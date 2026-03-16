.PHONY: install test lint format clean

install:
	pip install -r requirements.txt
	pip install -r requirements-dev.txt

test:
	pytest tests/ -v --tb=short

lint:
	ruff check src/ tests/
	mypy src/riskoracle/

format:
	black src/ tests/
	ruff check --fix src/ tests/

# Makefile-small — local dev
local-train:
	python ml/pipelines/train_local.py --sample-size 10000

local-serve:
	uvicorn src.riskoracle.api:app --reload --port 8000

# Makefile-Large — production
spark-train:
	spark-submit --master yarn ml/pipelines/train_distributed.py

