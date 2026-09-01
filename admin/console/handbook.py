"""The operator's handbook, served inside the console itself.

Written for someone who has never seen the code — the person who will actually
sit with this console every day. It lives here, not in a PDF or a shared
document, for three reasons that decided the format:

* a PDF goes stale the moment a screen changes, and nobody notices;
* the handbook can **link straight at the screen it describes**, and every
  screen can link back at its own page ("? Help" in the top bar), so reading and
  doing are one click apart; and
* it is behind the same sign-in as everything else, so it can describe real
  operational detail without that detail being public.

The content is data, not templates, so one renderer draws every page, the
contents list is generated rather than maintained by hand, and every topic is
searchable from the console's global search box.

Formatting: bodies are plain text with a deliberately tiny markup — `**bold**`,
`[label](/href)` and `` `code` `` — rendered by `fmt()`, which **escapes first**
and only then puts our own tags back. Content here is written by us, but a
handbook that can only be edited safely by someone who remembers to escape is a
handbook that will one day be edited by someone who doesn't.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field

from markupsafe import Markup

# Minimum role a topic is shown to, using the console's own ranking.
RANK = {"moderator": 0, "editor": 1, "super_admin": 2}

_BOLD = re.compile(r"\*\*(.+?)\*\*")
_CODE = re.compile(r"`([^`]+)`")
_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def fmt(text: str) -> Markup:
    """Escape `text`, then apply the handbook's three inline marks.

    Links are restricted to console-internal paths (`/…`) — the handbook has no
    reason to send an operator off-site, and an operator has every reason to
    trust a link inside their own admin console.
    """
    out = html.escape(text)
    out = _BOLD.sub(r"<b>\1</b>", out)
    out = _CODE.sub(r"<code>\1</code>", out)

    def link(m: re.Match) -> str:
        label, href = m.group(1), m.group(2)
        if not href.startswith("/"):
            return label
        return f'<a href="{href}">{label}</a>'

    out = _LINK.sub(link, out)
    return Markup(out)


@dataclass(frozen=True)
class Section:
    """One anchored chunk of a topic. `id` is the URL fragment, so every heading
    in the handbook is a link somebody can paste into a message."""

    id: str
    heading: str
    body: tuple[str, ...] = ()
    steps: tuple[str, ...] = ()
    # A short "careful" box. Used sparingly: a page of warnings is a page nobody
    # reads.
    warn: str | None = None


@dataclass(frozen=True)
class Topic:
    slug: str
    title: str
    summary: str
    role: str = "moderator"
    # The console screen this topic is about, so the page can offer "open it".
    screen: str | None = None
    sections: tuple[Section, ...] = field(default_factory=tuple)

    def search_text(self) -> str:
        parts = [self.title, self.summary]
        for s in self.sections:
            parts += [s.heading, *s.body, *s.steps]
        return " ".join(parts).lower()


TOPICS: tuple[Topic, ...] = (
    Topic(
        slug="start",
        title="Start here",
        summary="What this console is, what you are responsible for, and a daily routine.",
        sections=(
            Section(
                "what",
                "What Kitabi is",
                (
                    "Kitabi is a personal library app. People add the books they own, track what "
                    "they are reading, lend books to friends, and — if they choose to — write "
                    "reviews and make their shelf public. There is also a public website, "
                    "kitabi.in, which shows the books, authors and publishers everyone shares.",
                    "Two kinds of information live side by side, and the difference decides "
                    "almost everything you do here. **The catalogue is shared** — one entry for a "
                    "book, seen by everyone, editable by readers. **A reader's library is "
                    "private** — their shelf, their notes, their reading progress. This console "
                    "gives you full control of the shared half and almost none of the private "
                    "half, on purpose.",
                ),
            ),
            Section(
                "job",
                "What your job is here",
                ("Three things, in order of how often you will do them:",),
                steps=(
                    "**Clear the queues.** Anything with a red number beside it in the left-hand "
                    "menu is waiting for a human decision. Work through them.",
                    "**Look at what readers added.** New books, authors and cover photos go "
                    "public straight away. [New in catalog](/moderation/incoming) is where you "
                    "check them.",
                    "**Answer for the people.** Suspend an account that is causing harm, hide a "
                    "profile with an offensive name, and put things back when you were wrong.",
                ),
            ),
            Section(
                "routine",
                "A daily routine that works",
                (),
                steps=(
                    "Open the [Dashboard](/). Read the top strip — is anything obviously odd?",
                    "Look at **Waiting on you**. Anything that isn't “clear”, open it and "
                    "clear it.",
                    "Open [New in catalog](/moderation/incoming), set the period to the last day, "
                    "and skim what readers added. Tick **Reviewed** as you go.",
                    "Once a week, open [Uploaded images](/moderation/images) and look at the "
                    "pictures readers have uploaded.",
                    "Once a week, glance at [Service health](/system) — is anything costing more "
                    "than usual?",
                ),
            ),
            Section(
                "roles",
                "The three roles",
                (
                    "**Moderator** — the queues, readers, and the audit log. Cannot change the "
                    "catalogue or publish anything to readers' phones.",
                    "**Editor** — everything a moderator can do, plus the catalogue (books, "
                    "authors, publishers, series, buy links), the new-content and image reviews, "
                    "campaigns, and service health.",
                    "**Super admin** — everything, plus creating and removing other admins.",
                    "If a menu item isn't there, your role doesn't include it. That is not a "
                    "fault — ask a super admin if you think you need it.",
                ),
            ),
            Section(
                "safe",
                "Nothing here is truly destructive",
                (
                    "Almost every action in this console is reversible, and every single one is "
                    "written into the [audit log](/audit) with your name against it. Deleting a "
                    "book hides it rather than destroying it. Suspending a reader keeps all their "
                    "data. Removing a picture keeps its address in the log so it can be put back.",
                    "So: act. A wrong decision that you notice and undo is a much smaller problem "
                    "than a queue nobody touches for a month.",
                ),
                warn="The two things you cannot undo yourself are **merging two records "
                "together** (an editor can unmerge, but any hand edits made afterwards stay) and "
                "**removing another admin's access**. Slow down for those two.",
            ),
        ),
    ),
    Topic(
        slug="dashboard",
        title="The dashboard",
        summary="Every number on the front page, in plain English.",
        screen="/",
        sections=(
            Section(
                "live",
                "The dark panel: right now",
                (
                    "The big number is how many people have a reading timer running **this "
                    "minute**. Under it: how many different books that is, and how long the "
                    "longest sitting has been going. It refreshes by itself every twenty "
                    "seconds — you never need to reload the page.",
                    "It deliberately does not say *who* is reading *what*. The console never "
                    "opens a reader's shelf or reading progress, and a live list of names would "
                    "be exactly that with a nicer frame around it. The count is what tells you "
                    "the service is alive.",
                    "This is the one number that is genuinely live. Everything else on the page "
                    "is counted up to a few minutes ago.",
                ),
            ),
            Section(
                "today",
                "The six tiles: today",
                (
                    "**Active readers · 24h** — how many different people's phones have sent "
                    "anything to Kitabi in the last day. The closest thing we have to “people who "
                    "used the app today”.",
                    "**New readers today**, **Books shelved today**, **Works added today**, "
                    "**Reviews today** — counted from midnight UTC, which is 5:30am in India. So "
                    "early in the Indian morning these will look small; that is the clock, not a "
                    "problem.",
                    "**Minutes read today** — all reading time logged by everyone today, added up.",
                ),
            ),
            Section(
                "trends",
                "Trends and the growth chart",
                (
                    "The four cards under **Trends** count the last 7, 28 or 90 days — you choose "
                    "with the buttons. Under each number is the change against the period before "
                    "it, so “▲ 12 (30%)” on the 28-day view means twelve more than the previous "
                    "28 days.",
                    "The chart below draws the same four things per day. Hover anywhere on it and "
                    "the day's figures appear. The shaded line is new readers.",
                    "A flat line is not necessarily bad — Kitabi is small, and single-digit days "
                    "are normal. What matters is the direction over weeks.",
                ),
            ),
            Section(
                "waiting",
                "Waiting on you, and catalogue health",
                (
                    "**Waiting on you** repeats the queues from the left menu with an Open button "
                    "beside each. If everything says “clear”, you are done for the day.",
                    "**Catalogue health** shows how much of the catalogue has a cover, a "
                    "description and an ISBN. Click any bar to get the list of books still "
                    "missing that thing — this is the best source of useful work when the queues "
                    "are empty.",
                ),
            ),
            Section(
                "feeds",
                "The two feeds at the bottom",
                (
                    "**Newest readers** — the most recent sign-ups. Click a name to open their "
                    "account.",
                    "**Newest in the catalogue** — the most recent books, authors and publishers, "
                    "and who added each one. This is a preview of "
                    "[New in catalog](/moderation/incoming), which is the full version with the "
                    "review ticks.",
                ),
            ),
        ),
    ),
    Topic(
        slug="incoming",
        title="New in catalog",
        summary="Reviewing what readers added to the shared catalogue before anyone complains.",
        role="editor",
        screen="/moderation/incoming",
        sections=(
            Section(
                "why",
                "Why this screen exists",
                (
                    "Any signed-in reader can add a book, an author, a publisher or an edition, "
                    "and it appears on the public website immediately. Nobody approves it first — "
                    "that is deliberate, because asking permission to add your own book would "
                    "make the app useless.",
                    "Every other queue in this console waits for someone to *complain*. This one "
                    "doesn't. It is the screen where you catch a nonsense title, a joke author or "
                    "a mis-typed publisher before a reader ever sees it.",
                ),
            ),
            Section(
                "using",
                "How to work through it",
                (),
                steps=(
                    "Set **Period** to cover since you last looked (a day, a week).",
                    "Leave **Show** on “Not yet reviewed” so you only see what nobody has checked.",
                    "Click a row's name to open the full record and look at it properly.",
                    "Come back and press **Reviewed ✓**. The row disappears from your list.",
                    "If something is wrong, fix it on the record's own page — rename it, merge it "
                    "into the right one, or delete it.",
                ),
            ),
            Section(
                "looking-for",
                "What you are looking for",
                (
                    "**Gibberish or test entries** — “asdf”, “test book”, a title that is one "
                    "letter.",
                    "**A book that already exists** under a slightly different name. Rename or "
                    "merge rather than delete, so any reader who already shelved it keeps it.",
                    "**An author who is really a publisher**, or a publisher that is really a "
                    "series. Easy honest mistakes on a small phone screen.",
                    "**Anything offensive** in a title, name or description.",
                    "**A real book you have never heard of** — that is not a problem. Kitabi "
                    "exists for regional and translated books nobody else catalogues.",
                ),
            ),
            Section(
                "marks",
                "What the tick means",
                (
                    "**Reviewed ✓** records that you looked, with your name and the time, in the "
                    "[audit log](/audit). It does not approve anything or change the record — the "
                    "book was already public. It only stops two people reading the same rows.",
                    "Publishers and editions show no contributor. That is not missing data being "
                    "hidden from you: Kitabi never recorded who created those two kinds. Books "
                    "and authors do show who added them.",
                ),
            ),
        ),
    ),
    Topic(
        slug="images",
        title="Uploaded images",
        summary="Cover photos and portraits readers upload — the fastest way to get hurt.",
        role="editor",
        screen="/moderation/images",
        sections=(
            Section(
                "why",
                "Why this needs a human",
                (
                    "When a reader adds a book, they can photograph its cover with their phone. "
                    "That photo goes straight onto the public website. There is no filter of any "
                    "kind between the camera and the world.",
                    "Almost all of them are exactly what they claim to be — a book on a table. "
                    "The point of this screen is the handful that aren't.",
                ),
            ),
            Section(
                "using",
                "How to work through it",
                (),
                steps=(
                    "Set the period and scan the grid. It is deliberately a grid of pictures — "
                    "you are looking, not reading.",
                    "Anything you're unsure about, click the title to open the record it belongs "
                    "to and see the context.",
                    "Press **Remove** on anything that should not be public.",
                ),
            ),
            Section(
                "remove",
                "What Remove does",
                (
                    "It takes the picture off that record straight away, on the website and in "
                    "the app. The picture's address is written into the [audit log](/audit), so "
                    "if you were wrong, a developer can put the exact same picture back.",
                    "You do not need to be certain. Removing a good cover is a small, fixable "
                    "mistake; leaving an obscene one up is not.",
                ),
                warn="A photograph of a **person** — not a book — deserves a second look. If it "
                "might be a picture of a child, remove it and tell the owner the same day.",
            ),
            Section(
                "empty",
                "If the screen says it isn't available",
                (
                    "That means this console isn't connected to the picture store. The website is "
                    "fine and readers are unaffected — this screen simply has nothing it can show "
                    "you. Tell a developer; it is a settings change, not an outage.",
                ),
            ),
        ),
    ),
    Topic(
        slug="reports",
        title="Reported content",
        summary="Reviews that readers have flagged as abusive, and what to do about them.",
        screen="/moderation/reports",
        sections=(
            Section(
                "what",
                "What lands here",
                (
                    "Readers can flag a **public review** written by another reader. Nothing else "
                    "in Kitabi can be reported — not books, not names, not pictures. If several "
                    "people flag the same review, it appears once, with the number of flags.",
                    "You see the review's text, who wrote it, and what book or series it was "
                    "about. You need all three: “this is rubbish” about a book is a review; the "
                    "same words about an author may not be.",
                ),
            ),
            Section(
                "deciding",
                "Deciding",
                (
                    "**Uphold** if the review contains abuse, hate, threats, someone's private "
                    "information, spam or advertising, or is plainly not about the book.",
                    "**Dismiss** if it is a harsh but honest opinion. A one-star review with "
                    "blunt words is exactly what a review site is for. Disliking the book, the "
                    "author or the translation is not a violation.",
                    "When you genuinely can't decide, uphold it and tell the owner. It is "
                    "reversible.",
                ),
            ),
            Section(
                "effect",
                "What each button actually does",
                (
                    "**Uphold** hides the review from the app and the website. It is not deleted "
                    "— the text stays in the database and can be brought back. The reader is not "
                    "told, and is not suspended.",
                    "**Dismiss** closes the report and leaves the review exactly as it was.",
                    "Either way the reports on that review are closed, so it leaves your queue.",
                    "If the same person keeps writing abusive reviews, that is a matter for their "
                    "[reader account](/readers), not for this screen.",
                ),
            ),
        ),
    ),
    Topic(
        slug="claims",
        title="Author claims",
        summary="“This is me” — a reader saying they are the author of a book.",
        screen="/moderation/claims",
        sections=(
            Section(
                "what",
                "What a claim is",
                (
                    "A reader has pressed “This is me” on an author in the catalogue. If you "
                    "approve it, that author entry is linked to their account and they are shown "
                    "as the verified author.",
                    "Until you decide, nothing changes for anyone else. Only the claimant sees a "
                    "“pending review” note.",
                ),
            ),
            Section(
                "deciding",
                "How to decide",
                (
                    "This is an identity claim, so treat it as one. Approve when the evidence is "
                    "real: an email address on the publisher's domain, a matching public profile "
                    "the person clearly controls, a message from the publisher.",
                    "A matching name is not evidence. Neither is enthusiasm.",
                    "When in doubt, leave it pending and ask the owner. There is no deadline, and "
                    "a wrongly approved claim hands someone control over another writer's "
                    "identity on the site.",
                ),
                warn="Approving a claim for a well-known author is exactly the case where you "
                "should stop and check with the owner first.",
            ),
        ),
    ),
    Topic(
        slug="edits",
        title="Suggested edits",
        summary="Readers proposing corrections to a book someone else added.",
        role="editor",
        screen="/moderation/edits",
        sections=(
            Section(
                "what",
                "What these are",
                (
                    "When a reader improves a book entry that somebody else created, the change "
                    "is not applied straight away — it waits here as a suggestion. You see the "
                    "old value and the new one side by side.",
                    "Most are genuinely helpful: a missing subtitle, a proper description, a "
                    "corrected spelling.",
                ),
            ),
            Section(
                "deciding",
                "Approving and rejecting",
                (
                    "**Approve** when the new version is more accurate or more complete. You are "
                    "not judging writing style — a plain description is better than none.",
                    "**Reject** when it is wrong, when it is an opinion (“best novel ever "
                    "written” is not a description), or when it is about a different book.",
                    "If the suggestion is half right, approve nothing and edit the book yourself "
                    "on its own page. That is quicker than a conversation.",
                ),
            ),
        ),
    ),
    Topic(
        slug="merges",
        title="Duplicate review",
        summary="Two entries for the same author, publisher or book — folding them into one.",
        screen="/moderation/merges",
        sections=(
            Section(
                "what",
                "What the queue holds",
                (
                    "Kitabi automatically folds together entries that are *exactly* the same. "
                    "Everything else — the near-misses — comes here, because only a person can "
                    "tell “O. V. Vijayan” and “O V Vijayan” (the same writer) from two different "
                    "people with similar names.",
                ),
            ),
            Section(
                "using",
                "How to decide safely",
                (),
                steps=(
                    "Click each name to **peek** — a popup showing what that entry actually has "
                    "against it. Two people with one name are told apart by their books, never by "
                    "their spelling.",
                    "If they are the same, choose which spelling to keep. Keep the correct, fully "
                    "punctuated one.",
                    "Merge. Everything attached to the other entry moves across; old links keep "
                    "working.",
                    "If they are different people, dismiss the pair so it stops coming back.",
                ),
                warn="Merging moves other readers' ratings, reviews and shelves. Peek at both "
                "before you press it. An editor can unmerge, but any edits made after the merge "
                "do not come apart cleanly.",
            ),
        ),
    ),
    Topic(
        slug="catalog",
        title="The catalogue",
        summary="Books, editions, authors, publishers, series and buy links.",
        role="editor",
        screen="/catalog",
        sections=(
            Section(
                "work-edition",
                "Work and edition — the one idea to learn",
                (
                    "A **work** is the book as an idea: *Chemmeen*, written by Thakazhi. A "
                    "reader's rating and review belong to the work.",
                    "An **edition** is a physical printing: the 1956 hardback, the 2011 DC Books "
                    "paperback, the Malayalam original, the English translation. The cover, the "
                    "ISBN and the page count belong to the edition.",
                    "This matters because a reader owns an *edition*. If a book's page count "
                    "looks wrong, you are almost always looking at the wrong edition, not at a "
                    "bug.",
                ),
            ),
            Section(
                "finding",
                "Finding things",
                (
                    "The search box at the top of every page searches everything at once — books, "
                    "authors, publishers, readers — and understands typos and both scripts, so "
                    "“chemmeen” finds “ചെമ്മീൻ”. Press `/` anywhere to jump into it.",
                    "The catalogue page's own filters narrow by language, type and what is "
                    "missing. The “missing a cover / description / ISBN” counts are the best "
                    "to-do list in the console.",
                ),
            ),
            Section(
                "editing",
                "Editing",
                (
                    "Open a book to edit its details, set its series, add a buy link to an "
                    "edition, or delete it. Everything you change is logged.",
                    "**Delete** is a soft delete — the book stops appearing but is not destroyed. "
                    "Kitabi refuses to delete a book that readers have shelved, rated or "
                    "reviewed, and tells you so. That refusal is correct: deleting it would take "
                    "the book off somebody's shelf.",
                ),
            ),
            Section(
                "buy-links",
                "Buy links",
                (
                    "[Buy links](/catalog/buy-links) is a worklist of editions with no shop link "
                    "yet. Adding one puts a “buy” button on the book's public page. Paste the "
                    "normal product address; Kitabi handles the rest.",
                ),
            ),
        ),
    ),
    Topic(
        slug="promotions",
        title="Campaigns",
        summary="Messages that appear on readers' home screens inside the app.",
        role="editor",
        screen="/promotions",
        sections=(
            Section(
                "what",
                "What a campaign is",
                (
                    "A banner or a card on the app's home screen. This is the only part of the "
                    "console that puts something in front of every reader, so it is the part to "
                    "be slowest with.",
                    "The composer shows a live preview of a phone as you type. What you see is "
                    "what they get.",
                ),
            ),
            Section(
                "audience",
                "Choosing who sees it",
                (
                    "You can narrow by language, phone type, how long they have been a reader, "
                    "how many books they have, what they are reading, and more. The estimate "
                    "updates as you narrow, so you always know roughly how many people you are "
                    "about to talk to.",
                    "A campaign can carry different wording per language — one campaign, not two "
                    "— so a Malayalam reader gets Malayalam.",
                ),
            ),
            Section(
                "safety",
                "Before you publish",
                (),
                steps=(
                    "Read it out loud. Typos are permanent in a way a website's are not.",
                    "Check the link. Press it in the preview.",
                    "Check the dates and the frequency cap.",
                    "Publish. If it is wrong, **Stop now** takes it down immediately — readers' "
                    "phones pick that up on their next refresh.",
                ),
                warn="Readers can switch promotions off entirely in their profile, and Kitabi "
                "honours that. Never work around it.",
            ),
        ),
    ),
    Topic(
        slug="readers",
        title="Readers",
        summary="Finding an account, what you can see, and the two moderation actions.",
        screen="/readers",
        sections=(
            Section(
                "finding",
                "Finding someone",
                (
                    "Search by name, @handle or email. The filters answer the questions you "
                    "actually have: who is suspended, who joined this week, whose profile is "
                    "public. Long lists page at the bottom.",
                ),
            ),
            Section(
                "seeing",
                "What you can and cannot see",
                (
                    "You can see what they have already made public — their name, handle, whether "
                    "their profile and library are public — plus counts of what they have "
                    "contributed, when they last used the app, and what kind of phone they use.",
                    "You **cannot** see their shelf, their private notes, their reading progress, "
                    "or reviews they haven't published. Not “you shouldn't” — the console has no "
                    "screen that shows them.",
                ),
            ),
            Section(
                "hide-profile",
                "Hide public profile — the gentle action",
                (
                    "Use this for an offensive display name, handle or picture, or when someone "
                    "has made public something they clearly shouldn't have.",
                    "It takes their public page off kitabi.in, along with their shared library "
                    "and any public reviews. **Their app keeps working normally** — their own "
                    "library, reading and lending are untouched.",
                    "Press **Make profile public again** to undo it, exactly as it was.",
                ),
            ),
            Section(
                "suspending",
                "Suspend — the serious action",
                (
                    "Suspension locks the account out of the app entirely. Use it for harassment, "
                    "repeated abuse after a warning, spam, or deliberate vandalism of the "
                    "catalogue.",
                    "Everything they have is kept. Lifting the suspension gives it all back, "
                    "instantly.",
                    "Tell the owner when you suspend someone. A suspended reader will email, and "
                    "whoever answers needs to know why.",
                ),
                warn="There is no delete-account button, and that is on purpose. If a reader asks "
                "for their account to be erased, pass it to the owner — a real erasure is a "
                "careful operation across several systems, not a click.",
            ),
        ),
    ),
    Topic(
        slug="admins",
        title="Admin users",
        summary="Adding, changing and removing the people who can use this console.",
        role="super_admin",
        screen="/admins",
        sections=(
            Section(
                "adding",
                "Adding someone",
                (
                    "Create the admin, choose the lowest role that lets them do their job, and "
                    "send them the invite link. They set their own password and must set up an "
                    "authenticator app before they can reach anything.",
                    "Give a new person **moderator** first. Roles are easy to raise later and "
                    "awkward to explain after a mistake.",
                ),
            ),
            Section(
                "removing",
                "Removing someone",
                (
                    "Revoking access is immediate — their current session stops working. Their "
                    "past actions stay in the audit log for ever, with their name; that is the "
                    "point of the log.",
                    "You cannot revoke or demote yourself, and the last remaining super admin "
                    "cannot be removed by anyone. That is a deliberate guard against locking "
                    "everybody out.",
                ),
                warn="When someone leaves, revoke them the same day.",
            ),
        ),
    ),
    Topic(
        slug="audit",
        title="The audit log",
        summary="Every action anyone took here — how to search it and how to read it.",
        screen="/audit",
        sections=(
            Section(
                "what",
                "What is in it",
                (
                    "Every action taken in this console, every sign-in and every failed sign-in, "
                    "with who, what, when and from which address. It can never be edited or "
                    "deleted — not by you, not by a super admin.",
                    "Filter by person, by period, or type a word to find an action, a target or a "
                    "detail. Times are UTC, which is 5 hours 30 minutes behind Indian time.",
                ),
            ),
            Section(
                "using",
                "What it is for",
                (
                    "**Undoing.** When a picture was removed by mistake, its address is in the "
                    "log. When a name was changed, the old one is in the log.",
                    "**Answering “who did this?”** without anybody having to remember.",
                    "**Noticing trouble.** A run of failed sign-ins from an address you don't "
                    "recognise is worth telling the owner about.",
                ),
            ),
        ),
    ),
    Topic(
        slug="system",
        title="Service health",
        summary="What is switched on, and what is costing money today.",
        role="editor",
        screen="/system",
        sections=(
            Section(
                "budget",
                "The daily AI budget",
                (
                    "Two Kitabi features cost real money each time they are used: book "
                    "recommendations, and reading a book's details out of a photograph of its "
                    "cover. Every use is counted, and there is a hard daily limit for the whole "
                    "service.",
                    "The bar shows how much of today's limit is gone. It resets at midnight UTC.",
                    "If the limit is reached, those two features politely refuse for the rest of "
                    "the day and everything else keeps working. That is the limit doing its job, "
                    "not a fault. If it happens several days running, tell the owner — the limit "
                    "may need raising.",
                ),
            ),
            Section(
                "heavy",
                "Heaviest users",
                (
                    "If one account is using far more than everyone else, open it. A person "
                    "reads; a script doesn't. This is the shape of somebody running up a bill on "
                    "purpose.",
                ),
            ),
            Section(
                "switches",
                "Switched on / off",
                (
                    "**Off** means a feature was never switched on, not that it has broken. "
                    "Email, image uploads and the AI features each need a setting that only a "
                    "developer can add. Kitabi is built to work quietly without them rather than "
                    "to fail.",
                ),
            ),
        ),
    ),
    Topic(
        slug="account",
        title="Your own account",
        summary="Signing in, the authenticator code, and what to do if you're locked out.",
        sections=(
            Section(
                "signing-in",
                "Signing in",
                (
                    "Email and password, then a six-digit code from your authenticator app. The "
                    "code is required — there is no way to switch it off, because this console "
                    "can see every reader's account.",
                    "Five wrong passwords locks the account for fifteen minutes. Wait it out; "
                    "trying harder makes it worse.",
                    "You are signed out after twelve hours. That is normal.",
                ),
            ),
            Section(
                "recovery",
                "Recovery codes",
                (
                    "When you set up the authenticator you were given eight recovery codes. Each "
                    "works once, in place of the six-digit code. **Keep them somewhere that is "
                    "not your phone** — the whole point is that they survive losing it.",
                    "If you have lost both your phone and the codes, a super admin has to reset "
                    "you. There is no self-service path, deliberately.",
                ),
            ),
            Section(
                "hygiene",
                "Basic care",
                (
                    "Never share your sign-in. If two people need access, they get two accounts — "
                    "otherwise the audit log stops meaning anything.",
                    "Change your password from [Change password](/account/password) if you ever "
                    "think it has been seen.",
                    "You can install this console on your phone or desktop like an app: use your "
                    "browser's “Install” or “Add to Home Screen”. It still needs a connection — "
                    "it does not work offline.",
                ),
            ),
        ),
    ),
    Topic(
        slug="problems",
        title="When something looks wrong",
        summary="What to check first, what to write down, and when to escalate.",
        sections=(
            Section(
                "first",
                "Check these first",
                (),
                steps=(
                    "Reload the page. Then try a private/incognito window.",
                    "Is it just you, or is the public site down too? Open kitabi.in in another "
                    "tab — if the public site is fine, the problem is smaller than it feels.",
                    "Check [Service health](/system). An “off” switch or a reached limit explains "
                    "a lot of “broken” behaviour.",
                    "Check the [audit log](/audit) — did somebody change something a minute ago?",
                ),
            ),
            Section(
                "escalate",
                "Telling a developer",
                (
                    "Send four things, and it will usually be fixed the same day: **the exact web "
                    "address** you were on, **what you clicked**, **what you expected**, and "
                    "**what happened instead** — with a screenshot including the whole screen and "
                    "the time.",
                    "“It's broken” costs a day of guessing. “Pressing Reviewed on "
                    "/moderation/incoming at 14:20 showed a red error” is fixed in an hour.",
                ),
            ),
            Section(
                "never",
                "Things not to do",
                (
                    "Don't repeat a failed action many times — especially a merge or a delete. If "
                    "it half-worked, repeating it makes the mess bigger.",
                    "Don't share screenshots of reader emails outside the team.",
                    "Don't work around a reader's privacy setting because someone asked you to. "
                    "If it deserves an exception, it deserves the owner's decision.",
                ),
            ),
        ),
    ),
    Topic(
        slug="glossary",
        title="Glossary",
        summary="The words this console uses, and what each one actually means.",
        sections=(
            Section(
                "terms",
                "Words you will meet",
                (
                    "**Work** — a book as an idea. Ratings and reviews attach here.",
                    "**Edition** — one printing of a work. Cover, ISBN and page count attach here. "
                    "A reader owns an edition.",
                    "**Catalogue** — the shared list of books, authors, publishers and series that "
                    "everyone sees.",
                    "**Library** — one reader's private shelf. You cannot see inside it.",
                    "**Entry** — one book on one reader's shelf.",
                    "**Sitting / session** — one stretch of reading, timed in the app.",
                    "**Claim** — a reader saying “this author is me”.",
                    "**Revision** — a suggested edit waiting for a decision.",
                    "**Merge** — folding two duplicate records into one.",
                    "**Soft delete** — hidden everywhere, but kept in the database and "
                    "recoverable. Almost every “delete” here is one of these.",
                    "**Suspend** — lock a reader out, keep all their data.",
                    "**UTC** — the clock all times here are shown in. Indian time is 5 hours "
                    "30 minutes ahead.",
                    "**Sync** — a reader's phone sending its changes to Kitabi. The app works "
                    "offline and catches up later, so a change can be minutes old before it "
                    "reaches here.",
                ),
            ),
        ),
    ),
)

BY_SLUG = {t.slug: t for t in TOPICS}


def visible(role: str) -> list[Topic]:
    """The topics an admin of `role` can act on. A handbook page describing a
    screen its reader cannot open is worse than no page — it teaches them to
    expect a menu item that will never be there."""
    rank = RANK.get(role, 0)
    return [t for t in TOPICS if RANK[t.role] <= rank]


def search(query: str, role: str, limit: int = 4) -> list[Topic]:
    """Handbook hits for the console's global search box."""
    q = query.strip().lower()
    if len(q) < 2:
        return []
    hits = []
    for topic in visible(role):
        haystack = topic.search_text()
        if q in topic.title.lower():
            hits.append((0, topic))
        elif q in topic.summary.lower():
            hits.append((1, topic))
        elif q in haystack:
            hits.append((2, topic))
    hits.sort(key=lambda pair: pair[0])
    return [t for _, t in hits[:limit]]
