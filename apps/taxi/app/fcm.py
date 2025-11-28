from typing import Optional, Dict
import os

import httpx

# Google auth libraries are optional. Import them lazily so that the Taxi
# service can run (and the monolith can use Taxi internally) even when they
# are not installed; in that case FCM simply becomes a no-op.
try:
    from google.oauth2 import service_account  # type: ignore[import]
    from google.auth.transport.requests import Request  # type: ignore[import]
    _HAS_GOOGLE_AUTH = True
except Exception:  # pragma: no cover - best-effort optional dependency
    service_account = None  # type: ignore[assignment]
    Request = None  # type: ignore[assignment]
    _HAS_GOOGLE_AUTH = False

# Project ID from Firebase
PROJECT_ID = os.getenv("FCM_PROJECT_ID", "shamell")

# Path to the service account JSON (configurable via ENV)
SERVICE_ACCOUNT_FILE = os.getenv("FCM_SERVICE_ACCOUNT_FILE", "")

# The v1 API requires this scope
SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]


def _get_access_token() -> Optional[str]:
    """
    Creates an OAuth access token for the Firebase Cloud Messaging API.
    Returns None when a token cannot be created.
    """
    # If the google-auth stack or credentials are missing, silently disable FCM.
    if not _HAS_GOOGLE_AUTH or not SERVICE_ACCOUNT_FILE:
        return None
    try:
        credentials = service_account.Credentials.from_service_account_file(  # type: ignore[union-attr]
            SERVICE_ACCOUNT_FILE, scopes=SCOPES
        )
        credentials.refresh(Request())  # type: ignore[operator]
        return credentials.token
    except Exception:
        # FCM is strictly best-effort; never break the main app.
        return None


def send_fcm_v1(
    device_token: str,
    title: str,
    body: str,
    data: Optional[Dict[str, str]] = None,
) -> Optional[Dict]:
    """
    Sends a notification via the FCM HTTP v1 API.
    Best-effort: fails silently and returns None when something goes wrong.
    """
    if not device_token:
        return None
    access_token = _get_access_token()
    if not access_token:
        return None
    url = f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send"
    message_payload = {
        "message": {
            "token": device_token,
            "notification": {
                "title": title,
                "body": body,
            },
            "data": data or {},
        }
    }
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=UTF-8",
    }
    try:
        r = httpx.post(url, headers=headers, json=message_payload, timeout=5)
        r.raise_for_status()
        try:
            return r.json()
        except Exception:
            return {"status_code": r.status_code}
    except Exception:
        return None
