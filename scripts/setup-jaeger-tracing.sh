#!/bin/bash
# setup-jaeger-tracing.sh

set -e

echo "🔍 Setting up distributed tracing with Jaeger..."

# Install Jaeger operator
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.49.0/jaeger-operator.yaml -n observability

# Wait for Jaeger operator
kubectl wait --for=condition=ready pod -l name=jaeger-operator -n observability --timeout=300s

# Create Jaeger instance for production
cat > ops/tracing/jaeger/jaeger-production.yaml << 'EOF'
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: ml-platform-jaeger
  namespace: observability
spec:
  strategy: production
  storage:
    type: elasticsearch
    esIndexCleaner:
      enabled: true
      numberOfDays: 7
      schedule: "55 23 * * *"
    options:
      es:
        server-urls: http://elasticsearch.monitoring.svc.cluster.local:9200
        username: elastic
        password: "${ELASTIC_PASSWORD}"
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - jaeger.ml-platform.example.com
    tls:
      - hosts:
          - jaeger.ml-platform.example.com
        secretName: jaeger-tls
  agent:
    strategy: DaemonSet
  collector:
    maxReplicas: 5
    resources:
      limits:
        memory: 1Gi
  query:
    replicas: 2
    resources:
      limits:
        memory: 512Mi
EOF

# Get Elasticsearch password
ELASTIC_PASSWORD=$(kubectl get secret elasticsearch-master-credentials -n monitoring -o jsonpath='{.data.password}' | base64 --decode)
sed -i "s/\${ELASTIC_PASSWORD}/$ELASTIC_PASSWORD/g" ops/tracing/jaeger/jaeger-production.yaml

# Apply Jaeger configuration
kubectl apply -f ops/tracing/jaeger/jaeger-production.yaml

# Create OpenTelemetry collector
cat > ops/tracing/opentelemetry/otel-collector.yaml << 'EOF'
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: deployment
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      batch:
        timeout: 10s
        send_batch_size: 1000
      memory_limiter:
        check_interval: 1s
        limit_mib: 1000
        spike_limit_mib: 100
    
    exporters:
      jaeger:
        endpoint: ml-platform-jaeger-collector.observability.svc.cluster.local:14250
        tls:
          insecure: true
      logging:
        loglevel: info
      prometheus:
        endpoint: "0.0.0.0:8889"
        namespace: otel
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [jaeger, logging]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus, logging]
EOF

kubectl apply -f ops/tracing/opentelemetry/otel-collector.yaml

# Update ML services to include OpenTelemetry instrumentation
cat > src/python/ml-service/src/otel_config.py << 'EOF'
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
import os

def setup_tracing(service_name: str):
    """Setup OpenTelemetry tracing for the service"""
    
    # Create resource
    resource = Resource.create({
        "service.name": service_name,
        "service.version": os.getenv("APP_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("ENVIRONMENT", "production")
    })
    
    # Create tracer provider
    tracer_provider = TracerProvider(resource=resource)
    
    # Configure OTLP exporter
    otlp_endpoint = os.getenv("OTLP_ENDPOINT", "otel-collector.observability.svc.cluster.local:4317")
    otlp_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    
    # Add span processor
    span_processor = BatchSpanProcessor(otlp_exporter)
    tracer_provider.add_span_processor(span_processor)
    
    # Set tracer provider
    trace.set_tracer_provider(tracer_provider)
    
    return tracer_provider

def instrument_fastapi(app):
    """Instrument FastAPI application"""
    FastAPIInstrumentor.instrument_app(app)
    RequestsInstrumentor().instrument()
    
def get_tracer(name: str):
    """Get tracer instance"""
    return trace.get_tracer(name)
EOF

# Update ML service deployment to include OpenTelemetry
cat > kubernetes/overlays/prod/patches/opentelemetry-injection.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
  namespace: ml-platform
spec:
  template:
    spec:
      containers:
      - name: mlflow
        env:
        - name: OTEL_SERVICE_NAME
          value: "mlflow"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc.cluster.local:4318"
        - name: OTEL_PROPAGATORS
          value: "tracecontext,baggage,b3"
        - name: OTEL_TRACES_SAMPLER
          value: "parentbased_traceidratio"
        - name: OTEL_TRACES_SAMPLER_ARG
          value: "0.1"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feature-service
  namespace: ml-platform
spec:
  template:
    spec:
      containers:
      - name: feature-service
        env:
        - name: OTEL_SERVICE_NAME
          value: "feature-service"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc.cluster.local:4318"
        ports:
        - containerPort: 4318
          name: otlp
        - containerPort: 8888
          name: metrics
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-monitoring
  namespace: ml-platform
spec:
  template:
    spec:
      containers:
      - name: model-monitoring
        env:
        - name: OTEL_SERVICE_NAME
          value: "model-monitoring"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc.cluster.local:4318"
EOF

kubectl apply -k kubernetes/overlays/prod/

echo "✅ Distributed tracing setup complete!"