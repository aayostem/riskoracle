
# .PHONY: help init deploy test clean validate

# help: ## Display this help
# 	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# init: ## Initialize the entire platform
# 	@echo "🚀 Initializing Enterprise ML Platform..."
# 	$(MAKE) init-dev
# 	$(MAKE) init-infra
# 	$(MAKE) init-k8s
# 	$(MAKE) init-ml-platform

# init-dev: ## Initialize development environment
# 	@echo "💻 Setting up development environment..."
# 	python -m pip install --upgrade pip
# 	pip install pre-commit
# 	pre-commit install
# 	docker-compose up -d
# 	@echo "✅ Development environment ready!"

# init-infra: ## Initialize infrastructure (Terraform)
# 	@echo "🏗️  Setting up infrastructure..."
# 	cd infrastructure/terraform/environments/dev && \
# 		terraform init -backend-config=backend.tfvars
# 	@echo "✅ Infrastructure initialized!"

# init-k8s: ## Initialize Kubernetes
# 	@echo "⚙️  Setting up Kubernetes..."
# 	kubectl apply -f kubernetes/base/namespaces/
# 	@echo "✅ Kubernetes initialized!"

# init-ml-platform: ## Initialize ML platform
# 	@echo "🤖 Setting up ML platform..."
# 	$(MAKE) deploy-ml-components
# 	@echo "✅ ML platform initialized!"

# deploy: ## Deploy all services
# 	@echo "🚢 Deploying services..."
# 	$(MAKE) deploy-data-platform
# 	$(MAKE) deploy-ml-platform
# 	$(MAKE) deploy-applications
# 	@echo "✅ All services deployed!"

# deploy-data-platform:
# 	@echo "📦 Deploying data platform..."
# 	kubectl apply -k kubernetes/overlays/dev/data-platform/

# deploy-ml-platform:
# 	@echo "🧠 Deploying ML platform..."
# 	kubectl apply -k kubernetes/overlays/dev/ml-platform/

# deploy-applications:
# 	@echo "🖥️  Deploying applications..."
# 	kubectl apply -k kubernetes/overlays/dev/applications/

# deploy-ml-components:
# 	@echo "⚙️  Deploying ML components..."
# 	helm repo add mlflow https://helm.mlflow.org
# 	helm repo add feast https://feast-helm-charts.storage.googleapis.com
# 	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# 	helm repo update
# 	@echo "✅ ML components deployed!"

# test: ## Run all tests
# 	@echo "🧪 Running tests..."
# 	$(MAKE) test-unit
# 	$(MAKE) test-integration
# 	$(MAKE) test-e2e
# 	@echo "✅ All tests passed!"

# test-unit:
# 	@pytest tests/unit/ -v --cov=src --cov-report=html

# test-integration:
# 	@pytest tests/integration/ -v

# test-e2e:
# 	@pytest tests/e2e/ -v

# clean: ## Clean up all resources
# 	@echo "🧹 Cleaning up..."
# 	docker-compose down -v
# 	kubectl delete ns ml-platform monitoring security --wait=true --timeout=300s
# 	@echo "✅ Cleanup completed!"

# validate: ## Validate configurations
# 	@echo "🔍 Validating configurations..."
# 	terraform validate infrastructure/terraform/environments/dev/
# 	kubectl apply --dry-run=client -k kubernetes/overlays/dev/
# 	@echo "✅ Validation completed!"

# lint: ## Run linting
# 	@echo "✨ Running linters..."
# 	pre-commit run --all-files
# 	@echo "✅ Linting completed!"

# format: ## Format code
# 	@echo "🎨 Formatting code..."
# 	black src/python/
# 	isort src/python/
# 	terraform fmt -recursive infrastructure/
# 	@echo "✅ Formatting completed!"

# security-scan: ## Run security scans
# 	@echo "🔒 Running security scans..."
# 	trivy fs .
# 	checkov -d infrastructure/
# 	tfsec infrastructure/
# 	@echo "✅ Security scans completed!"


.PHONY: help init setup-dev conda-env install-dev install-prod test lint format security-check clean docs notebook docker-build docker-run

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "${BLUE}%-30s${NC} %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize the entire project (first time setup)
	@echo "${GREEN}🚀 Initializing ML Platform Project...${NC}"
	$(MAKE) check-prerequisites
	$(MAKE) conda-env
	$(MAKE) install-dev
	$(MAKE) setup-git
	$(MAKE) setup-pre-commit
	@echo "${GREEN}✅ Project initialization complete!${NC}"
	@echo ""
	@echo "${YELLOW}Next steps:${NC}"
	@echo "  1. Activate conda environment: ${BLUE}conda activate ml-platform-dev${NC}"
	@echo "  2. Start Jupyter Lab: ${BLUE}make notebook${NC}"
	@echo "  3. Start local services: ${BLUE}make docker-run${NC}"

check-prerequisites: ## Check if required tools are installed
	@echo "${GREEN}Checking prerequisites...${NC}"
	@command -v conda >/dev/null 2>&1 || { echo >&2 "${RED}Conda is required but not installed.${NC}"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo >&2 "${RED}Docker is required but not installed.${NC}"; exit 1; }
	@command -v docker-compose >/dev/null 2>&1 || { echo >&2 "${RED}Docker Compose is required but not installed.${NC}"; exit 1; }
	@command -v make >/dev/null 2>&1 || { echo >&2 "${RED}Make is required but not installed.${NC}"; exit 1; }
	@echo "${GREEN}✅ All prerequisites satisfied${NC}"

conda-env: ## Create or update conda environment
	@echo "${GREEN}Setting up Conda environment...${NC}"
	@if conda env list | grep -q "ml-platform-dev"; then \
		echo "${YELLOW}Updating existing conda environment...${NC}"; \
		conda env update -f environment.yml --prune; \
	else \
		echo "${YELLOW}Creating new conda environment...${NC}"; \
		conda env create -f environment.yml; \
	fi
	@echo "${GREEN}✅ Conda environment ready!${NC}"
	@echo "${YELLOW}Activate with: ${BLUE}conda activate ml-platform-dev${NC}"

conda-clean: ## Clean conda environment (remove and recreate)
	@echo "${YELLOW}Removing conda environment...${NC}"
	conda env remove -n ml-platform-dev -y
	$(MAKE) conda-env

install-dev: ## Install development dependencies
	@echo "${GREEN}Installing development dependencies...${NC}"
	conda run -n ml-platform-dev pip install -r requirements-dev.txt
	conda run -n ml-platform-dev pip install -e .
	@echo "${GREEN}✅ Development dependencies installed${NC}"

install-prod: ## Install production dependencies only
	@echo "${GREEN}Installing production dependencies...${NC}"
	conda run -n ml-platform-dev pip install -r requirements.txt
	@echo "${GREEN}✅ Production dependencies installed${NC}"

setup-git: ## Setup git configuration for the project
	@echo "${GREEN}Setting up git...${NC}"
	git config core.hooksPath .githooks
	git config commit.template .gitmessage
	@echo "${GREEN}✅ Git configured${NC}"

setup-pre-commit: ## Install and setup pre-commit hooks
	@echo "${GREEN}Setting up pre-commit hooks...${NC}"
	conda run -n ml-platform-dev pre-commit install
	conda run -n ml-platform-dev pre-commit install --hook-type commit-msg
	@echo "${GREEN}✅ Pre-commit hooks installed${NC}"

test: ## Run all tests
	@echo "${GREEN}Running tests...${NC}"
	conda run -n ml-platform-dev pytest tests/ -v --cov=src --cov-report=html --cov-report=xml

test-unit: ## Run unit tests only
	conda run -n ml-platform-dev pytest tests/unit/ -v

test-integration: ## Run integration tests only
	conda run -n ml-platform-dev pytest tests/integration/ -v

test-e2e: ## Run end-to-end tests only
	conda run -n ml-platform-dev pytest tests/e2e/ -v

test-performance: ## Run performance tests
	conda run -n ml-platform-dev pytest tests/performance/ -v --benchmark-only

lint: ## Run all linters
	@echo "${GREEN}Running linters...${NC}"
	conda run -n ml-platform-dev black --check src/ tests/
	conda run -n ml-platform-dev flake8 src/ tests/
	conda run -n ml-platform-dev mypy src/
	conda run -n ml-platform-dev isort --check-only src/ tests/

format: ## Format code automatically
	@echo "${GREEN}Formatting code...${NC}"
	conda run -n ml-platform-dev black src/ tests/
	conda run -n ml-platform-dev isort src/ tests/
	conda run -n ml-platform-dev autoflake --in-place --remove-all-unused-imports --recursive src/ tests/

security-check: ## Run security checks
	@echo "${GREEN}Running security checks...${NC}"
	conda run -n ml-platform-dev bandit -r src/ -f json -o bandit-report.json
	conda run -n ml-platform-dev safety check --json --output safety-report.json
	@echo "${GREEN}✅ Security checks completed${NC}"

docker-build: ## Build all Docker images
	@echo "${GREEN}Building Docker images...${NC}"
	docker-compose build --parallel

docker-run: ## Start all Docker services
	@echo "${GREEN}Starting Docker services...${NC}"
	docker-compose up -d
	@echo "${GREEN}✅ Services started${NC}"
	@echo "${YELLOW}Services available at:${NC}"
	@echo "  - MLflow: http://localhost:5000"
	@echo "  - Jupyter: http://localhost:8888"
	@echo "  - MinIO: http://localhost:9001"
	@echo "  - Redis: localhost:6379"
	@echo "  - PostgreSQL: localhost:5432"

docker-stop: ## Stop all Docker services
	@echo "${YELLOW}Stopping Docker services...${NC}"
	docker-compose down

docker-clean: ## Remove all Docker containers and volumes
	@echo "${YELLOW}Cleaning Docker environment...${NC}"
	docker-compose down -v
	docker system prune -f

notebook: ## Start Jupyter Lab notebook server
	@echo "${GREEN}Starting Jupyter Lab...${NC}"
	conda run -n ml-platform-dev jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password=''

notebook-kernel: ## Install Jupyter kernel for conda environment
	@echo "${GREEN}Installing Jupyter kernel...${NC}"
	conda run -n ml-platform-dev python -m ipykernel install --user --name=ml-platform-dev --display-name="ML Platform Dev"

docs: ## Build documentation
	@echo "${GREEN}Building documentation...${NC}"
	conda run -n ml-platform-dev mkdocs build

docs-serve: ## Serve documentation locally
	@echo "${GREEN}Serving documentation...${NC}"
	conda run -n ml-platform-dev mkdocs serve

clean: ## Clean all generated files and caches
	@echo "${YELLOW}Cleaning project...${NC}"
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name ".coverage" -delete
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".hypothesis" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ipynb_checkpoints" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "htmlcov" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "coverage.xml" -delete
	find . -type f -name "bandit-report.json" -delete
	find . -type f -name "safety-report.json" -delete
	rm -rf .tox dist build .coverage .benchmarks
	@echo "${GREEN}✅ Project cleaned${NC}"

reset: ## Reset project to clean state (docker + conda)
	@echo "${YELLOW}Resetting project...${NC}"
	$(MAKE) docker-clean
	$(MAKE) conda-clean
	$(MAKE) clean
	@echo "${GREEN}✅ Project reset complete${NC}"

dev: ## Start complete development environment
	@echo "${GREEN}Starting development environment...${NC}"
	$(MAKE) docker-run
	$(MAKE) notebook
	@echo "${GREEN}✅ Development environment ready!${NC}"

sync-env: ## Sync conda environment with updated dependencies
	@echo "${GREEN}Syncing conda environment...${NC}"
	conda env export -n ml-platform-dev --no-builds | grep -v "^prefix:" > environment.yml
	conda run -n ml-platform-dev pip freeze | grep -v "ml-platform" > requirements.txt
	@echo "${GREEN}✅ Environment synced${NC}"

env-info: ## Display conda environment information
	@echo "${BLUE}Conda Environment Information:${NC}"
	@echo "Name: ml-platform-dev"
	@conda info --envs | grep ml-platform-dev || true
	@echo ""
	@echo "${BLUE}Python version:${NC}"
	@conda run -n ml-platform-dev python --version
	@echo ""
	@echo "${BLUE}Installed packages:${NC}"
	@conda list -n ml-platform-dev --export

check-updates: ## Check for dependency updates
	@echo "${GREEN}Checking for dependency updates...${NC}"
	conda run -n ml-platform-dev pip list --outdated --format=columns
	@echo "${YELLOW}To update packages:${NC}"
	@echo "  pip install --upgrade PACKAGE_NAME"

shell: ## Activate conda shell (useful for manual commands)
	@echo "${GREEN}Activating conda shell...${NC}"
	@echo "${YELLOW}Run: conda activate ml-platform-dev${NC}"
	@echo "${YELLOW}Or use: conda run -n ml-platform-dev python ...${NC}"

setup-local-infra: ## Setup local infrastructure (LocalStack, etc.)
	@echo "${GREEN}Setting up local infrastructure...${NC}"
	docker-compose -f docker-compose.infrastructure.yml up -d
	@echo "${GREEN}✅ Local infrastructure started${NC}"
	@echo "${YELLOW}LocalStack: http://localhost:4566${NC}"
	@echo "${YELLOW}MinIO: http://localhost:9001${NC}"
	@echo "${YELLOW}Redis: localhost:6379${NC}"

health-check: ## Check health of all services
	@echo "${GREEN}Checking service health...${NC}"
	@echo "${BLUE}Docker services:${NC}"
	@docker-compose ps
	@echo ""
	@echo "${BLUE}Conda environment:${NC}"
	@conda info --envs | grep ml-platform-dev
	@echo ""
	@echo "${BLUE}Python packages:${NC}"
	@conda run -n ml-platform-dev pip list | grep -E "(mlflow|feast|fastapi|jupyter)"