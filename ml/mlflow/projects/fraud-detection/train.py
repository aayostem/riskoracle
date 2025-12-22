import argparse
import mlflow
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, roc_auc_score, accuracy_score
from sklearn.ensemble import RandomForestClassifier
from xgboost import XGBClassifier
import joblib
import os

def load_data(data_path: str):
    """Load and prepare data"""
    # In a real scenario, this would load from your data source
    # For demo purposes, we'll create synthetic data
    np.random.seed(42)
    n_samples = 10000
    
    # Create synthetic features
    data = pd.DataFrame({
        'amount': np.random.exponential(1000, n_samples),
        'time_of_day': np.random.randint(0, 24, n_samples),
        'day_of_week': np.random.randint(0, 7, n_samples),
        'customer_age': np.random.randint(18, 80, n_samples),
        'transaction_frequency': np.random.poisson(5, n_samples),
        'avg_transaction_amount': np.random.exponential(500, n_samples),
        'is_new_merchant': np.random.binomial(1, 0.1, n_samples),
        'is_foreign': np.random.binomial(1, 0.05, n_samples),
        'device_change': np.random.binomial(1, 0.02, n_samples),
        'location_change': np.random.binomial(1, 0.03, n_samples)
    })
    
    # Create target based on features (fraud probability)
    fraud_prob = (
        0.001 * data['amount'] / 1000 +
        0.2 * data['is_new_merchant'] +
        0.3 * data['is_foreign'] +
        0.4 * data['device_change'] +
        0.3 * data['location_change'] +
        np.random.normal(0, 0.1, n_samples)
    )
    
    data['is_fraud'] = (fraud_prob > fraud_prob.mean() + fraud_prob.std()).astype(int)
    
    return data

def train_model(X_train, y_train, n_estimators=100, max_depth=6):
    """Train XGBoost model"""
    model = XGBClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        learning_rate=0.1,
        objective='binary:logistic',
        random_state=42,
        eval_metric='logloss',
        use_label_encoder=False
    )
    
    model.fit(X_train, y_train)
    return model

def evaluate_model(model, X_test, y_test):
    """Evaluate model performance"""
    y_pred = model.predict(X_test)
    y_pred_proba = model.predict_proba(X_test)[:, 1]
    
    metrics = {
        'accuracy': accuracy_score(y_test, y_pred),
        'roc_auc': roc_auc_score(y_test, y_pred_proba),
        'precision_fraud': classification_report(y_test, y_pred, output_dict=True)['1']['precision'],
        'recall_fraud': classification_report(y_test, y_pred, output_dict=True)['1']['recall'],
        'f1_fraud': classification_report(y_test, y_pred, output_dict=True)['1']['f1-score']
    }
    
    return metrics

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-path', type=str, default='data/')
    parser.add_argument('--test-size', type=float, default=0.2)
    parser.add_argument('--n-estimators', type=int, default=100)
    parser.add_argument('--max-depth', type=int, default=6)
    args = parser.parse_args()
    
    # Start MLflow run
    with mlflow.start_run():
        # Log parameters
        mlflow.log_param("test_size", args.test_size)
        mlflow.log_param("n_estimators", args.n_estimators)
        mlflow.log_param("max_depth", args.max_depth)
        mlflow.log_param("model_type", "xgboost")
        
        # Load data
        data = load_data(args.data_path)
        
        # Prepare features and target
        feature_cols = [col for col in data.columns if col != 'is_fraud']
        X = data[feature_cols]
        y = data['is_fraud']
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=args.test_size, random_state=42, stratify=y
        )
        
        # Log dataset info
        mlflow.log_param("training_samples", len(X_train))
        mlflow.log_param("test_samples", len(X_test))
        mlflow.log_param("fraud_rate", y.mean())
        
        # Train model
        model = train_model(X_train, y_train, args.n_estimators, args.max_depth)
        
        # Evaluate model
        metrics = evaluate_model(model, X_test, y_test)
        
        # Log metrics
        for metric_name, metric_value in metrics.items():
            mlflow.log_metric(metric_name, metric_value)
        
        # Log model
        mlflow.xgboost.log_model(model, "model")
        
        # Save feature importance
        importance = pd.DataFrame({
            'feature': feature_cols,
            'importance': model.feature_importances_
        }).sort_values('importance', ascending=False)
        
        importance_path = "feature_importance.csv"
        importance.to_csv(importance_path, index=False)
        mlflow.log_artifact(importance_path)
        
        # Save model locally
        model_path = "model.pkl"
        joblib.dump(model, model_path)
        mlflow.log_artifact(model_path)
        
        print("Training completed successfully!")
        print(f"ROC-AUC: {metrics['roc_auc']:.4f}")
        print(f"Fraud Recall: {metrics['recall_fraud']:.4f}")

if __name__ == "__main__":
    main()
