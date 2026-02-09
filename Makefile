PYTHON ?= python3.11
VENV ?= .venv311
PIP := $(VENV)/bin/pip
PY := $(VENV)/bin/python

ITERATIONS ?= 100

.PHONY: help venv test compile iterate

help:
	@echo "Targets:"
	@echo "  venv      Create/refresh venv at $(VENV) and install deps"
	@echo "  test      Run pytest (ENV=test, MONOLITH_MODE=1)"
	@echo "  compile   Byte-compile all Python sources"
	@echo "  iterate   Run scripts/iterate_100.sh (ITERATIONS=$(ITERATIONS))"

venv:
	@test -x "$(PY)" || "$(PYTHON)" -m venv "$(VENV)"
	"$(PY)" -m pip install --upgrade pip
	"$(PIP)" install -r apps/monolith/requirements.txt
	"$(PIP)" install -e libs/shamell_shared/python
	"$(PIP)" install pytest

test: venv
	ENV=test MONOLITH_MODE=1 PYTHONPATH=. "$(PY)" -m pytest -q

compile: venv
	"$(PY)" -m compileall -q apps src libs NonWeChat

iterate: venv
	PYTHON_BIN="$(PY)" bash scripts/iterate_100.sh "$(ITERATIONS)"

