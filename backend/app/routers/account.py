from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request, Response

from app.config import Settings
from app.deps import get_settings
from app.errors import ApiError
from app.schemas.api import ErrorEnvelope
from app.security import rate_limited
from app.services.account_service import delete_account

router = APIRouter(prefix="/account", tags=["account"])
guard = rate_limited("account", lambda s: s.rate_limit_account_per_minute)


@router.delete(
    "",
    status_code=204,
    operation_id="deleteAccount",
    summary="Delete the signed-in person's cloud account and its data",
    description=(
        "Needs the app token (`Authorization`) and the person's own access token in `X-Account-Token`. The person is "
        "identified by that token, never by the request body. Removes the Supabase user; the profile and the plan "
        "stored for it are deleted with it. Data on the phone is not touched. 503 `account_unavailable` when the "
        "server has no account service configured."
    ),
    responses={
        401: {"model": ErrorEnvelope, "description": "App token missing, or the account token is not accepted."},
        502: {"model": ErrorEnvelope, "description": "The account service could not be reached or refused."},
        503: {"model": ErrorEnvelope, "description": "Accounts are not configured on this server."},
    },
)
async def remove_account(
    request: Request,
    x_account_token: Annotated[str | None, Header()] = None,
    settings: Settings = Depends(get_settings),
    _=Depends(guard),
) -> Response:
    if not settings.supabase_configured:
        raise ApiError(503, "account_unavailable", "Usuwanie konta nie jest teraz dostępne.")
    token = (x_account_token or "").strip()
    if not token:
        raise ApiError(401, "invalid_account_token", "Brak sesji konta. Zaloguj się i spróbuj jeszcze raz.")
    assert settings.supabase_url and settings.supabase_service_key  # supabase_configured
    await delete_account(
        supabase_url=settings.supabase_url,
        service_key=settings.supabase_service_key.get_secret_value().strip(),
        user_token=token,
        transport=getattr(request.app.state, "account_transport", None),
    )
    return Response(status_code=204)
