from fastapi import FastAPI, HTTPException
from feast import FeatureStore
import pandas as pd
from datetime import datetime
import logging
from pydantic import BaseModel
from typing import List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Feature Store Service",
    description="Real-time feature serving for ML models",
    version="1.0.0"
)

# Initialize Feature Store
store = FeatureStore(repo_path="/app/feature_repo")

# Request/Response models
class FeatureRequest(BaseModel):
    entity_type: str
    entity_id: str
    features: List[str]
    timestamp: Optional[datetime] = None

class FeatureResponse(BaseModel):
    entity_id: str
    features: dict
    timestamp: datetime

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test feature store connection
        online_features = store.get_online_features(
            features=["customer_stats:avg_transaction_amount"],
            entity_rows=[{"customer_id": "test_customer"}]
        )
        return {"status": "healthy", "feature_store": "connected"}
    except Exception as e:
        logger.error(f"Feature store health check failed: {e}")
        return {"status": "unhealthy", "error": str(e)}

@app.post("/features")
async def get_features(request: FeatureRequest) -> FeatureResponse:
    """Get features for an entity"""
    try:
        # Prepare entity rows
        entity_rows = [{f"{request.entity_type}_id": request.entity_id}]
        
        # Get features from Feast
        feature_vector = store.get_online_features(
            features=request.features,
            entity_rows=entity_rows
        ).to_dict()
        
        # Extract features
        features = {}
        for feature_name in request.features:
            if feature_name in feature_vector:
                features[feature_name] = feature_vector[feature_name][0]
        
        return FeatureResponse(
            entity_id=request.entity_id,
            features=features,
            timestamp=datetime.now()
        )
    except Exception as e:
        logger.error(f"Failed to get features: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/features/batch")
async def get_features_batch(requests: List[FeatureRequest]) -> List[FeatureResponse]:
    """Get features for multiple entities"""
    responses = []
    for request in requests:
        try:
            response = await get_features(request)
            responses.append(response)
        except Exception as e:
            logger.error(f"Failed to get features for {request.entity_id}: {e}")
            responses.append({
                "entity_id": request.entity_id,
                "error": str(e),
                "features": {}
            })
    
    return responses

@app.get("/features/entities/{entity_type}")
async def list_entities(entity_type: str, limit: int = 100):
    """List entities of a given type"""
    # Note: This is a simplified version. In production, you'd query your data source.
    return {
        "entity_type": entity_type,
        "entities": [f"{entity_type}_{i}" for i in range(min(limit, 100))],
        "count": min(limit, 100)
    }

@app.get("/features/available")
async def list_available_features():
    """List all available features"""
    try:
        feature_views = store.list_feature_views()
        
        features = []
        for fv in feature_views:
            for feature in fv.features:
                features.append({
                    "name": f"{fv.name}:{feature.name}",
                    "dtype": str(feature.dtype),
                    "entity": fv.entities[0].name if fv.entities else "unknown",
                    "description": feature.labels.get("description", "")
                })
        
        return {
            "feature_count": len(features),
            "features": features
        }
    except Exception as e:
        logger.error(f"Failed to list features: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)
