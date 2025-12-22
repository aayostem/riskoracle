## Overview
This runbook provides procedures for responding to incidents in the ML Platform.

## Severity Levels

### P1 - Critical
- Platform completely unavailable
- Data loss or corruption
- Security breach

### P2 - High
- Major functionality degraded
- Performance severely impacted
- Multiple users affected

### P3 - Medium
- Minor functionality issues
- Single user affected
- Performance degradation

### P4 - Low
- Cosmetic issues
- Documentation errors
- Enhancement requests

## Incident Response Process

### 1. Detection
- Monitor alerts from Prometheus/AlertManager
- Check Grafana dashboards
- Review application logs
- Monitor user reports

### 2. Triage
- Determine severity level
- Identify affected components
- Escalate if necessary
- Create incident ticket

### 3. Investigation
- Gather relevant logs and metrics
- Identify root cause
- Document findings
- Determine mitigation steps

### 4. Resolution
- Implement fix or workaround
- Verify resolution
- Update stakeholders
- Close incident ticket

### 5. Post-Mortem
- Schedule post-mortem meeting
- Document lessons learned
- Update runbooks and procedures
- Implement preventive measures

## Common Incidents

### MLFlow Service Down

**Symptoms:**
- Cannot access MLFlow UI
- Model training jobs failing
- Experiment tracking unavailable

**Diagnosis:**
```bash
# Check MLFlow pod status
kubectl get pods -n ml-platform -l app=mlflow

# Check logs
kubectl logs -n ml-platform deploy/mlflow

# Check service endpoint
kubectl exec -n ml-platform deploy/mlflow -- curl -f http://localhost:5000
```

**Resolution:**
1. Restart MLFlow deployment:
   ```bash
   kubectl rollout restart deployment/mlflow -n ml-platform
   ```

2. Check database connectivity:
   ```bash
   kubectl exec -n ml-platform deploy/mlflow -- \
     python -c "import psycopg2; psycopg2.connect(host='postgres', dbname='ml_platform', user='admin', password='admin')"
   ```

3. Check S3 access:
   ```bash
   kubectl exec -n ml-platform deploy/mlflow -- \
     aws s3 ls s3://$(terraform output -raw s3_bucket_mlflow)/
   ```

### Model Performance Degradation

**Symptoms:**
- High latency in predictions
- Increased error rates
- Data drift detected

**Diagnosis:**
```bash
# Check model metrics
kubectl exec -n ml-platform deploy/model-monitoring -- \
  curl http://localhost:8082/monitor/alerts

# Check feature drift
kubectl exec -n ml-platform deploy/feature-service -- \
  curl http://localhost:8081/features/available
```

**Resolution:**
1. Check feature store data:
   ```bash
   kubectl exec -n ml-platform deploy/feature-service -- \
     python -c "from feast import FeatureStore; store = FeatureStore(repo_path='.'); print(store.list_feature_views())"
   ```

2. Trigger model retraining:
   ```bash
   # Run Kubeflow pipeline
   kfp run submit \
     -e fraud-detection \
     -r latest \
     -p fraud-detection-pipeline
   ```

3. Deploy new model version:
   ```bash
   kubectl patch inferenceservice fraud-detection \
     -n ml-platform \
     --type='json' \
     -p='[{"op": "replace", "path": "/spec/predictor/model/storageUri", "value": "s3://ml-platform-mlflow-artifacts/2/latest/artifacts/model"}]'
   ```

### Resource Exhaustion

**Symptoms:**
- Pods in CrashLoopBackOff
- High CPU/memory usage
- Node pressure conditions

**Diagnosis:**
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n ml-platform

# Check cluster autoscaler
kubectl logs -n kube-system deployment/cluster-autoscaler
```

**Resolution:**
1. Scale up cluster:
   ```bash
   # Update node group size
   kubectl scale deployment/mlflow -n ml-platform --replicas=3
   ```

2. Adjust resource limits:
   ```bash
   kubectl set resources deployment/mlflow \
     -n ml-platform \
     --limits=cpu=1,memory=2Gi \
     --requests=cpu=500m,memory=1Gi
   ```

3. Clean up resources:
   ```bash
   # Delete completed jobs
   kubectl delete jobs --field-selector status.successful=1 -n ml-platform

   # Delete old pods
   kubectl delete pods --field-selector status.phase=Succeeded -n ml-platform
   ```

## Communication Plan

### Internal Communication
- **Slack Channel**: #ml-platform-alerts
- **Email Group**: ml-platform-team@company.com
- **PagerDuty**: ML Platform On-Call

### External Communication
- **Status Page**: status.ml-platform.example.com
- **Customer Support**: support@ml-platform.example.com
- **API Documentation**: docs.ml-platform.example.com

## Escalation Matrix

| Time Elapsed | Action |
|-------------|---------|
| 0-15 min | On-call engineer investigates |
| 15-30 min | Team lead notified |
| 30-60 min | Engineering manager notified |
| 60+ min | Director of Engineering notified |

## Post-Mortem Template

### Incident Summary
- **Title**: [Brief description]
- **Date**: [YYYY-MM-DD]
- **Severity**: [P1-P4]
- **Duration**: [Start time - End time]

### Impact
- **Affected Services**: [List services]
- **Users Affected**: [Number/percentage]
- **Business Impact**: [Financial/reputation]

### Timeline
```
[HH:MM] Incident detected
[HH:MM] Investigation started
[HH:MM] Root cause identified
[HH:MM] Mitigation implemented
[HH:MM] Service restored
[HH:MM] Post-mortem scheduled
```

### Root Cause
[Detailed explanation of root cause]

### Contributing Factors
[List factors that contributed to the incident]

### Action Items
| Item | Owner | Due Date | Status |
|------|-------|----------|--------|
| [Action 1] | [Owner] | [Date] | [Status] |
| [Action 2] | [Owner] | [Date] | [Status] |

### Lessons Learned
[Key takeaways and improvements]