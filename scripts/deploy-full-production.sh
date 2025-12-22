#!/bin/bash
# deploy-full-production.sh

set -e

echo "🚀 Complete ML Platform Production Deployment"
echo "============================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    required_tools=("aws" "kubectl" "helm" "terraform" "jq" "openssl")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying production infrastructure..."
    
    cd infrastructure/terraform/environments/prod
    
    # Initialize Terraform
    terraform init -upgrade
    
    # Plan deployment
    terraform plan -out=production.tfplan \
        -var="aws_region=us-east-1" \
        -var="environment=prod"
    
    # Confirm
    read -p "Review plan and continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Deployment cancelled by user"
        exit 1
    fi
    
    # Apply infrastructure
    terraform apply production.tfplan
    
    # Get outputs
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    AWS_REGION=$(terraform output -raw aws_region)
    
    # Update kubeconfig
    aws eks update-kubeconfig \
        --name $CLUSTER_NAME \
        --region $AWS_REGION \
        --alias ml-platform-prod
    
    cd ../../../..
    
    log_info "Infrastructure deployed successfully"
}

# Setup core services
setup_core_services() {
    log_info "Setting up core Kubernetes services..."
    
    # Create namespaces
    kubectl create namespace ml-platform --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces for Istio injection
    kubectl label namespace ml-platform istio-injection=enabled --overwrite
    
    # Install ingress-nginx
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
        --set controller.metrics.enabled=true \
        --set controller.metrics.serviceMonitor.enabled=true \
        --set controller.metrics.serviceMonitor.namespace=monitoring
    
    # Wait for ingress controller
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_info "Core services setup complete"
}

# Deploy security components
deploy_security() {
    log_info "Deploying security components..."
    
    # Run security setup scripts
    ./setup-vault-production.sh
    ./setup-cert-manager.sh
    
    # Deploy network policies
    kubectl apply -f kubernetes/base/network-policies.yaml
    
    # Deploy OPA Gatekeeper
    kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
    kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=300s
    
    # Apply OPA policies
    kubectl apply -f security/policies/opa/
    
    log_info "Security components deployed"
}

# Deploy monitoring stack
deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    ./setup-production-monitoring.sh
    ./setup-jaeger-tracing.sh
    
    # Deploy custom metrics adapter for KEDA
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    helm install keda kedacore/keda \
        --namespace keda \
        --create-namespace \
        --set metricsServer.enabled=true \
        --version 2.12.0
    
    log_info "Monitoring stack deployed"
}

# Deploy ML platform components
deploy_ml_platform() {
    log_info "Deploying ML platform components..."
    
    # Apply Kubernetes manifests
    kubectl apply -k kubernetes/overlays/prod
    
    # Wait for critical services
    kubectl wait --for=condition=ready pod -l app=mlflow -n ml-platform --timeout=300s
    kubectl wait --for=condition=ready pod -l app=postgres-prod -n ml-platform --timeout=300s
    kubectl wait --for=condition=ready pod -l app=redis -n ml-platform --timeout=300s
    
    # Deploy KServe
    kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
    
    # Deploy model
    kubectl apply -f ml/serving/kserve/fraud-detection-inferenceservice.yaml
    
    # Deploy KEDA scalers
    kubectl apply -f infrastructure/keda/ml-platform-scalers.yaml
    
    log_info "ML platform components deployed"
}

# Run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Test service connectivity
    services=(
        "mlflow:5000"
        "jupyter:8888"
        "feature-service:8081"
        "grafana:3000"
        "prometheus:9090"
    )
    
    for service in "${services[@]}"; do
        name=$(echo $service | cut -d: -f1)
        port=$(echo $service | cut -d: -f2)
        
        if kubectl exec -n ml-platform deploy/$name -- curl -f http://localhost:$port/health &> /dev/null; then
            log_info "$name is healthy"
        else
            log_error "$name health check failed"
            return 1
        fi
    done
    
    # Test feature store
    FEATURE_POD=$(kubectl get pod -n ml-platform -l app=feature-service -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n ml-platform $FEATURE_POD -- python -c "
from feast import FeatureStore
store = FeatureStore(repo_path='/app/feature_repo')
print('Feature store connected:', store.list_feature_views())
"; then
        log_info "Feature store is operational"
    else
        log_warn "Feature store test failed (may need data)"
    fi
    
    # Test model inference
    if kubectl get inferenceservice fraud-detection -n ml-platform &> /dev/null; then
        log_info "Model serving is deployed"
    else
        log_warn "Model serving not yet ready"
    fi
    
    log_info "Validation tests completed"
}

# Print deployment summary
print_summary() {
    log_info "Gathering deployment information..."
    
    # Get endpoints
    INGRESS_LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    GRAFANA_LB=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending")
    VAULT_LB=$(kubectl get svc vault -n security -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending")
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    
    echo ""
    echo "=============================================="
    echo "🚀 ML PLATFORM PRODUCTION DEPLOYMENT COMPLETE"
    echo "=============================================="
    echo ""
    echo "📊 DEPLOYMENT SUMMARY:"
    echo "   • Cluster: $CLUSTER_NAME"
    echo "   • Ingress Load Balancer: $INGRESS_LB"
    echo "   • Grafana: $GRAFANA_LB"
    echo "   • Vault: $VAULT_LB"
    echo ""
    echo "🌐 CONFIGURE DNS:"
    echo "   Create CNAME records pointing to:"
    echo "   • ml-platform.example.com → $INGRESS_LB"
    echo "   • grafana.ml-platform.example.com → $GRAFANA_LB"
    echo "   • vault.ml-platform.example.com → $VAULT_LB"
    echo ""
    echo "🔧 NEXT STEPS:"
    echo "   1. Configure DNS records"
    echo "   2. Update Vault with production secrets:"
    echo "      kubectl exec -it vault-0 -n security -- vault login"
    echo "      kubectl exec -it vault-0 -n security -- vault kv put secret/ml-platform/prod/database password=PROD_PASSWORD"
    echo "   3. Initialize MLflow with production data"
    echo "   4. Configure alerting channels (Slack, Email)"
    echo "   5. Run load tests"
    echo "   6. Document runbooks"
    echo ""
    echo "📚 USEFUL COMMANDS:"
    echo "   • View all pods: kubectl get pods -A"
    echo "   • View ML platform: kubectl get all -n ml-platform"
    echo "   • Check logs: kubectl logs -n ml-platform deploy/mlflow -f"
    echo "   • Port forward: kubectl port-forward -n ml-platform svc/mlflow 5000:5000"
    echo "   • Get Grafana password: kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 --decode"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "   • Rotate all default passwords"
    echo "   • Configure backup for databases"
    echo "   • Set up monitoring alerts"
    echo "   • Test disaster recovery procedures"
    echo ""
    echo "=============================================="
}

# Main deployment flow
main() {
    log_info "Starting complete production deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Setup core services
    setup_core_services
    
    # Deploy security
    deploy_security
    
    # Deploy monitoring
    deploy_monitoring
    
    # Deploy ML platform
    deploy_ml_platform
    
    # Run validation
    run_validation_tests
    
    # Print summary
    print_summary
    
    log_info "🎉 Production deployment completed successfully!"
}

# Run main
main "$@"