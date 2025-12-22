from feast import FileSource
from datetime import datetime

# Define data sources
customer_stats_source = FileSource(
    name="customer_stats",
    path="data/customer_stats.parquet",
    timestamp_field="event_timestamp",
    created_timestamp_column="created_timestamp"
)

transaction_stats_source = FileSource(
    name="transaction_stats",
    path="data/transaction_stats.parquet",
    timestamp_field="event_timestamp",
    created_timestamp_column="created_timestamp"
)

merchant_stats_source = FileSource(
    name="merchant_stats",
    path="data/merchant_stats.parquet",
    timestamp_field="event_timestamp",
    created_timestamp_column="created_timestamp"
)
