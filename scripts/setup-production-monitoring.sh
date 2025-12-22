#!/bin/bash
# setup-production-monitoring.sh

set -e

echo "📊 Setting up production monitoring stack..."

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus Stack with production configuration
cat > ops/monitoring/prometheus-stack/values-prod.yaml << 'EOF'
grafana:
  adminPassword: "$(openssl rand -base64 32)"
  persistence:
    enabled: true
    size: 20Gi
    storageClassName: gp3
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.ml-platform.example.com
    tls:
      - hosts:
          - grafana.ml-platform.example.com
        secretName: grafana-tls
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/auth-type: basic
      nginx.ingress.kubernetes.io/auth-secret: grafana-auth
      nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
  grafana.ini:
    server:
      domain: grafana.ml-platform.example.com
      root_url: https://grafana.ml-platform.example.com
    auth:
      disable_login_form: false
      disable_signout_menu: true
    auth.anonymous:
      enabled: false
    auth.basic:
      enabled: true
    log:
      mode: console
      level: info

prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: "100GB"
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 200Gi
    resources:
      requests:
        memory: 4Gi
        cpu: 2
      limits:
        memory: 8Gi
        cpu: 4
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    additionalScrapeConfigs:
      - job_name: 'mlflow'
        static_configs:
          - targets: ['mlflow.ml-platform.svc.cluster.local:5000']
        metrics_path: '/metrics'
        scrape_interval: 30s
      - job_name: 'feature-service'
        static_configs:
          - targets: ['feature-service.ml-platform.svc.cluster.local:8081']
        metrics_path: '/metrics'
        scrape_interval: 30s
      - job_name: 'model-serving'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ['ml-platform']
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_serving_kserve_io_inferenceservice]
            action: keep
            regex: (.+)
          - source_labels: [__meta_kubernetes_pod_container_port_number]
            action: keep
            regex: 8080

alertmanager:
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alerts@ml-platform.example.com'
      smtp_auth_username: 'alerts@ml-platform.example.com'
      smtp_auth_password: '${SMTP_PASSWORD}'
      slack_api_url: '${SLACK_WEBHOOK_URL}'
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'team-slack'
      routes:
        - match:
            severity: critical
          receiver: 'critical-slack'
          continue: true
        - match:
            severity: warning
          receiver: 'warning-slack'
    receivers:
      - name: 'team-slack'
        slack_configs:
          - channel: '#ml-platform-alerts'
            send_resolved: true
            title: '{{ template "slack.default.title" . }}'
            text: '{{ template "slack.default.text" . }}'
            icon_emoji: '🚨'
      - name: 'critical-slack'
        slack_configs:
          - channel: '#ml-platform-critical'
            send_resolved: true
            title: 'CRITICAL: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
            icon_emoji: '🔥'
      - name: 'warning-slack'
        slack_configs:
          - channel: '#ml-platform-warnings'
            send_resolved: true
            title: 'WARNING: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
            icon_emoji: '⚠️'

kube-state-metrics:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 200m

prometheus-node-exporter:
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
      cpu: 100m
EOF

# Generate random passwords
SMTP_PASSWORD=$(openssl rand -base64 32)
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Replace placeholders in values file
sed -i "s/\${SMTP_PASSWORD}/$SMTP_PASSWORD/g" ops/monitoring/prometheus-stack/values-prod.yaml
sed -i "s|\${SLACK_WEBHOOK_URL}|$SLACK_WEBHOOK_URL|g" ops/monitoring/prometheus-stack/values-prod.yaml

# Install Prometheus Stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 46.6.0 \
  -f ops/monitoring/prometheus-stack/values-prod.yaml

# Wait for monitoring stack to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s

# Create basic auth secret for Grafana
htpasswd -bc auth.txt admin "$(openssl rand -base64 32)"
kubectl create secret generic grafana-auth \
  --namespace monitoring \
  --from-file=auth=auth.txt \
  --dry-run=client -o yaml | kubectl apply -f -

rm auth.txt

# Create ML-specific Prometheus rules
cat > ops/monitoring/prometheus/rules/ml-rules.yaml << 'EOF'
groups:
  - name: ml-platform.rules
    rules:
      - alert: MLFlowHighLatency
        expr: histogram_quantile(0.95, rate(mlflow_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
          service: mlflow
        annotations:
          summary: "MLFlow high latency detected"
          description: "MLFlow p95 latency is {{ $value }}s (threshold: 1s)"
          
      - alert: FeatureStoreHighErrorRate
        expr: rate(feature_service_errors_total[5m]) / rate(feature_service_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
          service: feature-service
        annotations:
          summary: "Feature store high error rate"
          description: "Feature service error rate is {{ $value | humanizePercentage }} (threshold: 5%)"
          
      - alert: ModelServingHighLatency
        expr: histogram_quantile(0.99, rate(model_serving_latency_seconds_bucket[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
          service: model-serving
        annotations:
          summary: "Model serving high latency"
          description: "Model serving p99 latency is {{ $value }}s (threshold: 0.5s)"
          
      - alert: RedisMemoryHigh
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
        for: 5m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis memory usage high"
          description: "Redis memory usage is {{ $value | humanizePercentage }} (threshold: 80%)"
          
      - alert: JupyterNotebookCrashLoop
        expr: increase(kube_pod_container_status_restarts_total{container="jupyter"}[10m]) > 3
        for: 2m
        labels:
          severity: critical
          service: jupyter
        annotations:
          summary: "Jupyter notebook crash loop detected"
          description: "Jupyter notebook has restarted {{ $value }} times in the last 10 minutes"
          
      - alert: ModelPredictionDrift
        expr: model_prediction_drift_score > 0.25
        for: 10m
        labels:
          severity: warning
          service: model-monitoring
        annotations:
          summary: "Model prediction drift detected"
          description: "Model prediction drift score is {{ $value }} (threshold: 0.25)"
          
      - alert: DataQualityIssues
        expr: data_quality_score < 0.9
        for: 15m
        labels:
          severity: warning
          service: data-quality
        annotations:
          summary: "Data quality issues detected"
          description: "Data quality score is {{ $value }} (threshold: 0.9)"
EOF

# Apply Prometheus rules
kubectl apply -f ops/monitoring/prometheus/rules/ml-rules.yaml

# Create Grafana dashboards
cat > ops/monitoring/grafana/dashboards/ml-platform-overview.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "ML Platform - Production Overview",
    "tags": ["ml-platform", "production", "overview"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Platform Health",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(up{namespace=\"ml-platform\"}) / count(up{namespace=\"ml-platform\"}) * 100",
            "legendFormat": "Service Availability",
            "format": "percentunit"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 99}
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "title": "Total Predictions",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(increase(model_predictions_total[1h]))",
            "legendFormat": "Predictions/Hour"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Prediction Latency (p95)",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, sum(rate(model_serving_latency_seconds_bucket[5m])) by (le, model_name))",
            "legendFormat": "{{model_name}}"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
        "fieldConfig": {
          "defaults": {
            "unit": "s",
            "decimals": 3
          }
        }
      },
      {
        "id": 4,
        "title": "Error Rate by Service",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(feature_service_errors_total[5m]) / rate(feature_service_requests_total[5m])",
            "legendFormat": "Feature Service"
          },
          {
            "expr": "rate(model_serving_errors_total[5m]) / rate(model_serving_requests_total[5m])",
            "legendFormat": "Model Serving"
          },
          {
            "expr": "rate(mlflow_errors_total[5m]) / rate(mlflow_requests_total[5m])",
            "legendFormat": "MLFlow"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16},
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "decimals": 3
          }
        }
      },
      {
        "id": 5,
        "title": "Resource Utilization",
        "type": "timeseries",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"ml-platform\"}[5m])) by (pod)",
            "legendFormat": "{{pod}} - CPU"
          },
          {
            "expr": "sum(container_memory_working_set_bytes{namespace=\"ml-platform\"}) by (pod) / 1024 / 1024 / 1024",
            "legendFormat": "{{pod}} - Memory (GB)"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      },
      {
        "id": 6,
        "title": "Data Drift Detection",
        "type": "timeseries",
        "targets": [
          {
            "expr": "model_prediction_drift_score",
            "legendFormat": "Prediction Drift"
          },
          {
            "expr": "model_feature_drift_score",
            "legendFormat": "Feature Drift"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32},
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 0.1},
                {"color": "red", "value": 0.25}
              ]
            }
          }
        }
      }
    ],
    "time": {
      "from": "now-6h",
      "to": "now"
    },
    "refresh": "30s"
  }
}
EOF

# Create dashboard for feature store
cat > ops/monitoring/grafana/dashboards/feature-store.json << 'EOF'
{
  "dashboard": {
    "title": "Feature Store - Production",
    "panels": [
      {
        "title": "Feature Retrieval Latency",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(feature_retrieval_latency_seconds_bucket[5m]))",
            "legendFormat": "p95"
          },
          {
            "expr": "histogram_quantile(0.99, rate(feature_retrieval_latency_seconds_bucket[5m]))",
            "legendFormat": "p99"
          }
        ]
      },
      {
        "title": "Cache Hit Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(feature_cache_hits_total[5m]) / (rate(feature_cache_hits_total[5m]) + rate(feature_cache_misses_total[5m]))",
            "legendFormat": "Cache Hit Rate"
          }
        ]
      },
      {
        "title": "Feature Store Throughput",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(feature_requests_total[5m])",
            "legendFormat": "Requests/Second"
          }
        ]
      }
    ]
  }
}
EOF

echo "✅ Production monitoring setup complete!"