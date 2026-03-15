<div align="center">

<br />

```
██████╗ ██╗███████╗██╗  ██╗ ██████╗ ██████╗  █████╗  ██████╗██╗     ███████╗
██╔══██╗██║██╔════╝██║ ██╔╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║     ██╔════╝
██████╔╝██║███████╗█████╔╝ ██║   ██║██████╔╝███████║██║     ██║     █████╗  
██╔══██╗██║╚════██║██╔═██╗ ██║   ██║██╔══██╗██╔══██║██║     ██║     ██╔══╝  
██║  ██║██║███████║██║  ██╗╚██████╔╝██║  ██║██║  ██║╚██████╗███████╗███████╗
╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚══════╝
```

**Production-grade Enterprise ML Platform — from raw data to inference, fully cloud-native**

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-844FBA?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.27+-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![MLflow](https://img.shields.io/badge/MLflow-tracking-0194E2?style=flat-square&logo=mlflow&logoColor=white)](https://mlflow.org/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=flat-square&logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![License: MIT](https://img.shields.io/badge/License-MIT-22C55E?style=flat-square)](./LICENSE)

<br />

</div>

---

## What This Is

RiskOracle is an end-to-end enterprise ML platform designed for production. It covers the full lifecycle — feature engineering, model training, experiment tracking, serving, monitoring, and GitOps deployment — on a cloud-native stack with security controls built in from the ground up.

This is not a tutorial scaffold or a demo project. The architecture reflects real production concerns: multi-environment Terraform modules, Kubernetes workloads behind Istio, OPA policy enforcement, Vault-based secrets, and a feature store that separates online and offline paths.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          RiskOracle Platform                                │
├──────────────────┬──────────────────┬───────────────────┬───────────────────┤
│   Data Platform  │   ML Platform    │    Serving Layer  │   Operations      │
│                  │                  │                   │                   │
│  Delta Lake      │  MLflow          │  Kubernetes       │  Prometheus       │
│  Apache Spark    │  Feast           │  Istio            │  Grafana          │
│  Airflow         │  Kubeflow        │  ArgoCD           │  ELK Stack        │
│                  │  Jupyter         │                   │                   │
├──────────────────┴──────────────────┴───────────────────┴───────────────────┤
│                         Infrastructure Layer                                │
│              Terraform  ·  Kubernetes  ·  Helm  ·  Docker                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                           Security Controls                                 │
│                    OPA  ·  Vault  ·  KMS  ·  Gitleaks                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Data & ML
| Component | Technology | Role |
|-----------|-----------|------|
| Feature Store | [Feast](https://feast.dev/) | Online/offline feature serving |
| Experiment Tracking | [MLflow](https://mlflow.org/) | Model versioning, metrics, artifacts |
| Pipeline Orchestration | [Kubeflow](https://www.kubeflow.org/) | ML workflow execution on K8s |
| Data Lakehouse | [Delta Lake](https://delta.io/) | ACID transactions on object storage |
| Batch Processing | [Apache Spark](https://spark.apache.org/) | Large-scale feature computation |
| Workflow Scheduler | [Apache Airflow](https://airflow.apache.org/) | DAG-based pipeline scheduling |

### Infrastructure
| Component | Technology | Role |
|-----------|-----------|------|
| Provisioning | [Terraform](https://www.terraform.io/) | Cloud infrastructure as code |
| Container Orchestration | [Kubernetes](https://kubernetes.io/) | Workload scheduling and scaling |
| Service Mesh | [Istio](https://istio.io/) | mTLS, traffic management, observability |
| GitOps | [ArgoCD](https://argoproj.github.io/cd/) | Continuous delivery to Kubernetes |
| Package Management | [Helm](https://helm.sh/) | Kubernetes application packaging |

### Observability
| Component | Technology | Role |
|-----------|-----------|------|
| Metrics | [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | Platform and model monitoring |
| Logging | ELK Stack | Centralised log aggregation and search |

### Security
| Component | Technology | Role |
|-----------|-----------|------|
| Policy Enforcement | [OPA](https://www.openpolicyagent.org/) | Admission control, authorisation |
| Secrets Management | [HashiCorp Vault](https://www.vaultproject.io/) | Dynamic secrets, PKI |
| Encryption | KMS | Data encryption at rest and in transit |
| Secret Scanning | [Gitleaks](https://gitleaks.io/) | Pre-commit secret detection |

---

## Repository Structure

```
riskoracle/
├── .devcontainer/          # Reproducible dev environment (VS Code / Codespaces)
├── .github/                # GitHub Actions CI/CD workflows
├── charts/                 # Helm charts for platform components
├── docs/                   # Architecture docs, ADRs, runbooks
├── infrastructure/         # Terraform modules (networking, compute, storage, IAM)
├── kubernetes/             # Raw Kubernetes manifests
├── ml/                     # Model code, training pipelines, evaluation
├── notebooks/              # Jupyter notebooks for exploration and prototyping
├── ops/                    # Operational runbooks and SOP documentation
├── scripts/                # Utility and automation scripts
├── security/               # OPA policies, Vault configs, security controls
├── src/                    # Core platform application code
├── tests/                  # Test suite (unit, integration, smoke)
├── tools/                  # Developer tooling and helpers
├── docker-compose.yml      # Local full-stack environment
├── Makefile                # Primary task runner
├── Makefile-small          # Lightweight local targets
├── Makefile-Large          # Full production-scale targets
└── pyproject.toml          # Python project config and dependencies
```

---

## Getting Started

### Prerequisites

```
Python >= 3.10
Docker + Docker Compose
Terraform >= 1.5
kubectl
make
```

### 1. Clone and configure

```bash
git clone https://github.com/aayostem/riskoracle.git
cd riskoracle

cp .env.example .env
# Edit .env with your environment-specific values
```

### 2. Install dependencies and pre-commit hooks

```bash
make setup
```

This installs Python dependencies and registers the pre-commit hook suite (ruff, black, gitleaks, YAML lint).

### 3. Start the local stack

```bash
# Lightweight local stack
make -f Makefile-small dev-up

# Full platform stack
make dev-up
```

### 4. Run smoke tests

```bash
python test_feature_retrieval.py   # Verify feature store connectivity
python test_inference.py           # Verify model serving endpoint
```

---

## Makefile Profiles

RiskOracle ships with three Makefile profiles to match your environment:

| Profile | File | When to use |
|---------|------|-------------|
| **Default** | `Makefile` | Standard development workflow |
| **Small** | `Makefile-small` | Local laptop, minimal resource footprint |
| **Large** | `Makefile-Large` | Full production-scale local simulation |

Key targets (all profiles):

```bash
make setup          # Install deps and hooks
make dev-up         # Start services
make dev-down       # Stop services
make test           # Run test suite
make lint           # Run linters
make infra-plan     # Terraform plan
make infra-apply    # Terraform apply
make deploy         # ArgoCD sync
```

---

## Infrastructure

Terraform modules live under `infrastructure/` and cover:

- **Networking** — VPC, subnets, security groups, NAT gateways
- **Compute** — Kubernetes node groups, autoscaling policies
- **Storage** — S3/GCS buckets for Delta Lake, MLflow artifact store
- **IAM** — Least-privilege roles for each platform component
- **Secrets** — Vault cluster provisioning and KMS key management

Apply infrastructure:

```bash
cd infrastructure/
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

---

## ML Platform

### Feature Engineering (Feast)

Features are defined in `ml/feature_store/` and served via Feast. The platform maintains separate online (low-latency) and offline (batch) stores.

### Experiment Tracking (MLflow)

All training runs log to MLflow. Access the UI:

```bash
make mlflow-ui    # Opens at http://localhost:5000
```

### Pipeline Execution (Kubeflow)

ML pipelines are defined as Kubeflow Pipelines components. Compile and submit:

```bash
make pipeline-compile   # Compile pipeline spec
make pipeline-submit    # Submit to Kubeflow
```

### Jupyter Environment

A custom Jupyter image is provided for exploration:

```bash
docker build -f Dockerfile.jupyter -t riskoracle-jupyter .
docker run -p 8888:8888 riskoracle-jupyter
```

---

## CI/CD

```
┌─────────────────────────────────────────────────────┐
│                  GitHub Actions                     │
│                                                     │
│  Push/PR  →  Lint  →  Test  →  Build  →  Publish  │
└────────────────────────────┬────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │     ArgoCD      │
                    │  (GitOps sync)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   Kubernetes    │
                    │   Cluster       │
                    └─────────────────┘
```

Workflows are defined under `.github/workflows/`. ArgoCD watches the `kubernetes/` and `charts/` directories for changes and applies them automatically.

---

## Observability

| Signal | Tool | Endpoint |
|--------|------|----------|
| Metrics | Prometheus + Grafana | `http://localhost:3000` |
| Logs | Kibana (ELK) | `http://localhost:5601` |
| Traces | Istio + Jaeger | `http://localhost:16686` |

Dashboards in Grafana cover platform health, model latency, feature freshness, and pipeline success rates.

---

## Security

- **OPA** policies in `security/` enforce admission control rules on all Kubernetes workloads
- **Vault** manages all dynamic secrets; static secrets are never committed to the repository
- **Gitleaks** runs on every commit via pre-commit to prevent accidental secret exposure
- **Istio** enforces mTLS between all services in the mesh
- **KMS** encrypts all data at rest in object storage and the secrets backend

See [SECURITY.md](./SECURITY.md) for the vulnerability reporting process.

---

## Recovery

Incident and recovery procedures are documented in [`recovery-procedure.md`](./recovery-procedure.md). This covers platform component failures, state recovery, and runbook references.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for branch strategy, commit conventions, PR process, and testing requirements.

---

## License

[MIT](./LICENSE) — Copyright © 2025 Ayo
