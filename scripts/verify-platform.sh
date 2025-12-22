#!/bin/bash
# verify-platform.sh
# Complete verification script for the ML Platform

echo "🔍 Verifying Enterprise ML Platform deployment..."

# Function to test service
test_service() {
    local service_name=$1
    local namespace=$2
    local port=$3
    local endpoint=$4
    
    echo "Testing $service_name..."
    
    # Get pod name
    pod_name=$(kubectl get pods -n $namespace -l app=$service_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        echo "❌ $service_name pod not found"
        return 1
    fi
    
    # Test connectivity
    if kubectl exec -n $namespace $pod_name -- curl -f http://localhost:$port$endpoint >/dev/null 2>&1; then
        echo "✅ $service_name is healthy"
        return 0
    else
        echo "❌ $service_name health check failed"
        return 1
    fi
}

# Test all services
echo ""
echo "Testing core services..."
echo "========================"

test_service "mlflow" "ml-platform" "5000" "/"
test_service "jupyter" "ml-platform" "8888" "/api"
test_service "redis" "ml-platform" "6379" "/ping"

# Test Kubernetes cluster
echo ""
echo "Testing Kubernetes cluster..."
echo "============================="

kubectl get nodes
kubectl get pods -n ml-platform
kubectl get svc -n ml-platform

# Test MLflow API
echo ""
echo "Testing MLflow API..."
echo "====================="

MLFLOW_POD=$(kubectl get pod -n ml-platform -l app=mlflow -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n ml-platform $MLFLOW_POD -- python -c "
import mlflow
mlflow.set_tracking_uri('http://localhost:5000')
exps = mlflow.search_experiments()
print(f'Found {len(exps)} experiments')
for exp in exps:
    print(f'  - {exp.name}')
"; then
    echo "✅ MLflow API is working"
else
    echo "❌ MLflow API test failed"
fi

# Test feature store
echo ""
echo "Testing Feature Store..."
echo "========================"

FEATURE_POD=$(kubectl get pod -n ml-platform -l app=feature-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$FEATURE_POD" ]; then
    if kubectl exec -n ml-platform $FEATURE_POD -- curl -f http://localhost:8081/health; then
        echo "✅ Feature Store is healthy"
    else
        echo "❌ Feature Store health check failed"
    fi
else
    echo "⚠️  Feature Store not deployed"
fi

# Test model serving
echo ""
echo "Testing Model Serving..."
echo "========================"

if kubectl get inferenceservice fraud-detection -n ml-platform >/dev/null 2>&1; then
    echo "✅ Model Serving is deployed"
    
    # Get inference endpoint
    SERVICE_HOSTNAME=$(kubectl get inferenceservice fraud-detection -n ml-platform -o jsonpath='{.status.url}' | cut -d'/' -f3)
    
    # Create test request
    cat > test_request.json << 'EOF'
EOF
    
    # Test inference
    if curl -f -X POST http://$SERVICE_HOSTNAME/v1/models/fraud-detection:predict \
        -H "Content-Type: application/json" \
        -d @test_request.json >/dev/null 2>&1; then
        echo "✅ Model inference is working"
    else
        echo "❌ Model inference test failed"
    fi
    
    rm -f test_request.json
else
    echo "⚠️  Model Serving not deployed"
fi

# Test monitoring
echo ""
echo "Testing Monitoring..."
echo "===================="

if kubectl get svc monitoring-grafana -n monitoring >/dev/null 2>&1; then
    echo "✅ Monitoring stack is deployed"
    
    # Test Prometheus
    PROM_POD=$(kubectl get pod -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n monitoring $PROM_POD -- wget -q -O- http://localhost:9090/api/v1/query?query=up >/dev/null 2>&1; then
        echo "✅ Prometheus is healthy"
    else
        echo "❌ Prometheus health check failed"
    fi
else
    echo "⚠️  Monitoring stack not deployed"
fi

# Test security
echo ""
echo "Testing Security..."
echo "==================="

if kubectl get pod -n security -l app.kubernetes.io/name=vault >/dev/null 2>&1; then
    echo "✅ Vault is deployed"
else
    echo "⚠️  Vault not deployed"
fi

if kubectl get pod -n gatekeeper-system -l control-plane=controller-manager >/dev/null 2>&1; then
    echo "✅ OPA Gatekeeper is deployed"
else
    echo "⚠️  OPA Gatekeeper not deployed"
fi

# Summary
echo ""
echo "📊 DEPLOYMENT VERIFICATION SUMMARY"
echo "=================================="
echo ""
echo "Platform Status:"
echo "• Kubernetes Cluster: $(kubectl config current-context)"
echo "• ML Platform Namespace: $(kubectl get ns ml-platform -o jsonpath='{.status.phase}')"
echo "• Total Pods in ML Platform: $(kubectl get pods -n ml-platform --no-headers | wc -l)"
echo ""
echo "Next Steps:"
echo "1. Configure DNS for external access"
echo "2. Set up authentication and authorization"
echo "3. Import your data and models"
echo "4. Configure monitoring alerts"
echo "5. Run load tests"
echo ""
echo "🎉 Platform verification complete!"