#!/bin/bash
# deploy-production.sh

set -e

echo "🚀 Deploying ML Platform to Production..."

# Initialize Terraform
cd infrastructure/terraform/environments/prod

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update terraform.tfvars with actual account ID
sed -i "s/123456789012/${AWS_ACCOUNT_ID}/g" terraform.tfvars

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Plan deployment
echo "Creating Terraform plan..."
terraform plan -out=production.tfplan

# Review plan
echo "Reviewing plan..."
terraform show production.tfplan

# Confirm deployment
read -p "Continue with deployment? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

# Apply infrastructure
echo "Deploying infrastructure..."
terraform apply production.tfplan

# Get outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region)

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --alias ml-platform-prod

# Verify cluster access
echo "Verifying cluster access..."
kubectl config use-context ml-platform-prod
kubectl get nodes

echo "✅ Production infrastructure deployed!"