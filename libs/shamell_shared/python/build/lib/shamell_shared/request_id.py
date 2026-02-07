import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from contextvars import ContextVar

_rid_ctx: ContextVar[str] = ContextVar("request_id", default="")


def get_request_id() -> str:
    rid = _rid_ctx.get()
    if not rid:
        rid = uuid.uuid4().hex
        _rid_ctx.set(rid)
    return rid


class RequestIDMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, header_name: str = "X-Request-ID"):
        super().__init__(app)
        self.header_name = header_name

    async def dispatch(self, request: Request, call_next):
        rid = request.headers.get(self.header_name) or uuid.uuid4().hex
        _rid_ctx.set(rid)
        response: Response = await call_next(request)
        response.headers.setdefault(self.header_name, rid)
        return response

