from datetime import UTC, datetime
from typing import Annotated, Any

from pydantic import AfterValidator, BaseModel, BeforeValidator, ConfigDict, PlainSerializer
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    """camelCase on the wire (like the Swift Codable types), snake_case in Python.

    Unknown fields are ignored on input so the app can add fields before the server learns about them.
    """

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="ignore")


def _require_text_or_datetime(value: Any) -> Any:
    # A number would be read as a Unix timestamp, but Swift's default Date encoding is seconds since 2001.
    # The app must send ISO 8601 text (JSONEncoder.dateEncodingStrategy = .iso8601).
    if isinstance(value, bool) or not isinstance(value, str | datetime):
        raise ValueError("Data musi być tekstem w formacie ISO 8601.")
    return value


def _to_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _format(value: datetime) -> str:
    # No fractional seconds: Swift's `.iso8601` decoding strategy does not parse them.
    return _to_utc(value).strftime("%Y-%m-%dT%H:%M:%SZ")


UtcDateTime = Annotated[
    datetime,
    BeforeValidator(_require_text_or_datetime),
    AfterValidator(_to_utc),
    PlainSerializer(_format, return_type=str, when_used="json"),
]
