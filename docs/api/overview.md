# ML Platform API Documentation

## Overview
The ML Platform provides REST APIs for managing the machine learning lifecycle.

## Base URL
```
https://api.ml-platform.example.com/v1
```

## Authentication
All API requests require authentication using JWT tokens.

### Getting a Token
```bash
curl -X POST https://api.ml-platform.example.com/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "username": "your-username",
    "password": "your-password"
  }'
```

Response:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "expires_in": 3600
}
```

### Using the Token
```bash
curl -H "Authorization: Bearer <token>" \
  https://api.ml-platform.example.com/v1/experiments
```

## API Endpoints

### Experiments API

#### List Experiments
```http
GET /experiments
```

**Response:**
```json
{
  "experiments": [
    {
      "experiment_id": "1",
      "name": "fraud-detection",
      "artifact_location": "s3://ml-platform-mlflow-artifacts/1",
      "lifecycle_stage": "active",
      "tags": {
        "project": "fraud-detection",
        "team": "ml-engineering"
      }
    }
  ]
}
```

#### Create Experiment
```http
POST /experiments
```

**Request:**
```json
{
  "name": "customer-churn",
  "tags": {
    "project": "customer-analytics",
    "priority": "high"
  }
}
```

### Models API

#### List Models
```http
GET /models
```

#### Register Model
```http
POST /models
```

**Request:**
```json
{
  "name": "fraud-detection-v2",
  "description": "Fraud detection model version 2",
  "run_id": "abc123def456",
  "tags": {
    "framework": "xgboost",
    "version": "2.0.0"
  }
}
```

### Predictions API

#### Make Prediction
```http
POST /predict
```

**Request:**
```json
{
  "model": "fraud-detection",
  "version": "latest",
  "features": {
    "amount": 1500.0,
    "time_of_day": 14,
    "customer_age": 35,
    "transaction_frequency": 5
  }
}
```

**Response:**
```json
{
  "prediction": 0.85,
  "confidence": 0.92,
  "model_version": "2.0.0",
  "request_id": "req_123456"
}
```

### Monitoring API

#### Get Model Metrics
```http
GET /models/{model_name}/metrics
```

#### Check Data Drift
```http
POST /monitoring/drift
```

**Request:**
```json
{
  "model_name": "fraud-detection",
  "features": [
    {
      "amount": 1500.0,
      "time_of_day": 14
    }
  ]
}
```

## Rate Limits
- **Free Tier**: 100 requests/minute
- **Professional Tier**: 1000 requests/minute
- **Enterprise Tier**: Custom limits

## Error Codes

| Code | Description |
|------|-------------|
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 429 | Too Many Requests |
| 500 | Internal Server Error |

## SDKs
- **Python**: `pip install ml-platform-sdk`
- **Java**: Available via Maven Central
- **JavaScript**: `npm install ml-platform-sdk`

## Examples

### Python Example
```python
from ml_platform import MLPlatformClient

client = MLPlatformClient(
    api_key="your-api-key",
    endpoint="https://api.ml-platform.example.com"
)

# Make prediction
prediction = client.predict(
    model="fraud-detection",
    features={
        "amount": 1500.0,
        "time_of_day": 14
    }
)

print(f"Fraud probability: {prediction['prediction']}")
```

### cURL Example
```bash
curl -X POST https://api.ml-platform.example.com/v1/predict \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "fraud-detection",
    "features": {
      "amount": 1500.0,
      "time_of_day": 14
    }
  }'
```