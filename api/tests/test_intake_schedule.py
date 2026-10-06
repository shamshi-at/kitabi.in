"""When the nightly intake runs (owner decision, 6 Oct 2026: 02:30 IST).

The scheduler works in UTC and India has no DST, so 02:30 IST is 21:00 UTC. The
time is a setting rather than a literal in `scheduler.start()` so that the admin
console's "Nightly intake" screen can read the same two numbers and judge the
right night (`admin/tests/test_intake.py` pins that half).
"""

from app.core.config import get_settings
from app.jobs import scheduler as scheduler_module


def test_the_default_run_is_half_past_two_in_the_morning_in_india():
    settings = get_settings()
    assert (
        settings.catalog_intake_run_hour_utc,
        settings.catalog_intake_run_minute_utc,
    ) == (21, 0)
    # 21:00 UTC + 5:30 = 02:30 the next morning.
    total = settings.catalog_intake_run_hour_utc * 60 + settings.catalog_intake_run_minute_utc + 330
    assert divmod(total % (24 * 60), 60) == (2, 30)


def test_the_cron_is_registered_from_those_settings(monkeypatch):
    registered: dict[str, dict] = {}

    def add_job(func, trigger, **kwargs):  # noqa: ANN001, ANN202
        registered[kwargs["id"]] = {"trigger": trigger, **kwargs}

    monkeypatch.setattr(scheduler_module.scheduler, "add_job", add_job)
    monkeypatch.setattr(scheduler_module.scheduler, "start", lambda: None)

    scheduler_module.start()

    job = registered["catalog_intake"]
    assert job["trigger"] == "cron"
    assert (job["hour"], job["minute"]) == (21, 0)
    assert job["misfire_grace_time"] == 3600 and job["coalesce"] and job["max_instances"] == 1
