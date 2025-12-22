#!/bin/bash
# setup-cert-manager.sh

set -e

echo "🔐 Setting up cert-manager for TLS certificates..."

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Create ClusterIssuer for Let's Encrypt production
cat > security/cert-manager/cluster-issuer-prod.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@ml-platform.example.com
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
          podTemplate:
            spec:
              nodeSelector:
                kubernetes.io/os: linux
EOF

kubectl apply -f security/cert-manager/cluster-issuer-prod.yaml

# Create Certificate for ML Platform
cat > security/cert-manager/ml-platform-certificate.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ml-platform-tls
  namespace: ml-platform
spec:
  secretName: ml-platform-tls-secret
  duration: 2160h # 90d
  renewBefore: 360h # 15d
  subject:
    organizations:
    - ML Platform Inc.
  commonName: ml-platform.example.com
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  dnsNames:
    - ml-platform.example.com
    - api.ml-platform.example.com
    - mlflow.ml-platform.example.com
    - jupyter.ml-platform.example.com
    - grafana.ml-platform.example.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
EOF

kubectl apply -f security/cert-manager/ml-platform-certificate.yaml

# Update Ingress to use TLS
cat > kubernetes/overlays/prod/ingress-tls.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ml-platform-ingress
  namespace: ml-platform
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains; preload";
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
      more_set_headers "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:;";
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ml-platform.example.com
    - api.ml-platform.example.com
    - mlflow.ml-platform.example.com
    - jupyter.ml-platform.example.com
    secretName: ml-platform-tls-secret
  rules:
  - host: ml-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ml-platform-ui
            port:
              number: 80
  - host: api.ml-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ml-platform-api
            port:
              number: 8080
  - host: mlflow.ml-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mlflow
            port:
              number: 5000
  - host: jupyter.ml-platform.example.com
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

kubectl apply -f kubernetes/overlays/prod/ingress-tls.yaml

echo "✅ cert-manager setup complete!"