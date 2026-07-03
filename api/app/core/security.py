"""Supabase JWT verification.

PyJWT against the project JWKS (asymmetric ES256 keys — Supabase default since
Oct 2025). PyJWKClient caches keys and handles `kid` rotation. python-jose is
banned (unmaintained).
"""

from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.core.config import get_settings

_bearer = HTTPBearer(auto_error=False)
_jwks_client: PyJWKClient | None = None


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(get_settings().jwks_url, cache_keys=True, lifespan=3600)
    return _jwks_client


def _unauthorized(message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"code": "unauthorized", "message": message},
        headers={"WWW-Authenticate": "Bearer"},
    )


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> dict:
    if credentials is None:
        raise _unauthorized("Missing bearer token")
    settings = get_settings()
    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(credentials.credentials)
        claims = jwt.decode(
            credentials.credentials,
            signing_key.key,
            algorithms=["ES256", "RS256"],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise _unauthorized("Invalid or expired token") from exc
    user_meta = claims.get("user_metadata") or {}
    # Google puts avatar in 'avatar_url'; Apple has no picture.
    avatar_url = user_meta.get("avatar_url") or user_meta.get("picture")
    return {
        "id": claims["sub"],
        "email": claims.get("email"),
        "avatar_url": avatar_url,
        "full_name": user_meta.get("full_name") or user_meta.get("name"),
    }
