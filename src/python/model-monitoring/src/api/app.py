from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Dict, List, Optional
import pandas as pd
import numpy as np
from datetime import datetime
import logging
import asyncio

from monitoring.drift_detector import DataDriftDetector, ModelPerformanceMonitor

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Model Monitoring Service",
    description="Real-time model performance and drift monitoring",
    version="1.0.0"
)

# In-memory store for monitoring data (in production, use Redis/Database)
monitoring_store = {}

class MonitoringRequest(BaseModel):
    model_name: str
    features: List[Dict]
    predictions: List[float]
    actuals: Optional[List[float]] = None
    metadata: Optional[Dict] = None

class DriftCheckRequest(BaseModel):
    model_name: str
    features: List[Dict]
    reference_data_id: Optional[str] = None

class PerformanceMetrics(BaseModel):
    model_name: str
    timestamp: datetime
    metrics: Dict[str, float]
    drift_detected: bool
    performance_degradation: bool
    details: Dict

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "model-monitoring"}

@app.post("/monitor/prediction")
async def monitor_prediction(request: MonitoringRequest, background_tasks: BackgroundTasks):
    """Monitor a single prediction"""
    try:
        # Convert features to DataFrame
        features_df = pd.DataFrame(request.features)
        
        # Get or create drift detector
        detector_key = f"{request.model_name}_detector"
        if detector_key not in monitoring_store:
            # Create new detector with first batch of data as reference
            monitoring_store[detector_key] = DataDriftDetector(features_df)
        
        detector = monitoring_store[detector_key]
        
        # Check for drift
        drift_results = detector.detect_drift(features_df)
        
        # Check performance degradation if actuals provided
        performance_degradation = False
        if request.actuals is not None:
            monitor = ModelPerformanceMonitor(
                request.model_name,
                mlflow_tracking_uri="http://mlflow:5000"
            )
            
            # Calculate metrics
            from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
            
            actuals_array = np.array(request.actuals)
            predictions_array = np.array(request.predictions)
            
            metrics = {
                'accuracy': accuracy_score(actuals_array, predictions_array > 0.5),
                'precision': precision_score(actuals_array, predictions_array > 0.5, zero_division=0),
                'recall': recall_score(actuals_array, predictions_array > 0.5, zero_division=0),
                'f1_score': f1_score(actuals_array, predictions_array > 0.5, zero_division=0)
            }
            
            # Check performance degradation
            degradation_results = monitor.check_performance_degradation(metrics)
            performance_degradation = degradation_results['degradation_detected']
            
            # Log to MLflow in background
            background_tasks.add_task(
                monitor.log_performance_metrics,
                metrics=metrics,
                features=features_df,
                predictions=predictions_array,
                actuals=actuals_array,
                metadata=request.metadata
            )
        
        response = PerformanceMetrics(
            model_name=request.model_name,
            timestamp=datetime.now(),
            metrics=metrics if 'metrics' in locals() else {},
            drift_detected=drift_results['drift_detected'],
            performance_degradation=performance_degradation,
            details={
                'drift_results': drift_results,
                'feature_count': len(features_df.columns),
                'sample_count': len(features_df)
            }
        )
        
        return response
        
    except Exception as e:
        logger.error(f"Monitoring failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/monitor/drift")
async def check_drift(request: DriftCheckRequest):
    """Check for data drift"""
    try:
        # Convert features to DataFrame
        features_df = pd.DataFrame(request.features)
        
        # Get detector
        detector_key = f"{request.model_name}_detector"
        if detector_key not in monitoring_store:
            raise HTTPException(status_code=404, detail="No reference data found")
        
        detector = monitoring_store[detector_key]
        
        # Detect drift
        drift_results = detector.detect_drift(features_df)
        
        return {
            'model_name': request.model_name,
            'timestamp': datetime.now().isoformat(),
            'drift_detected': drift_results['drift_detected'],
            'details': drift_results
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Drift detection failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/monitor/reference/set")
async def set_reference_data(request: MonitoringRequest):
    """Set reference data for drift detection"""
    try:
        features_df = pd.DataFrame(request.features)
        
        detector_key = f"{request.model_name}_detector"
        monitoring_store[detector_key] = DataDriftDetector(features_df)
        
        return {
            'model_name': request.model_name,
            'reference_samples': len(features_df),
            'reference_features': list(features_df.columns),
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failed to set reference data: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/monitor/status/{model_name}")
async def get_monitoring_status(model_name: str):
    """Get monitoring status for a model"""
    detector_key = f"{model_name}_detector"
    
    if detector_key not in monitoring_store:
        return {
            'model_name': model_name,
            'status': 'not_monitored',
            'message': 'No reference data set for this model'
        }
    
    detector = monitoring_store[detector_key]
    
    return {
        'model_name': model_name,
        'status': 'monitoring_active',
        'reference_samples': len(detector.reference_data),
        'reference_features': list(detector.reference_data.columns),
        'last_updated': datetime.now().isoformat()
    }

@app.get("/monitor/alerts")
async def get_active_alerts(threshold: float = 0.25):
    """Get active monitoring alerts"""
    alerts = []
    
    for detector_key, detector in monitoring_store.items():
        model_name = detector_key.replace('_detector', '')
        
        # This is a simplified check - in production, you'd have actual recent data
        # For now, we'll return a placeholder response
        alerts.append({
            'model_name': model_name,
            'alert_type': 'data_drift',
            'severity': 'warning',
            'message': 'Potential data drift detected',
            'timestamp': datetime.now().isoformat(),
            'details': {
                'features_checked': len(detector.reference_data.columns),
                'samples_reference': len(detector.reference_data)
            }
        })
    
    return {
        'total_alerts': len(alerts),
        'alerts': alerts,
        'timestamp': datetime.now().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
