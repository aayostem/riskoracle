import mlflow
import boto3
from datetime import datetime

# Set MLflow tracking URI
MLFLOW_TRACKING_URI = "http://mlflow:5000"
mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)

# Create experiment
experiment_name = "fraud-detection-production"
try:
    experiment_id = mlflow.create_experiment(experiment_name)
    print(f"Created experiment: {experiment_name} with ID: {experiment_id}")
except:
    experiment = mlflow.get_experiment_by_name(experiment_name)
    experiment_id = experiment.experiment_id
    print(f"Experiment already exists: {experiment_name}")

# Test connection and configuration
with mlflow.start_run(experiment_id=experiment_id, run_name="configuration-test"):
    mlflow.log_param("configured_at", datetime.now().isoformat())
    mlflow.log_metric("test_metric", 1.0)
    mlflow.set_tag("environment", "development")
    
    # Test artifact logging
    test_data = "Configuration successful!"
    mlflow.log_text(test_data, "configuration_test.txt")
    
print("MLflow configuration completed successfully!")
