from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import mlflow
import numpy as np
import joblib
import os
from typing import List, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="ML Service API",
    description="Machine Learning Model Serving API",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load model
MODEL_PATH = os.getenv("MODEL_PATH", "model.pkl")
try:
    model = joblib.load(MODEL_PATH)
    logger.info(f"Model loaded successfully from {MODEL_PATH}")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    model = None

# Request/Response models
class PredictionRequest(BaseModel):
    features: List[float]
    
class PredictionResponse(BaseModel):
    prediction: float
    confidence: float
    model_version: str = "1.0.0"

class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    mlflow_connected: bool

@app.get("/health")
async def health_check() -> HealthResponse:
    """Health check endpoint"""
    mlflow_connected = False
    try:
        # Try to connect to MLflow
        mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI", "http://mlflow:5000"))
        experiments = mlflow.search_experiments()
        mlflow_connected = len(experiments) > 0
    except Exception as e:
        logger.error(f"MLflow connection failed: {e}")
    
    return HealthResponse(
        status="healthy" if model else "degraded",
        model_loaded=model is not None,
        mlflow_connected=mlflow_connected
    )

@app.post("/predict")
async def predict(request: PredictionRequest) -> PredictionResponse:
    """Make predictions using the ML model"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Convert features to numpy array
        features_array = np.array(request.features).reshape(1, -1)
        
        # Make prediction
        prediction = model.predict(features_array)[0]
        prediction_proba = model.predict_proba(features_array)[0]
        
        # Calculate confidence
        confidence = float(np.max(prediction_proba))
        
        logger.info(f"Prediction made: {prediction} with confidence {confidence}")
        
        return PredictionResponse(
            prediction=float(prediction),
            confidence=confidence,
            model_version="1.0.0"
        )
    except Exception as e:
        logger.error(f"Prediction failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/model/info")
async def model_info():
    """Get model information"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        info = {
            "model_type": type(model).__name__,
            "n_features": model.n_features_in_ if hasattr(model, 'n_features_in_') else "unknown",
            "model_version": "1.0.0",
            "feature_importance": None
        }
        
        # Add feature importance if available
        if hasattr(model, 'feature_importances_'):
            info["feature_importance"] = model.feature_importances_.tolist()
        
        return info
    except Exception as e:
        logger.error(f"Failed to get model info: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
