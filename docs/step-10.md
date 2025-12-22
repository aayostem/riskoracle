```bash
# Create AWS IAM User for Terraform
# ===================================
# Go to AWS Console → IAM → Users → Create User
# Name: terraform-user
# Permissions: AdministratorAccess (for demo) or create custom policy
# Save Access Key ID and Secret Access Key

# Configure AWS CLI
aws configure
# Enter:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: us-east-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity

# Create S3 Bucket for Terraform State
aws s3api create-bucket \
    --bucket terraform-state-$(aws sts get-caller-identity --query Account --output text) \
    --region us-east-1

# Create DynamoDB Table for State Locking
aws dynamodb create-table \
    --table-name terraform-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

```


# Initialize Terraform
cd infrastructure/terraform/environments/dev

# Update variables with your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/123456789012/${AWS_ACCOUNT_ID}/g" terraform.tfvars

# Initialize Terraform
terraform init
# This will:
# 1. Download required providers
# 2. Configure S3 backend
# 3. Set up state locking with DynamoDB

# Plan the deployment
terraform plan -out=tfplan

# Review the plan
terraform show tfplan

# Apply the infrastructure
terraform apply -auto-approve

# Expected outputs:
# cluster_name = ml-platform-dev
# cluster_endpoint = https://xxxxxxxxxxxxxxxx.gr7.us-east-1.eks.amazonaws.com
# vpc_id = vpc-xxxxxxxx
# redis_endpoint = ml-platform-dev.xxxxxx.xxxxx.cache.amazonaws.com:6379
# s3_bucket_mlflow = ml-platform-dev-mlflow-artifacts
# s3_bucket_data = ml-platform-dev-data-lake

# Get kubeconfig
aws eks update-kubeconfig \
    --name $(terraform output -raw cluster_name) \
    --region us-east-1

# Verify cluster access
kubectl get nodes
kubectl get pods -A


# Create Kubernetes Namespaces
kubectl apply -f kubernetes/base/namespaces/

# Create ConfigMaps and Secrets
# First, update the MLFlow IAM role ARN in the config
MLFLOW_IAM_ROLE=$(terraform output -raw mlflow_iam_role_arn)
echo "MLFLOW_IAM_ROLE_ARN: ${MLFLOW_IAM_ROLE}" > kubernetes/overlays/dev/configs/s3-config.yaml

# Apply the Kubernetes manifests
kubectl apply -k kubernetes/overlays/dev/ml-platform/

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=mlflow -n ml-platform --timeout=300s
kubectl wait --for=condition=ready pod -l app=jupyter -n ml-platform --timeout=300s

# Check deployment status
kubectl get all -n ml-platform


# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing

# Wait for Load Balancer to be provisioned
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

# Get Load Balancer DNS
INGRESS_LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Ingress Load Balancer: http://${INGRESS_LB}"

# Create Ingress for ML Platform services
cat > kubernetes/overlays/dev/ml-platform/ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ml-platform-ingress
  namespace: ml-platform
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: mlflow.dev.ml-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mlflow
            port:
              number: 5000
  - host: jupyter.dev.ml-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jupyter
            port:
              number: 8888
EOF

kubectl apply -f kubernetes/overlays/dev/ml-platform/ingress.yaml

# For testing, update local hosts file
echo "${INGRESS_LB} mlflow.dev.ml-platform.example.com jupyter.dev.ml-platform.example.com" | sudo tee -a /etc/hosts

# Install Prometheus Stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cat > ops/monitoring/prometheus-stack/values.yaml << 'EOF'
grafana:
  adminPassword: admin
  service:
    type: LoadBalancer
  ingress:
    enabled: true
    hosts:
      - grafana.dev.ml-platform.example.com

prometheus:
  service:
    type: LoadBalancer
  ingress:
    enabled: true
    hosts:
      - prometheus.dev.ml-platform.example.com

alertmanager:
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alerts@ml-platform.example.com'
      smtp_auth_username: 'your-email@gmail.com'
      smtp_auth_password: 'your-password'
    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'email-notifications'
    receivers:
    - name: 'email-notifications'
      email_configs:
      - to: 'team@ml-platform.example.com'
EOF

helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f ops/monitoring/prometheus-stack/values.yaml

# Wait for monitoring stack to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Get Grafana Load Balancer
GRAFANA_LB=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana: http://${GRAFANA_LB}"

# Update hosts file
echo "${GRAFANA_LB} grafana.dev.ml-platform.example.com" | sudo tee -a /etc/hosts















