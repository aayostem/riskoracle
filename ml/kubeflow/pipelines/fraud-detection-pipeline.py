import kfp
from kfp import dsl
from kfp.components import create_component_from_func
import mlflow

# Define components
@create_component_from_func
def load_data_op(
    data_path: str,
    output_data: dsl.OutputPath('dataframe')
):
    import pandas as pd
    import numpy as np
    import json
    
    # Load or generate data
    np.random.seed(42)
    n_samples = 10000
    
    data = pd.DataFrame({
        'amount': np.random.exponential(1000, n_samples),
        'time_of_day': np.random.randint(0, 24, n_samples),
        'customer_age': np.random.randint(18, 80, n_samples),
        'is_fraud': np.random.binomial(1, 0.01, n_samples)
    })
    
    # Save data
    data.to_parquet(output_data)
    
    # Return metadata
    metadata = {
        'samples': len(data),
        'fraud_rate': data['is_fraud'].mean(),
        'columns': list(data.columns)
    }
    
    return json.dumps(metadata)

@create_component_from_func
def train_model_op(
    input_data: dsl.InputPath('dataframe'),
    n_estimators: int = 100,
    max_depth: int = 6,
    output_model: dsl.OutputPath('model')
):
    import pandas as pd
    import xgboost as xgb
    from sklearn.model_selection import train_test_split
    import joblib
    import mlflow
    import json
    
    # Load data
    data = pd.read_parquet(input_data)
    
    # Prepare features
    X = data.drop('is_fraud', axis=1)
    y = data['is_fraud']
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    # Train model
    model = xgb.XGBClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        learning_rate=0.1,
        random_state=42
    )
    
    model.fit(X_train, y_train)
    
    # Save model
    joblib.dump(model, output_model)
    
    # Calculate metrics
    train_score = model.score(X_train, y_train)
    test_score = model.score(X_test, y_test)
    
    # Log to MLflow
    mlflow.set_tracking_uri("http://mlflow:5000")
    with mlflow.start_run():
        mlflow.log_params({
            'n_estimators': n_estimators,
            'max_depth': max_depth,
            'train_samples': len(X_train),
            'test_samples': len(X_test)
        })
        mlflow.log_metrics({
            'train_accuracy': train_score,
            'test_accuracy': test_score
        })
        mlflow.xgboost.log_model(model, "model")
    
    metrics = {
        'train_accuracy': train_score,
        'test_accuracy': test_score,
        'model_type': 'XGBoost'
    }
    
    return json.dumps(metrics)

@create_component_from_func
def evaluate_model_op(
    input_model: dsl.InputPath('model'),
    input_data: dsl.InputPath('dataframe'),
    output_report: dsl.OutputPath('json')
):
    import pandas as pd
    import joblib
    from sklearn.metrics import classification_report, roc_auc_score
    import json
    
    # Load model and data
    model = joblib.load(input_model)
    data = pd.read_parquet(input_data)
    
    # Prepare features
    X = data.drop('is_fraud', axis=1)
    y = data['is_fraud']
    
    # Make predictions
    y_pred = model.predict(X)
    y_pred_proba = model.predict_proba(X)[:, 1]
    
    # Calculate metrics
    report = classification_report(y, y_pred, output_dict=True)
    roc_auc = roc_auc_score(y, y_pred_proba)
    
    # Add ROC AUC to report
    report['roc_auc'] = roc_auc
    
    # Save report
    with open(output_report, 'w') as f:
        json.dump(report, f)
    
    return json.dumps({'roc_auc': roc_auc, 'status': 'completed'})

# Define pipeline
@dsl.pipeline(
    name='fraud-detection-pipeline',
    description='End-to-end fraud detection ML pipeline'
)
def fraud_detection_pipeline(
    data_path: str = '/data/transactions.parquet',
    n_estimators: int = 100,
    max_depth: int = 6
):
    # Define pipeline steps
    load_data_task = load_data_op(data_path=data_path)
    
    train_model_task = train_model_op(
        input_data=load_data_task.outputs['output_data'],
        n_estimators=n_estimators,
        max_depth=max_depth
    )
    
    evaluate_task = evaluate_model_op(
        input_model=train_model_task.outputs['output_model'],
        input_data=load_data_task.outputs['output_data']
    )
    
    # Set dependencies
    train_model_task.after(load_data_task)
    evaluate_task.after(train_model_task)

# Compile pipeline
if __name__ == '__main__':
    kfp.compiler.Compiler().compile(
        fraud_detection_pipeline,
        'fraud-detection-pipeline.yaml'
    )
    print("Pipeline compiled successfully!")
