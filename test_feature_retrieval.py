from datetime import datetime
import pandas as pd
from feast import FeatureStore

store = FeatureStore(repo_path=".")

# Create entity dataframe
entity_df = pd.DataFrame.from_dict({
    "customer_id": ["customer_1", "customer_2", "customer_3"],
    "event_timestamp": [datetime.now()] * 3,
})

# Retrieve features
training_df = store.get_historical_features(
    entity_df=entity_df,
    features=[
        "customer_stats:avg_transaction_amount",
        "customer_stats:transaction_frequency_7d",
        "customer_stats:fraud_rate"
    ]
).to_df()

print("Feature retrieval test:")
print(training_df.head())
