from collections.abc import Callable
from fastapi import FastAPI


def register_startup(app: FastAPI) -> Callable[[Callable], Callable]:
    """
    Register a startup hook without using FastAPI's deprecated @on_event API.
    Usage:
        @register_startup(app)
        async def _startup(): ...
    """
    def decorator(func: Callable) -> Callable:
        app.router.on_startup.append(func)
        return func
    return decorator


def register_shutdown(app: FastAPI) -> Callable[[Callable], Callable]:
    """
    Register a shutdown hook without using FastAPI's deprecated @on_event API.
    """
    def decorator(func: Callable) -> Callable:
        app.router.on_shutdown.append(func)
        return func
    return decorator
