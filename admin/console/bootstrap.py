"""Make the API's `app` package importable from the admin app.

The admin console reuses the API's SQLAlchemy models, DB engine and settings
rather than duplicating them — the same `sys.path` trick the ETL scripts use
(etl/03_transform.py). Import this module first, before any `from app...`.
"""

import sys
from pathlib import Path

_API = Path(__file__).resolve().parents[2] / "api"
if str(_API) not in sys.path:
    sys.path.insert(0, str(_API))
