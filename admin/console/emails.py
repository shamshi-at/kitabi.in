"""Branded email content for the admin sign-in flows — the Reading Room theme in
the one format email clients actually honour: table layout, inline styles, a
hosted PNG logo (inline SVG and <style> blocks get stripped by Gmail et al.),
and a plain-text alternative alongside every HTML body for deliverability and
text-only clients.

Each builder returns (subject, text, html). The routers hand these to
mail.send(); mail.py sends the HTML with the text as the fallback part.
"""

from html import escape

# Reading Room palette (docs/screen-design.md).
_PAPER = "#F6F0E3"
_CARD = "#FFFCF4"
_INK = "#2B2118"
_INK_SOFT = "#7A6A55"
_LINE = "#E2D6BD"
_OXBLOOD = "#7E2A33"
_GOLD = "#B8862B"
_PANEL = "#241811"

_LOGO = "https://kitabi.in/kitabi-logo.png"
_SERIF = "Georgia, 'Times New Roman', serif"
_SANS = "-apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"


def _shell(heading: str, lead_html: str, feature_html: str, after_html: str = "") -> str:
    """The branded outer frame: paper backdrop, a card, the logo + wordmark, a
    heading, a lead paragraph, a feature block (the code or a button), and a
    quiet footer. All inline; centred; ~480px."""
    return f"""\
<!DOCTYPE html>
<html lang="en"><body style="margin:0;padding:0;background:{_PAPER};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{_PAPER};">
<tr><td align="center" style="padding:32px 16px;">
  <table role="presentation" width="480" cellpadding="0" cellspacing="0"
    style="width:480px;max-width:100%;background:{_CARD};border:1px solid {_LINE};border-radius:14px;overflow:hidden;">
    <tr><td align="center" style="background:{_PANEL};padding:26px 24px 22px;">
      <img src="{_LOGO}" width="52" height="52" alt="Kitabi"
        style="display:block;border-radius:12px;border:0;outline:none;">
      <div style="font-family:{_SERIF};font-size:20px;font-weight:normal;color:{_PAPER};padding-top:10px;letter-spacing:.5px;">Kitabi</div>
      <div style="font-family:{_SANS};font-size:10px;letter-spacing:2px;color:{_GOLD};padding-top:2px;">ADMIN</div>
    </td></tr>
    <tr><td style="padding:30px 34px 34px;">
      <h1 style="margin:0 0 12px;font-family:{_SERIF};font-size:22px;font-weight:normal;color:{_INK};">{heading}</h1>
      <p style="margin:0 0 22px;font-family:{_SANS};font-size:14px;line-height:1.6;color:{_INK_SOFT};">{lead_html}</p>
      {feature_html}
      {after_html}
    </td></tr>
    <tr><td style="padding:0 34px 30px;">
      <hr style="border:0;border-top:1px solid {_LINE};margin:0 0 14px;">
      <p style="margin:0;font-family:{_SANS};font-size:11.5px;line-height:1.6;color:{_INK_SOFT};">
        Kitabi Admin · Beyond the Bookshelf. If you didn't request this, you can safely ignore this email.</p>
    </td></tr>
  </table>
</td></tr></table>
</body></html>"""


def _button(label: str, url: str) -> str:
    """A bulletproof (table-cell) button — the only kind that renders across
    Outlook and the rest."""
    safe = escape(url, quote=True)
    return f"""\
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 8px;"><tr>
  <td align="center" bgcolor="{_OXBLOOD}" style="border-radius:9px;">
    <a href="{safe}" style="display:inline-block;padding:13px 26px;font-family:{_SANS};font-size:14px;
      font-weight:600;color:#ffffff;text-decoration:none;border-radius:9px;">{escape(label)}</a>
  </td>
</tr></table>
<p style="margin:8px 0 0;font-family:{_SANS};font-size:11.5px;line-height:1.6;color:{_INK_SOFT};word-break:break-all;">
  Or paste this link: <a href="{safe}" style="color:{_OXBLOOD};">{safe}</a></p>"""


def _code_box(code: str) -> str:
    return f"""\
<div style="font-family:'SF Mono',Menlo,Consolas,monospace;font-size:30px;font-weight:600;
  letter-spacing:8px;color:{_INK};background:{_PAPER};border:1px solid {_LINE};border-radius:10px;
  padding:16px;text-align:center;">{escape(code)}</div>"""


# ---- the three flows -----------------------------------------------------
def reset_email(otp: str, base_url: str) -> tuple[str, str, str]:
    subject = "Your Kitabi Admin sign-in code"
    text = (
        f"Your one-time sign-in code is {otp}\n\n"
        f"It expires in 30 minutes. Enter it in the password field at {base_url}/sign-in — "
        f"you'll be asked to set a new password right after.\n\n"
        f"If you didn't request this, ignore this email."
    )
    html = _shell(
        "Your sign-in code",
        "Enter this one-time code in the password field on the sign-in page. "
        "It expires in 30 minutes, and you'll set a new password right after.",
        _code_box(otp),
    )
    return subject, text, html


def magic_email(link: str) -> tuple[str, str, str]:
    subject = "Your Kitabi Admin sign-in link"
    text = (
        f"Sign in to Kitabi Admin:\n\n{link}\n\n"
        f"This link works once and expires in 15 minutes. You'll still confirm your "
        f"authenticator code after.\n\nIf you didn't request this, ignore this email."
    )
    html = _shell(
        "Sign in to Kitabi Admin",
        "Use the button below to sign in. It works once and expires in 15 minutes — "
        "you'll still confirm your authenticator code after.",
        _button("Sign in", link),
    )
    return subject, text, html


def invite_email(link: str, role: str) -> tuple[str, str, str]:
    role_label = role.replace("_", " ")
    subject = "You've been invited to Kitabi Admin"
    text = (
        f"You've been added as a {role_label} on Kitabi Admin.\n\n"
        f"Set up your account (valid 48 hours):\n\n{link}\n\n"
        f"You'll choose a password and set up an authenticator app."
    )
    html = _shell(
        "Welcome to Kitabi Admin",
        f"You've been added as a <b style=\"color:{_INK};\">{escape(role_label)}</b>. "
        f"Set up your account below — you'll choose a password and an authenticator app. "
        f"This invite is valid for 48 hours.",
        _button("Set up your account", link),
    )
    return subject, text, html
