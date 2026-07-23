"""Shared Jinja environment. `templates.TemplateResponse(request, name, ctx)`
uses the modern (request-first) signature."""

from pathlib import Path

from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))
