"""Promotion serving — targeting resolution, language-variant selection, and
engagement events (docs/promotions-plan.md).

**Targeting is resolved here, on the server, always.** The device receives only
what it is eligible for. Filtering on the client would mean shipping every
campaign and every targeting rule to every install — which leaks commercial
plans to anyone with a proxy, and freezes retargeting behind an app release.

The two mechanisms stay separate: `matches()` decides *who is eligible*,
`pick_content()` decides *which words they see*.
"""

import hashlib
import json
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from sqlalchemy import Select, func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.edition import Edition
from app.models.genre import Genre
from app.models.library_entry import LibraryEntry
from app.models.profile import Profile
from app.models.promotion import (
    EVENT_DISMISS,
    EVENT_IMPRESSION,
    EVENT_KINDS,
    STATE_DRAFT,
    STATE_ENDED,
    STATE_LIVE,
    STATE_PAUSED,
    STATE_SCHEDULED,
    STATUS_DRAFT,
    STATUS_PAUSED,
    STATUS_PUBLISHED,
    Promotion,
    PromotionContent,
    PromotionEvent,
)
from app.models.work import Work, work_genres

# One reader can't report more than this in a single batch. Generous for a
# month offline, small enough that a malformed client can't flood the table.
MAX_EVENTS_PER_BATCH = 200

# Frequency defaults. `min_hours_between` is deliberately not zero: the same
# strip on every cold start is how a promotion becomes a grievance.
DEFAULT_MIN_HOURS_BETWEEN = 24


def _now() -> datetime:
    return datetime.now(UTC)


def _aware(value: datetime | None) -> datetime | None:
    """Postgres gives us tz-aware values; SQLite and hand-built test rows may
    not. Compare like with like rather than raising deep inside a filter."""
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=UTC)


# --------------------------------------------------------------------------
# Derived state
# --------------------------------------------------------------------------


def effective_state(promo: Promotion, now: datetime | None = None) -> str:
    """What the console shows and the serve query means.

    Only `status` is stored (the operator's intent); scheduled/live/ended fall
    out of the dates. Nothing runs on a timer to flip rows — so there is no day
    on which the timer didn't run and a finished campaign is still live.
    """
    if promo.status == STATUS_DRAFT:
        return STATE_DRAFT
    if promo.status == STATUS_PAUSED:
        return STATE_PAUSED
    now = now or _now()
    starts, ends = _aware(promo.starts_at), _aware(promo.ends_at)
    if starts is not None and starts > now:
        return STATE_SCHEDULED
    if ends is not None and ends <= now:
        return STATE_ENDED
    return STATE_LIVE


def live_window_clause(now: datetime) -> list:
    """The SQL half of `effective_state` — a campaign is servable when it's
    published and inside its window."""
    return [
        Promotion.deleted_at.is_(None),
        Promotion.status == STATUS_PUBLISHED,
        or_(Promotion.starts_at.is_(None), Promotion.starts_at <= now),
        or_(Promotion.ends_at.is_(None), Promotion.ends_at > now),
    ]


# --------------------------------------------------------------------------
# Reader facts + the targeting predicate
# --------------------------------------------------------------------------


@dataclass
class ReaderFacts:
    """Everything targeting can look at, for one reader.

    Materialised up front so `matches()` stays pure and synchronous — which is
    what lets the audience estimate reuse it verbatim instead of reimplementing
    the rules in SQL and drifting out of step with what actually gets served.
    """

    user_id: uuid.UUID
    languages: list[str] = field(default_factory=list)
    account_age_days: int = 0
    platform: str | None = None
    app_version: tuple[int, ...] | None = None
    library_size: int = 0
    statuses: set[str] = field(default_factory=set)
    genres: set[str] = field(default_factory=set)


def parse_version(raw: str | None) -> tuple[int, ...] | None:
    """'0.2.1' -> (0, 2, 1). Anything unparseable is None, which fails a
    version rule closed (see `matches`)."""
    if not raw:
        return None
    parts = raw.strip().split("+")[0].split("-")[0].split(".")
    out: list[int] = []
    for part in parts:
        if not part.isdigit():
            return None
        out.append(int(part))
    return tuple(out) or None


def _cmp_version(a: tuple[int, ...], b: tuple[int, ...]) -> int:
    length = max(len(a), len(b))
    a_pad = a + (0,) * (length - len(a))
    b_pad = b + (0,) * (length - len(b))
    return (a_pad > b_pad) - (a_pad < b_pad)


def rollout_bucket(promotion_id: uuid.UUID, user_id: uuid.UUID) -> int:
    """A stable 0–99 bucket per (campaign, reader).

    Stable is the whole point: a reader must always land on the same side of a
    partial rollout, or the promo flickers in and out between fetches and the
    metrics mean nothing. Hashed rather than random, and salted with the
    campaign id so a 10% rollout doesn't always pick the same tenth of readers.
    """
    digest = hashlib.sha256(f"{promotion_id}:{user_id}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 100


def matches(targeting: dict | None, facts: ReaderFacts) -> bool:
    """Does this reader qualify? Every key is optional; an absent key means
    "don't filter on this". All present keys must hold (AND); values within one
    key are OR.

    Unknown facts fail a rule **closed** — if a campaign targets Android and the
    build is too old to send `X-Platform`, that reader doesn't get it. Showing a
    promotion to someone you can't verify is the wrong direction to be wrong in.
    """
    t = targeting or {}

    if ids := t.get("reader_ids"):
        if str(facts.user_id) not in {str(i) for i in ids}:
            return False
    if excluded := t.get("exclude_reader_ids"):
        if str(facts.user_id) in {str(i) for i in excluded}:
            return False

    if languages := t.get("languages"):
        if not set(languages) & set(facts.languages or []):
            return False

    if platforms := t.get("platform"):
        if facts.platform is None or facts.platform not in platforms:
            return False

    if minimum := t.get("app_version_min"):
        wanted = parse_version(minimum)
        if wanted and (facts.app_version is None or _cmp_version(facts.app_version, wanted) < 0):
            return False
    if maximum := t.get("app_version_max"):
        wanted = parse_version(maximum)
        if wanted and (facts.app_version is None or _cmp_version(facts.app_version, wanted) > 0):
            return False

    if not _in_range(facts.account_age_days, t.get("account_age_days")):
        return False
    if not _in_range(facts.library_size, t.get("library_size")):
        return False

    if wanted_statuses := t.get("has_status"):
        if not set(wanted_statuses) & facts.statuses:
            return False
    if wanted_genres := t.get("genres"):
        if not set(wanted_genres) & facts.genres:
            return False

    return True


def matches_rollout(promo: Promotion, facts: ReaderFacts) -> bool:
    """Split out from `matches` because it needs the campaign id, and because
    the audience estimate reports it separately — "412 match, of whom 25% will
    see it" is two different numbers and conflating them hides one."""
    percent = (promo.targeting or {}).get("rollout_percent")
    if percent is None or percent >= 100:
        return True
    if percent <= 0:
        return False
    return rollout_bucket(promo.id, facts.user_id) < percent


def _in_range(value: int, rule: dict | None) -> bool:
    if not rule:
        return True
    if (minimum := rule.get("min")) is not None and value < minimum:
        return False
    if (maximum := rule.get("max")) is not None and value > maximum:
        return False
    return True


def needed_facts(targetings: list[dict]) -> set[str]:
    """Which expensive facts any of these campaigns actually needs — so a
    reader whose only live campaign targets a language never pays for the
    genre join."""
    needed: set[str] = set()
    for t in targetings:
        if not t:
            continue
        if t.get("library_size"):
            needed.add("library_size")
        if t.get("has_status"):
            needed.add("statuses")
        if t.get("genres"):
            needed.add("genres")
    return needed


# --------------------------------------------------------------------------
# Building reader facts
# --------------------------------------------------------------------------


async def build_facts(
    db: AsyncSession,
    profile: Profile,
    *,
    platform: str | None,
    app_version: str | None,
    needs: set[str],
    now: datetime | None = None,
) -> ReaderFacts:
    now = now or _now()
    created = _aware(profile.created_at) or now
    facts = ReaderFacts(
        user_id=profile.id,
        languages=list(profile.preferred_languages or []),
        account_age_days=max(0, (now - created).days),
        platform=platform,
        app_version=parse_version(app_version),
    )
    if needs & {"library_size", "statuses"}:
        rows = (
            await db.execute(
                select(LibraryEntry.status, func.count())
                .where(LibraryEntry.user_id == profile.id, LibraryEntry.deleted_at.is_(None))
                .group_by(LibraryEntry.status)
            )
        ).all()
        facts.library_size = sum(count for _, count in rows)
        facts.statuses = {status for status, _ in rows}
    if "genres" in needs:
        rows = (
            await db.execute(_reader_genres_stmt().where(LibraryEntry.user_id == profile.id))
        ).all()
        facts.genres = {name for _, name in rows}
    return facts


def _reader_genres_stmt() -> Select:
    """(user_id, genre name) for every genre represented in a reader's shelf.
    Selected as pairs so the single-reader path and the bulk estimate can share
    one join — the rules must not drift between them."""
    return (
        select(LibraryEntry.user_id, Genre.name)
        .select_from(LibraryEntry)
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .join(Work, Work.id == Edition.work_id)
        .join(work_genres, work_genres.c.work_id == Work.id)
        .join(Genre, Genre.id == work_genres.c.genre_id)
        .where(LibraryEntry.deleted_at.is_(None))
        .distinct()
    )


# --------------------------------------------------------------------------
# Content variants
# --------------------------------------------------------------------------


def pick_content(contents: list[PromotionContent], languages: list[str]) -> PromotionContent | None:
    """The reader's first listed language that has a variant, else the default.

    Returns None when a campaign has neither — in which case it is skipped
    entirely, rather than shown to someone in a language they didn't ask for.
    """
    by_language = {c.language: c for c in contents}
    for language in languages or []:
        if language in by_language:
            return by_language[language]
    return by_language.get(None)


# --------------------------------------------------------------------------
# The serve path
# --------------------------------------------------------------------------


async def resolve_for_reader(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    platform: str | None = None,
    app_version: str | None = None,
    now: datetime | None = None,
) -> list[dict]:
    """Every promotion this reader should see right now, already resolved:
    targeting applied, variant chosen, dismissals and caps excluded, capped at
    one per placement."""
    now = now or _now()
    profile = await db.get(Profile, user_id)
    if profile is None or profile.deleted_at is not None or profile.promotions_opt_out:
        return []

    candidates = (
        (
            await db.execute(
                select(Promotion)
                .where(*live_window_clause(now))
                .order_by(Promotion.priority.desc(), Promotion.starts_at.asc().nulls_last())
            )
        )
        .scalars()
        .all()
    )
    if not candidates:
        return []

    facts = await build_facts(
        db,
        profile,
        platform=platform,
        app_version=app_version,
        needs=needed_facts([c.targeting for c in candidates]),
        now=now,
    )

    ids = [c.id for c in candidates]
    history = await _reader_history(db, user_id, ids)
    contents = await _contents_by_promotion(db, ids)

    resolved: list[dict] = []
    filled: set[str] = set()
    for promo in candidates:
        if promo.placement in filled:
            continue
        if not _frequency_allows(promo, history.get(promo.id, {}), now):
            continue
        if not matches(promo.targeting, facts) or not matches_rollout(promo, facts):
            continue
        content = pick_content(contents.get(promo.id, []), facts.languages)
        if content is None:
            continue
        resolved.append(_to_payload(promo, content))
        filled.add(promo.placement)
    return resolved


async def _reader_history(
    db: AsyncSession, user_id: uuid.UUID, promotion_ids: list[uuid.UUID]
) -> dict[uuid.UUID, dict[str, tuple[int, datetime | None]]]:
    """One query for every candidate: per (promotion, kind), how many and how
    recently."""
    rows = (
        await db.execute(
            select(
                PromotionEvent.promotion_id,
                PromotionEvent.kind,
                func.count(),
                func.max(PromotionEvent.occurred_at),
            )
            .where(
                PromotionEvent.user_id == user_id,
                PromotionEvent.promotion_id.in_(promotion_ids),
            )
            .group_by(PromotionEvent.promotion_id, PromotionEvent.kind)
        )
    ).all()
    out: dict[uuid.UUID, dict[str, tuple[int, datetime | None]]] = {}
    for promotion_id, kind, count, last in rows:
        out.setdefault(promotion_id, {})[kind] = (count, _aware(last))
    return out


async def _contents_by_promotion(
    db: AsyncSession, promotion_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[PromotionContent]]:
    rows = (
        (
            await db.execute(
                select(PromotionContent).where(PromotionContent.promotion_id.in_(promotion_ids))
            )
        )
        .scalars()
        .all()
    )
    out: dict[uuid.UUID, list[PromotionContent]] = {}
    for row in rows:
        out.setdefault(row.promotion_id, []).append(row)
    return out


def _frequency_allows(
    promo: Promotion, history: dict[str, tuple[int, datetime | None]], now: datetime
) -> bool:
    freq = promo.frequency or {}
    dismiss_count, dismissed_at = history.get(EVENT_DISMISS, (0, None))
    if dismiss_count:
        redisplay = freq.get("redisplay_after_days")
        if redisplay is None or dismissed_at is None:
            return False
        if now < dismissed_at + timedelta(days=redisplay):
            return False

    seen, last_seen = history.get(EVENT_IMPRESSION, (0, None))
    cap = freq.get("max_impressions")
    if cap is not None and seen >= cap:
        return False
    gap = freq.get("min_hours_between", DEFAULT_MIN_HOURS_BETWEEN)
    if gap and last_seen is not None and now < last_seen + timedelta(hours=gap):
        return False
    return True


def _to_payload(promo: Promotion, content: PromotionContent) -> dict:
    freq = promo.frequency or {}
    return {
        "id": str(promo.id),
        "kind": promo.kind,
        "card_style": promo.card_style,
        "placement": promo.placement,
        "sponsor": promo.sponsor,
        "language": content.language,
        "headline": content.headline,
        "body": content.body,
        "cta_label": content.cta_label,
        "image_url": content.image_url,
        "action_type": content.action_type,
        "action_value": content.action_value,
        "work_id": str(promo.work_id) if promo.work_id else None,
        "edition_id": str(promo.edition_id) if promo.edition_id else None,
        "dismissible": bool(freq.get("dismissible", True)),
        "priority": promo.priority,
        "expires_at": _aware(promo.ends_at).isoformat() if promo.ends_at else None,
    }


def payload_version(promotions: list[dict]) -> str:
    """A short hash of the resolved payload, returned as an ETag so the app's
    poll is a 304 and a few bytes in the normal case."""
    blob = json.dumps(promotions, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


# --------------------------------------------------------------------------
# Events
# --------------------------------------------------------------------------


async def record_events(db: AsyncSession, user_id: uuid.UUID, events: list) -> int:
    """Append impression/click/dismiss rows. Idempotent on the client-generated
    id, so a retried batch is discarded rather than double-counted."""
    if not events:
        return 0
    known = set(
        (
            await db.execute(
                select(Promotion.id).where(
                    Promotion.id.in_({e.promotion_id for e in events}),
                    Promotion.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    rows = [
        {
            "id": e.id,
            "promotion_id": e.promotion_id,
            "user_id": user_id,
            "kind": e.kind,
            "language": e.language,
            "occurred_at": e.occurred_at,
        }
        for e in events[:MAX_EVENTS_PER_BATCH]
        if e.kind in EVENT_KINDS and e.promotion_id in known
    ]
    if not rows:
        return 0
    # A campaign deleted between the device recording an event and reporting it
    # simply drops the row — never a 4xx, or the app's outbox would retry a
    # batch that can never succeed.
    await db.execute(
        pg_insert(PromotionEvent).values(rows).on_conflict_do_nothing(index_elements=["id"])
    )
    await db.commit()
    return len(rows)


# --------------------------------------------------------------------------
# Audience estimate (admin console)
# --------------------------------------------------------------------------


async def estimate_audience(db: AsyncSession, targeting: dict | None) -> dict:
    """How many readers match, and the total it's drawn from.

    Reuses `matches()` rather than reimplementing the rules in SQL: the whole
    value of the estimate is that it agrees with what will actually be served,
    and two implementations of the same rules drift apart the first time one is
    edited. Facts for *every* reader are loaded in three queries regardless of
    reader count, then filtered in Python.

    # SCALE: at a few hundred thousand readers, precompute these facts into a
    # summary table on a schedule instead. In Postgres, not Redis (rule 8).
    """
    now = _now()
    everyone = (
        (await db.execute(select(Profile).where(Profile.deleted_at.is_(None)))).scalars().all()
    )
    # The denominator is the *addressable* pool, not every account. Counting
    # opted-out readers in the total but not in the matches makes "Everyone" and
    # "of N readers" two different numbers on the same panel, which reads as a
    # bug even when both are individually right.
    profiles = [p for p in everyone if not p.promotions_opt_out]
    total = len(profiles)
    opted_out = len(everyone) - total
    if not profiles:
        return {"matched": 0, "total": 0, "opted_out": opted_out}

    needs = needed_facts([targeting or {}])
    sizes: dict[uuid.UUID, int] = {}
    statuses: dict[uuid.UUID, set[str]] = {}
    genres: dict[uuid.UUID, set[str]] = {}

    if needs & {"library_size", "statuses"}:
        for user_id, status, count in (
            await db.execute(
                select(LibraryEntry.user_id, LibraryEntry.status, func.count())
                .where(LibraryEntry.deleted_at.is_(None))
                .group_by(LibraryEntry.user_id, LibraryEntry.status)
            )
        ).all():
            sizes[user_id] = sizes.get(user_id, 0) + count
            statuses.setdefault(user_id, set()).add(status)
    if "genres" in needs:
        for user_id, name in (await db.execute(_reader_genres_stmt())).all():
            genres.setdefault(user_id, set()).add(name)

    matched = 0
    for profile in profiles:
        created = _aware(profile.created_at) or now
        facts = ReaderFacts(
            user_id=profile.id,
            languages=list(profile.preferred_languages or []),
            account_age_days=max(0, (now - created).days),
            # Platform and version are per-install, not per-reader — a reader
            # with two phones has two. The estimate therefore can't honour
            # those rules, and says so in the console rather than quietly
            # reporting a number that ignores them.
            platform=None,
            app_version=None,
            library_size=sizes.get(profile.id, 0),
            statuses=statuses.get(profile.id, set()),
            genres=genres.get(profile.id, set()),
        )
        countable = dict(targeting or {})
        countable.pop("platform", None)
        countable.pop("app_version_min", None)
        countable.pop("app_version_max", None)
        if matches(countable, facts):
            matched += 1

    rollout = (targeting or {}).get("rollout_percent")
    return {
        "matched": matched,
        "total": total,
        "opted_out": opted_out,
        "rollout_percent": rollout,
        "ignores_device_rules": bool(
            (targeting or {}).keys() & {"platform", "app_version_min", "app_version_max"}
        ),
    }
