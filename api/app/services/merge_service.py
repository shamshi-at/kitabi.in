"""Finding and merging duplicate authors and publishers.

The catalogue holds roughly a hundred redundant rows out of ~2,250 — "Perkins,
John" beside "John Perkins", "Patañjali." beside "Patanjali.", three separate
Vaikom Muhammad Basheers. They split one person's books across several pages,
make search look like it is malfunctioning, and are the reason author pages
cannot safely be indexed.

**Merging is destructive and a false merge is silent.** Conflating two real
people is worse than leaving a duplicate, and nobody notices it happened. So:

* only EXACT normalised-name matches merge automatically (owner decision) —
  in a catalogue this size an identical name is overwhelmingly one entity;
* everything softer (word-order, spelling, transliteration variants) is
  *proposed* and waits for a human;
* every merge is reversible by clearing one column, so a mistake is a correction
  rather than an excavation.

**The pointer, not a delete.** The loser keeps `merged_into_id` set to the
survivor, which is what lets its URL 301 rather than 404. Author pages may
already be indexed; a merge that breaks old URLs discards exactly the ranking it
was supposed to consolidate.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Author, Edition, MergeDismissal, Publisher, Series, Work
from app.models.work import work_authors
from app.services.search_rank import normalize

# How a candidate cluster was found. Only EXACT is safe to apply unattended.
EXACT = "exact"
WORD_ORDER = "word_order"
SPELLING = "spelling"

MODELS = {"authors": Author, "publishers": Publisher, "series": Series}


@dataclass
class Candidate:
    """One cluster of rows believed to be the same entity."""

    kind: str
    reason: str
    survivor_id: uuid.UUID
    survivor_name: str
    losers: list[tuple[uuid.UUID, str]] = field(default_factory=list)

    @property
    def auto_mergeable(self) -> bool:
        return self.reason == EXACT


def _key_exact(name: str) -> str:
    return normalize(name)


def _key_word_order(name: str) -> str:
    """Word set, order-insensitive — catches "Perkins, John" / "John Perkins"."""
    return " ".join(sorted(set(normalize(name).split())))


def _key_spelling(fold: str | None) -> str:
    """Word set of the spelling-folded form — catches accent and
    transliteration variants ("Kālaccuvaṭu" / "Kalaccuvatu")."""
    return " ".join(sorted(set(normalize(fold).split())))


async def _counts(db: AsyncSession, kind: str, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """How much each row carries — the primary survivor signal."""
    if not ids:
        return {}
    if kind == "authors":
        stmt = (
            select(work_authors.c.author_id, func.count(work_authors.c.work_id))
            .where(work_authors.c.author_id.in_(ids))
            .group_by(work_authors.c.author_id)
        )
    elif kind == "series":
        stmt = (
            select(Work.series_id, func.count(Work.id))
            .where(Work.series_id.in_(ids), Work.deleted_at.is_(None))
            .group_by(Work.series_id)
        )
    else:
        stmt = (
            select(Edition.publisher_id, func.count(Edition.id))
            .where(Edition.publisher_id.in_(ids), Edition.deleted_at.is_(None))
            .group_by(Edition.publisher_id)
        )
    return dict((await db.execute(stmt)).all())


def repeats_itself(name: str | None) -> bool:
    """Whether a name contains a multi-word run repeated back to back — the
    shape of a bad import ("Rev. William Rev. William Benham"), not of a fuller
    name. Only runs of two words or more count, so a name that genuinely says a
    word twice (Sri Sri Ravi Shankar) is left alone.
    """
    words = normalize(name).split()
    for size in range(2, len(words) // 2 + 1):
        for start in range(len(words) - 2 * size + 1):
            if words[start : start + size] == words[start + size : start + 2 * size]:
                return True
    return False


def pick_survivor(rows: list, counts: dict) -> object:
    """Which row wins. Deterministic, so proposing twice proposes the same thing.

    Most works first — that row already has the most inbound links and the most
    to lose. Then a name that doesn't repeat itself, because the longest-name
    rule below otherwise hands the tie to exactly the corrupted row it should
    reject (reported 12 Aug 2026: "Rev. William Rev. William Benham" was
    proposed as the survivor over "Rev. William Benham"). Then the longest name,
    because "Basheer, Vaikom Muhammad" carries more information than
    "V. M. Basheer" and a merge should not throw detail away. Then oldest, as a
    stable final tiebreak.

    Only a default. The reviewer picks the survivor in the console, and can fix
    the kept row's name before merging — no heuristic gets every name right.
    """
    return sorted(
        rows,
        key=lambda r: (
            -counts.get(r.id, 0),
            repeats_itself(r.name),
            -len(r.name or ""),
            r.created_at,
            str(r.id),
        ),
    )[0]


async def find_candidates(db: AsyncSession, kind: str) -> list[Candidate]:
    """Every duplicate cluster, strongest evidence first.

    A row already merged, or soft-deleted, is never a candidate — otherwise
    approving one merge would keep re-proposing it forever.
    """
    model = MODELS[kind]
    rows = list(
        (
            await db.execute(
                select(model).where(model.deleted_at.is_(None), model.merged_into_id.is_(None))
            )
        )
        .scalars()
        .all()
    )
    counts = await _counts(db, kind, [r.id for r in rows])
    dismissed = await _dismissed_pairs(db, kind)

    seen: set[uuid.UUID] = set()
    out: list[Candidate] = []

    # Strongest evidence first, and a row claimed by a stronger reason is not
    # offered again under a weaker one.
    for reason, keyfn in (
        (EXACT, lambda r: _key_exact(r.name)),
        (WORD_ORDER, lambda r: _key_word_order(r.name)),
        (SPELLING, lambda r: _key_spelling(r.name_fold)),
    ):
        groups: dict[str, list] = defaultdict(list)
        for row in rows:
            if row.id in seen:
                continue
            key = keyfn(row)
            if key:
                groups[key].append(row)
        for group in groups.values():
            if len(group) < 2:
                continue
            survivor = pick_survivor(group, counts)
            losers = [
                r
                for r in group
                if r.id != survivor.id and _pair(survivor.id, r.id) not in dismissed
            ]
            if not losers:
                # Every pairing here has already been rejected by a human. Mark
                # the whole group seen so a weaker matcher does not re-offer it.
                for r in group:
                    seen.add(r.id)
                continue
            for r in group:
                seen.add(r.id)
            out.append(
                Candidate(
                    kind=kind,
                    reason=reason,
                    survivor_id=survivor.id,
                    survivor_name=survivor.name,
                    losers=[(r.id, r.name) for r in losers],
                )
            )
    return out


# Fields worth rescuing from a row being merged away. A bio typed on the
# duplicate must not vanish because that row happened to lose.
_CARRY_OVER = {
    "authors": (
        "bio",
        "image_url",
        "primary_language",
        "pen_name",
        "external_id",
        "external_source",
        # An approved claim ("this reader IS this author") must survive the
        # duplicate row losing a merge — the verification was of the person.
        "linked_user_id",
    ),
    "publishers": ("logo_url", "primary_language", "external_id", "external_source"),
    "series": ("description", "primary_language", "external_id", "external_source"),
}


async def merge(db: AsyncSession, kind: str, survivor_id: uuid.UUID, loser_id: uuid.UUID) -> bool:
    """Fold `loser` into `survivor`. Returns False if the merge is not sane.

    Repoints references, rescues fields the survivor is missing, then soft
    deletes the loser and points it at the survivor.
    """
    if survivor_id == loser_id:
        return False
    model = MODELS[kind]
    survivor = await db.get(model, survivor_id)
    loser = await db.get(model, loser_id)
    if survivor is None or loser is None:
        return False
    if survivor.merged_into_id is not None or loser.merged_into_id is not None:
        # Never chain merges — a pointer to a pointer means a redirect hop, and
        # unmerging the middle row would silently strand the far one.
        return False

    if kind == "authors":
        # Repoint, but skip works already credited to the survivor or the
        # composite primary key collides.
        already = set(
            (
                await db.execute(
                    select(work_authors.c.work_id).where(work_authors.c.author_id == survivor_id)
                )
            )
            .scalars()
            .all()
        )
        moving = set(
            (
                await db.execute(
                    select(work_authors.c.work_id).where(work_authors.c.author_id == loser_id)
                )
            )
            .scalars()
            .all()
        )
        duplicated = moving & already
        if duplicated:
            await db.execute(
                work_authors.delete().where(
                    work_authors.c.author_id == loser_id,
                    work_authors.c.work_id.in_(duplicated),
                )
            )
        await db.execute(
            work_authors.update()
            .where(work_authors.c.author_id == loser_id)
            .values(author_id=survivor_id)
        )
    elif kind == "series":
        # The books move, and keep their positions: two rows for one series
        # hold the same ordering, so a merge should not renumber anything.
        await db.execute(
            update(Work).where(Work.series_id == loser_id).values(series_id=survivor_id)
        )
    else:
        await db.execute(
            update(Edition).where(Edition.publisher_id == loser_id).values(publisher_id=survivor_id)
        )

    for attr in _CARRY_OVER[kind]:
        if not getattr(survivor, attr, None) and getattr(loser, attr, None):
            setattr(survivor, attr, getattr(loser, attr))

    # Anything already pointing at the loser must be repointed at the survivor,
    # or merging a row that others were merged into creates a CHAIN:
    #   di-si-buks -> di-si-buks-3 -> dc-books
    # Redirect resolution does a single hop, so the far end of a chain silently
    # 404s — the exact failure the pointer exists to prevent. Keeping the graph
    # flat means every merged row always points directly at a live survivor.
    await db.execute(
        update(model).where(model.merged_into_id == loser_id).values(merged_into_id=survivor_id)
    )

    loser.merged_into_id = survivor_id
    loser.deleted_at = datetime.now(UTC)
    await db.flush()
    return True


async def unmerge(db: AsyncSession, kind: str, loser_id: uuid.UUID) -> bool:
    """Undo a merge: the row comes back, still without its works.

    Deliberately partial and honest about it. Restoring the row and its URL is
    the part that matters (a wrong merge otherwise leaves a person unreachable);
    re-splitting which book belonged to whom is a judgement no column recorded,
    so it is left to a human rather than guessed.
    """
    model = MODELS[kind]
    loser = await db.get(model, loser_id)
    if loser is None or loser.merged_into_id is None:
        return False
    loser.merged_into_id = None
    loser.deleted_at = None
    await db.flush()
    return True


async def auto_merge_exact(db: AsyncSession, kind: str, *, limit: int = 200) -> int:
    """Apply only the EXACT-name clusters. Returns how many rows were folded in.

    Owner decision: in a catalogue of this size an identical normalised name is
    overwhelmingly one entity, and every merge is reversible, so review adds
    delay without adding safety for this case alone.
    """
    merged = 0
    for candidate in await find_candidates(db, kind):
        if not candidate.auto_mergeable:
            continue
        for loser_id, _ in candidate.losers:
            if merged >= limit:
                break
            if await merge(db, kind, candidate.survivor_id, loser_id):
                merged += 1
    if merged:
        await db.commit()
    return merged


def _pair(a: uuid.UUID, b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    """Ordered, so "A is not B" and "B is not A" are one fact."""
    return (a, b) if str(a) < str(b) else (b, a)


async def _dismissed_pairs(db: AsyncSession, kind: str) -> set:
    rows = (
        await db.execute(
            select(MergeDismissal.left_id, MergeDismissal.right_id).where(
                MergeDismissal.kind == kind
            )
        )
    ).all()
    return {(left, right) for left, right in rows}


async def dismiss(
    db: AsyncSession, kind: str, a_id: uuid.UUID, b_id: uuid.UUID, by: uuid.UUID | None = None
) -> bool:
    """Record that two rows are NOT the same entity, so the queue can empty.

    Idempotent: dismissing the same pair twice is a no-op rather than an error,
    because a reviewer double-clicking a button is not an exceptional condition.
    """
    if a_id == b_id:
        return False
    left, right = _pair(a_id, b_id)
    existing = (
        await db.execute(
            select(MergeDismissal.id).where(
                MergeDismissal.kind == kind,
                MergeDismissal.left_id == left,
                MergeDismissal.right_id == right,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return True
    db.add(
        MergeDismissal(id=uuid.uuid4(), kind=kind, left_id=left, right_id=right, dismissed_by=by)
    )
    await db.flush()
    return True


async def resolve_merged(db: AsyncSession, kind: str, row) -> object | None:  # noqa: ANN001
    """The row a merged entity now points at, or None if it isn't merged."""
    if row is None or getattr(row, "merged_into_id", None) is None:
        return None
    return await db.get(MODELS[kind], row.merged_into_id)


async def canonical(db: AsyncSession, row) -> object | None:  # noqa: ANN001
    """The live row `row` stands for — itself when it is live, the survivor it
    was merged into when it isn't, None when it is a dead end.

    **The one rule for "which row does this name mean".** A merge is a decision
    a human made once in the console ("ഡി സി ബുക്സ് is DC Books"), and every
    place a free-text name or a remembered id turns back into a catalogue row
    has to honour it, or the merge only holds until the next cover is
    photographed: the extractor reads the loser's spelling, nothing recognises
    it, and a fresh duplicate opens next door — the exact row that was just
    folded away.

    One hop is enough by construction: `merge` repoints anything already
    aimed at a loser, so the graph stays flat (see the CHAIN note there).

    None has two causes and they are deliberately the same answer: a row that
    was soft-deleted without being merged points nowhere, and neither does one
    whose survivor has since gone. In both cases the caller holds a name that
    no longer names anything, which is what "None" means.
    """
    if row is None:
        return None
    target_id = getattr(row, "merged_into_id", None)
    if target_id is None:
        return row if row.deleted_at is None else None
    survivor = await db.get(type(row), target_id)
    if survivor is None or survivor.deleted_at is not None:
        return None
    return survivor
