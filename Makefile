.PHONY: help init setup install dev test lint format clean notebook docker-up docker-down

# Detect OS and set path separator
ifeq ($(OS),Windows_NT)
    VENV_PYTHON = .venv/Scripts/python.exe
    VENV_PIP = .venv/Scripts/pip.exe
    RM = del /Q
    RMDIR = rmdir /S /Q
    NULL_OUT = 2>nul
    ACTIVATE_CMD = .venv\Scripts\activate
else
    VENV_PYTHON = .venv/bin/python
    VENV_PIP = .venv/bin/pip
    RM = rm -f
    RMDIR = rm -rf
    NULL_OUT = 2>/dev/null
    ACTIVATE_CMD = source .venv/bin/activate
endif

help:
	@echo "Available commands:"
	@echo "  make init      - Initialize project (first time)"
	@echo "  make setup     - Setup virtual environment"
	@echo "  make install   - Install dependencies"
	@echo "  make dev       - Start development environment"
	@echo "  make test      - Run tests"
	@echo "  make lint      - Run linters"
	@echo "  make format    - Format code"
	@echo "  make clean     - Clean project"
	@echo "  make notebook  - Start Jupyter Lab"
	@echo "  make docker-up - Start Docker services"
	@echo "  make docker-down - Stop Docker services"

init: setup install

setup:
	@echo "Creating virtual environment..."
	python -m venv .venv
	@echo "✅ Virtual environment created"
	@echo "Activate with: $(ACTIVATE_CMD)"

install:
	@echo "Installing dependencies..."
	$(VENV_PYTHON) -m pip install --upgrade pip
	$(VENV_PYTHON) -m pip install -e .[dev]
	@echo "✅ Dependencies installed"

dev: docker-up notebook

notebook:
	@echo "Starting Jupyter Lab..."
	$(VENV_PYTHON) -m jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password=''

docker-up:
	@echo "Starting Docker services..."
	@if [ -f docker-compose.yml ]; then \
		docker-compose up -d; \
		echo "✅ Services started"; \
		echo "Services available at:"; \
		echo "  - Jupyter: http://localhost:8888"; \
		echo "  - MLflow: http://localhost:5000"; \
	else \
		echo "docker-compose.yml not found"; \
	fi

docker-down:
	@echo "Stopping Docker services..."
	@if [ -f docker-compose.yml ]; then \
		docker-compose down; \
		echo "✅ Services stopped"; \
	else \
		echo "docker-compose.yml not found"; \
	fi

test:
	$(VENV_PYTHON) -m pytest tests/ -v

lint:
	$(VENV_PYTHON) -m black --check src/ tests/ || echo "Black found issues"
	$(VENV_PYTHON) -m flake8 src/ tests/ || echo "Flake8 found issues"

format:
	$(VENV_PYTHON) -m black src/ tests/
	$(VENV_PYTHON) -m isort src/ tests/

clean:
	@echo "Cleaning project..."
ifeq ($(OS),Windows_NT)
	@if exist __pycache__ $(RMDIR) __pycache__ $(NULL_OUT)
	@$(RM) *.pyc $(NULL_OUT)
	@$(RM) .coverage $(NULL_OUT)
	@if exist .pytest_cache $(RMDIR) .pytest_cache $(NULL_OUT)
	@if exist htmlcov $(RMDIR) htmlcov $(NULL_OUT)
	@if exist .mypy_cache $(RMDIR) .mypy_cache $(NULL_OUT)
else
	@find . -type d -name "__pycache__" -exec $(RMDIR) {} + $(NULL_OUT)
	@find . -type f -name "*.pyc" -delete $(NULL_OUT)
	@$(RM) .coverage $(NULL_OUT)
	@$(RM) -r .pytest_cache $(NULL_OUT)
	@$(RM) -r htmlcov $(NULL_OUT)
	@$(RM) -r .mypy_cache $(NULL_OUT)
endif
	@echo "✅ Project cleaned"

# Windows-specific helper (if needed)
windows-activate:
	@echo "To activate virtual environment on Windows:"
	@echo "  .venv\Scripts\activate"

# Unix-specific helper (if needed)
unix-activate:
	@echo "To activate virtual environment on Unix:"
	@echo "  source .venv/bin/activate"
	