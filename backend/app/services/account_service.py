"""Deleting a person's cloud account.

The phone cannot delete a Supabase auth user (that needs the service role, which lives only on the server), so it asks
this backend. Two steps, both against Supabase Auth:

1. the person's own access token is checked (`GET /auth/v1/user`), which also tells us who they are: the id is never
   taken from the request, so nobody can delete someone else's account by naming them;
2. that user is deleted with the service role (`DELETE /auth/v1/admin/users/{id}`). The tables `profiles` and
   `training_plans` reference `auth.users` with `on delete cascade`, so the person's rows go with it.

Nothing is stored or logged here: no token, no id, no e-mail.
"""

import uuid

import httpx

from app.errors import ApiError
from app.logging_setup import get_logger

log = get_logger("account")

_TIMEOUT = 8.0


def _unavailable() -> ApiError:
    return ApiError(502, "account_unavailable", "Nie udało się usunąć konta. Spróbuj ponownie za chwilę.")


async def delete_account(
    *, supabase_url: str, service_key: str, user_token: str, transport: httpx.AsyncBaseTransport | None = None
) -> None:
    """Deletes the account that `user_token` belongs to. Raises ApiError: 401 for a token Supabase does not accept,
    502 when Supabase cannot be reached or refuses."""
    base = supabase_url.rstrip("/")
    async with httpx.AsyncClient(timeout=_TIMEOUT, transport=transport) as client:
        try:
            who = await client.get(
                f"{base}/auth/v1/user", headers={"apikey": service_key, "Authorization": f"Bearer {user_token}"}
            )
        except httpx.HTTPError as exc:
            log.warning("account_lookup_failed", extra={"error": type(exc).__name__})
            raise _unavailable() from exc
        if who.status_code in (401, 403):
            raise ApiError(
                401, "invalid_account_token", "Sesja konta wygasła. Zaloguj się ponownie i spróbuj jeszcze raz."
            )
        if who.status_code != 200:
            log.warning("account_lookup_status", extra={"status": who.status_code})
            raise _unavailable()
        try:
            user_id = str(uuid.UUID(str(who.json()["id"])))
        except (KeyError, ValueError, TypeError) as exc:
            log.warning("account_lookup_body")
            raise _unavailable() from exc

        try:
            gone = await client.delete(
                f"{base}/auth/v1/admin/users/{user_id}",
                headers={"apikey": service_key, "Authorization": f"Bearer {service_key}"},
            )
        except httpx.HTTPError as exc:
            log.warning("account_delete_failed", extra={"error": type(exc).__name__})
            raise _unavailable() from exc
        # 404: already gone (a retry after a lost answer), which is the state the person asked for.
        if gone.status_code not in (200, 204, 404):
            log.warning("account_delete_status", extra={"status": gone.status_code})
            raise _unavailable()
