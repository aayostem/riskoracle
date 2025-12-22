from datetime import datetime
from feast import FeatureStore

# Initialize feature store
store = FeatureStore(repo_path=".")

# Materialize features from 30 days ago to now
start_date = datetime.now() - timedelta(days=30)
end_date = datetime.now()

store.materialize(
    start_date=start_date,
    end_date=end_date
)

print("Feature materialization complete!")
