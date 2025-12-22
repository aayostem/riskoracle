#!/bin/bash
# deploy-platform.sh
# Complete deployment script for Enterprise ML Platform

set -e

echo "🚀 Deploying Enterprise ML Platform..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        exit 1
    fi
    
    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "terraform is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure..."
    
    cd infrastructure/terraform/environments/dev
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    # Apply infrastructure
    log_info "Applying infrastructure..."
    terraform apply -auto-approve
    
    # Get outputs
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    AWS_REGION=$(terraform output -raw aws_region)
    
    # Update kubeconfig
    log_info "Updating kubeconfig..."
    aws eks update-kubeconfig \
        --name $CLUSTER_NAME \
        --region $AWS_REGION
    
    cd ../../../..
    
    log_info "Infrastructure deployed successfully"
}

# Deploy Kubernetes components
deploy_kubernetes() {
    log_info "Deploying Kubernetes components..."
    
    # Create namespaces
    log_info "Creating namespaces..."
    kubectl apply -f kubernetes/base/namespaces/
    
    # Deploy ML platform
    log_info "Deploying ML platform..."
    kubectl apply -k kubernetes/overlays/dev/ml-platform/
    
    # Wait for deployments
    log_info "Waiting for MLFlow..."
    kubectl wait --for=condition=ready pod -l app=mlflow -n ml-platform --timeout=300s
    
    log_info "Waiting for Jupyter..."
    kubectl wait --for=condition=ready pod -l app=jupyter -n ml-platform --timeout=300s
    
    # Deploy monitoring
    log_info "Deploying monitoring stack..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        -f ops/monitoring/prometheus-stack/values.yaml
    
    # Deploy ingress
    log_info "Deploying ingress controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer
    
    log_info "Kubernetes components deployed successfully"
}

# Deploy ML components
deploy_ml_components() {
    log_info "Deploying ML components..."
    
    # Initialize MLflow
    log_info "Initializing MLflow..."
    kubectl exec -n ml-platform deploy/mlflow -- python -c "
import mlflow
mlflow.set_tracking_uri('http://localhost:5000')
exp_id = mlflow.create_experiment('fraud-detection')
print(f'MLflow initialized with experiment ID: {exp_id}')
"
    
    # Deploy Feast feature store
    log_info "Deploying Feast feature store..."
    kubectl apply -f kubernetes/overlays/dev/ml-platform/feast/
    
    # Deploy model serving
    log_info "Deploying model serving..."
    kubectl apply -f ml/serving/kserve/
    
    log_info "ML components deployed successfully"
}

# Deploy security components
deploy_security() {
    log_info "Deploying security components..."
    
    # Deploy Vault
    log_info "Deploying Vault..."
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update
    
    helm install vault hashicorp/vault \
        --namespace security \
        --create-namespace \
        -f security/vault/values.yaml
    
    # Deploy OPA Gatekeeper
    log_info "Deploying OPA Gatekeeper..."
    kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
    
    # Apply network policies
    log_info "Applying network policies..."
    kubectl apply -f kubernetes/base/network-policies.yaml
    
    log_info "Security components deployed successfully"
}

# Run tests
run_tests() {
    log_info "Running tests..."
    
    # Test MLflow
    log_info "Testing MLflow..."
    MLFLOW_POD=$(kubectl get pod -n ml-platform -l app=mlflow -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n ml-platform $MLFLOW_POD -- curl -f http://localhost:5000 || {
        log_error "MLflow test failed"
        return 1
    }
    
    # Test Jupyter
    log_info "Testing Jupyter..."
    JUPYTER_POD=$(kubectl get pod -n ml-platform -l app=jupyter -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n ml-platform $JUPYTER_POD -- curl -f http://localhost:8888/api || {
        log_error "Jupyter test failed"
        return 1
    }
    
    # Test Kubernetes cluster
    log_info "Testing Kubernetes cluster..."
    kubectl get nodes || {
        log_error "Kubernetes cluster test failed"
        return 1
    }
    
    log_info "All tests passed successfully"
}

# Print deployment information
print_deployment_info() {
    log_info "Gathering deployment information..."
    
    # Get Load Balancer URLs
    INGRESS_LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not ready")
    GRAFANA_LB=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not ready")
    
    # Get MLflow endpoint
    MLFLOW_ENDPOINT="http://mlflow.ml-platform.svc.cluster.local:5000"
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    
    echo ""
    echo "=============================================="
    echo "🚀 ENTERPRISE ML PLATFORM DEPLOYMENT COMPLETE"
    echo "=============================================="
    echo ""
    echo "📊 PLATFORM COMPONENTS:"
    echo "   • Kubernetes Cluster: $CLUSTER_NAME"
    echo "   • MLflow Tracking: $MLFLOW_ENDPOINT"
    echo "   • Jupyter Notebooks: http://jupyter.ml-platform.svc.cluster.local:8888"
    echo ""
    echo "🌐 EXTERNAL ENDPOINTS:"
    echo "   • Ingress Load Balancer: http://$INGRESS_LB"
    echo "   • Grafana Dashboard: http://$GRAFANA_LB"
    echo ""
    echo "🔧 NEXT STEPS:"
    echo "   1. Update DNS records for external endpoints"
    echo "   2. Configure authentication and authorization"
    echo "   3. Import sample data and models"
    echo "   4. Set up monitoring alerts"
    echo "   5. Configure CI/CD pipelines"
    echo ""
    echo "📚 DOCUMENTATION:"
    echo "   • Architecture: docs/architecture/"
    echo "   • API Documentation: docs/api/"
    echo "   • Runbooks: docs/runbooks/"
    echo ""
    echo "🛠️  MANAGEMENT COMMANDS:"
    echo "   • View all pods: kubectl get pods -A"
    echo "   • View ML platform: kubectl get all -n ml-platform"
    echo "   • View logs: kubectl logs -n ml-platform deploy/mlflow"
    echo "   • Port forward MLflow: kubectl port-forward -n ml-platform svc/mlflow 5000:5000"
    echo ""
    echo "=============================================="
}

# Main deployment flow
main() {
    log_info "Starting Enterprise ML Platform deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Deploy Kubernetes components
    deploy_kubernetes
    
    # Deploy ML components
    deploy_ml_components
    
    # Deploy security components
    deploy_security
    
    # Run tests
    run_tests
    
    # Print deployment information
    print_deployment_info
    
    log_info "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"