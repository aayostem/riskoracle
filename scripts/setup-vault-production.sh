#!/bin/bash
# setup-vault-production.sh

set -e

echo "🔐 Setting up HashiCorp Vault for production..."

# Deploy Vault in production mode
helm install vault hashicorp/vault \
  --namespace security \
  --create-namespace \
  --set 'server.ha.enabled=true' \
  --set 'server.ha.replicas=3' \
  --set 'server.ha.raft.enabled=true' \
  --set 'server.dataStorage.enabled=true' \
  --set 'server.dataStorage.size=10Gi' \
  --set 'server.service.type=LoadBalancer' \
  --set 'server.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=nlb' \
  --set 'ui.enabled=true' \
  --set 'ui.serviceType=LoadBalancer' \
  --set 'injector.enabled=true' \
  --set 'global.tlsDisable=false'

# Wait for Vault to be ready
echo "Waiting for Vault pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n security --timeout=300s

# Get Vault load balancer endpoint
VAULT_LB=$(kubectl get svc vault -n security -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export VAULT_ADDR="https://${VAULT_LB}:8200"

echo "Vault endpoint: $VAULT_ADDR"

# Initialize Vault
echo "Initializing Vault..."
VAULT_INIT_OUTPUT=$(vault operator init -key-shares=5 -key-threshold=3 -format=json)

# Parse initialization output
UNSEAL_KEYS=$(echo $VAULT_INIT_OUTPUT | jq -r '.unseal_keys_b64[]')
ROOT_TOKEN=$(echo $VAULT_INIT_OUTPUT | jq -r '.root_token')

# Save keys securely
mkdir -p security/vault/backup
echo "$VAULT_INIT_OUTPUT" > security/vault/backup/init_output.json
echo "Root token: $ROOT_TOKEN" > security/vault/backup/root_token.txt
echo "Unseal keys saved to security/vault/backup/"

# Unseal Vault
echo "Unsealing Vault..."
for key in $(echo $UNSEAL_KEYS | head -3); do
  vault operator unseal $key
done

# Login with root token
vault login $ROOT_TOKEN

# Enable secrets engines
echo "Enabling secrets engines..."
vault secrets enable -path=secret kv-v2
vault secrets enable -path=database database
vault secrets enable -path=aws aws
vault secrets enable -path=pki pki
vault secrets enable -path=transit transit

# Configure PKI
echo "Setting up PKI..."
vault secrets tune -max-lease-ttl=87600h pki
vault write pki/root/generate/internal \
    common_name=ml-platform.example.com \
    ttl=87600h

vault write pki/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

vault write pki/roles/ml-platform \
    allowed_domains=ml-platform.example.com \
    allow_subdomains=true \
    max_ttl=720h

# Configure AWS secrets engine
echo "Configuring AWS secrets engine..."
vault write aws/config/root \
    access_key=$AWS_ACCESS_KEY_ID \
    secret_key=$AWS_SECRET_ACCESS_KEY \
    region=us-east-1

vault write aws/roles/ml-platform-role \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ml-platform-*",
        "arn:aws:s3:::ml-platform-*/*"
      ]
    }
  ]
}
EOF

# Enable Kubernetes auth
echo "Configuring Kubernetes auth..."
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    kubernetes_host="https://$(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $NF}' | sed 's/https:\/\///')" \
    token_reviewer_jwt="$(kubectl get secret $(kubectl get serviceaccount vault -n security -o jsonpath='{.secrets[0].name}') -n security -o jsonpath='{.data.token}' | base64 --decode)" \
    kubernetes_ca_cert="$(kubectl get secret $(kubectl get serviceaccount vault -n security -o jsonpath='{.secrets[0].name}') -n security -o jsonpath='{.data.ca\.crt}' | base64 --decode)" \
    issuer="https://kubernetes.default.svc.cluster.local"

# Create policies
echo "Creating Vault policies..."

# ML Platform policy
cat > security/vault/policies/ml-platform.hcl << 'EOF'
# Read-only access to ML platform secrets
path "secret/data/ml-platform/*" {
  capabilities = ["read", "list"]
}

# Generate database credentials
path "database/creds/ml-platform" {
  capabilities = ["read"]
}

# Generate AWS credentials
path "aws/creds/ml-platform-role" {
  capabilities = ["read"]
}

# Encrypt/decrypt data
path "transit/encrypt/ml-platform" {
  capabilities = ["update"]
}

path "transit/decrypt/ml-platform" {
  capabilities = ["update"]
}
EOF

vault policy write ml-platform security/vault/policies/ml-platform.hcl

# Create Kubernetes auth role
vault write auth/kubernetes/role/ml-platform \
    bound_service_account_names=mlflow,jupyter,feature-service,model-monitoring \
    bound_service_account_namespaces=ml-platform \
    policies=ml-platform \
    ttl=1h \
    max_ttl=24h

# Configure database secrets engine
echo "Configuring PostgreSQL database secrets engine..."

# First, create PostgreSQL service in production
cat > kubernetes/overlays/prod/postgres.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: postgres-prod
  namespace: ml-platform
spec:
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgres-prod
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-prod
  namespace: ml-platform
spec:
  serviceName: postgres-prod
  replicas: 3
  selector:
    matchLabels:
      app: postgres-prod
  template:
    metadata:
      labels:
        app: postgres-prod
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: ml_platform_prod
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: ml-platform-secrets-prod
              key: DATABASE_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ml-platform-secrets-prod
              key: DATABASE_PASSWORD
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
          subPath: postgres
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi
      storageClassName: gp3
EOF

kubectl apply -f kubernetes/overlays/prod/postgres.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgres-prod -n ml-platform --timeout=300s

# Configure Vault database secrets engine
vault write database/config/ml-platform-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="ml-platform" \
    connection_url="postgresql://{{username}}:{{password}}@postgres-prod.ml-platform.svc.cluster.local:5432/ml_platform_prod?sslmode=require" \
    username="mlflow_prod" \
    password="$DATABASE_PASSWORD"

vault write database/roles/ml-platform \
    db_name=ml-platform-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Configure transit for encryption
vault write transit/keys/ml-platform type=aes256-gcm96

echo "✅ Vault setup complete!"