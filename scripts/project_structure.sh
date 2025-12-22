# Create the enterprise project structure
# ========================================

mkdir enterprise-ml-platform
cd enterprise-ml-platform

# Initialize Git Repository
git init
git branch -m main

# Create directory structure
mkdir -p .github/{workflows,ISSUE_TEMPLATE,PULL_REQUEST_TEMPLATE}
mkdir -p .devcontainer
mkdir -p charts/{mlflow,feast,airflow,prometheus-stack,istio}
mkdir -p infrastructure/{terraform,crossplane,terragrunt}
mkdir -p infrastructure/terraform/{modules,environments}
mkdir -p infrastructure/terraform/modules/{networking,kubernetes,databases,messaging,storage}
mkdir -p infrastructure/terraform/environments/{dev,staging,prod}
mkdir -p infrastructure/crossplane/{compositions,definitions,examples}
mkdir -p infrastructure/terragrunt/live/{global,dev,staging,prod}
mkdir -p kubernetes/{base,overlays,manifests}
mkdir -p kubernetes/base/{namespaces,configs,crds}
mkdir -p kubernetes/overlays/{dev,staging,prod}
mkdir -p src/{python,java,go}
mkdir -p src/python/{ml-service,feature-service,data-ingestion,model-monitoring}
mkdir -p data/{schemas,dbt,airflow,spark}
mkdir -p data/schemas/{avro,protobuf,json-schema}
mkdir -p data/dbt/{models,seeds,snapshots,macros}
mkdir -p data/airflow/{dags,plugins,config}
mkdir -p data/spark/{jobs,configs}
mkdir -p ml/{feast,mlflow,kubeflow,notebooks,serving}
mkdir -p ml/feast/{feature_repo,deployments,tests}
mkdir -p ml/mlflow/{projects,models,registry}
mkdir -p ml/kubeflow/{pipelines,components,experiments}
mkdir -p ml/notebooks/{exploratory,prototyping,research}
mkdir -p ml/serving/{kserve,seldon,triton}
mkdir -p ops/{monitoring,logging,tracing,alerting}
mkdir -p ops/monitoring/{prometheus,grafana,loki}
mkdir -p security/{policies,vault,scanners,compliance}
mkdir -p security/policies/{opa,checkov,tfsec}
mkdir -p docs/{architecture,runbooks,api,onboarding}
mkdir -p docs/architecture/{decision-records,system-context,c4-model}
mkdir -p tests/{unit,integration,e2e,performance,chaos}
mkdir -p tools/{scripts,generators,utilities}

# Initialize each Python service
for service in ml-service feature-service data-ingestion model-monitoring; do
  mkdir -p src/python/$service/{src,tests}
  mkdir -p src/python/$service/src/{api,models,services}
done

# Create empty files to maintain structure
find . -type d -empty -exec touch {}/.gitkeep \;