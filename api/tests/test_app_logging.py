"""The jobs' own log lines have to be visible.

uvicorn configures its own loggers and nobody else's, so every `logger.info`
under `app.*` was dropped. The first unattended night of the catalogue intake
(4 Oct 2026) published 150 books and the log said nothing at all about it.
"""

import logging

from app.main import _show_app_logs


def test_the_applications_info_lines_reach_the_log():
    _show_app_logs()
    assert logging.getLogger("app.jobs.catalog_intake").isEnabledFor(logging.INFO)
    assert logging.getLogger("app.services.author_roles").isEnabledFor(logging.INFO)


def test_setting_it_up_twice_does_not_print_every_line_twice():
    _show_app_logs()
    _show_app_logs()
    assert len(logging.getLogger("app").handlers) == 1
