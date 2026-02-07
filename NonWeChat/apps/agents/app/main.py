import os
from fastapi import FastAPI
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging

app = FastAPI(title="Agents API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)
