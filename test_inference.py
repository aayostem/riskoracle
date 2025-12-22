import requests
import json

# Get inference endpoint
SERVICE_HOSTNAME=$(kubectl get inferenceservice fraud-detection -n ml-platform -o jsonpath='{.status.url}' | cut -d'/' -f3)
ENDPOINT="http://${SERVICE_HOSTNAME}/v1/models/fraud-detection:predict"

# Create test data
test_data = {
    "instances": [
        {
            "amount": 1500.0,
            "time_of_day": 14,
            "customer_age": 35,
            "transaction_frequency": 5,
            "is_new_merchant": 0,
            "is_foreign": 0
        }
    ]
}

# Make prediction
response = requests.post(ENDPOINT, json=test_data)
print(f"Status Code: {response.status_code}")
print(f"Response: {response.json()}")
