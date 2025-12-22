from feast import FeatureView, Field
from feast.types import Float32, Int64
from datetime import timedelta
from entities import customer, transaction, merchant
from data_sources import customer_stats_source, transaction_stats_source, merchant_stats_source

# Customer features
customer_stats_view = FeatureView(
    name="customer_stats",
    entities=[customer],
    ttl=timedelta(days=90),
    schema=[
        Field(name="avg_transaction_amount", dtype=Float32),
        Field(name="total_transactions", dtype=Int64),
        Field(name="transaction_frequency_7d", dtype=Float32),
        Field(name="transaction_frequency_30d", dtype=Float32),
        Field(name="avg_transaction_amount_7d", dtype=Float32),
        Field(name="max_transaction_amount", dtype=Float32),
        Field(name="min_transaction_amount", dtype=Float32),
        Field(name="std_transaction_amount", dtype=Float32),
        Field(name="total_fraud_transactions", dtype=Int64),
        Field(name="fraud_rate", dtype=Float32),
    ],
    source=customer_stats_source,
    online=True
)

# Transaction features
transaction_stats_view = FeatureView(
    name="transaction_stats",
    entities=[transaction],
    ttl=timedelta(days=30),
    schema=[
        Field(name="amount", dtype=Float32),
        Field(name="time_of_day", dtype=Int64),
        Field(name="day_of_week", dtype=Int64),
        Field(name="is_weekend", dtype=Int64),
        Field(name="is_holiday", dtype=Int64),
        Field(name="merchant_category", dtype=Int64),
        Field(name="device_type", dtype=Int64),
        Field(name="ip_country", dtype=Int64),
        Field(name="billing_country", dtype=Int64),
        Field(name="shipping_country", dtype=Int64),
    ],
    source=transaction_stats_source,
    online=True
)

# Merchant features
merchant_stats_view = FeatureView(
    name="merchant_stats",
    entities=[merchant],
    ttl=timedelta(days=90),
    schema=[
        Field(name="merchant_fraud_rate", dtype=Float32),
        Field(name="total_transactions", dtype=Int64),
        Field(name="avg_transaction_amount", dtype=Float32),
        Field(name="customer_count", dtype=Int64),
        Field(name="chargeback_rate", dtype=Float32),
        Field(name="merchant_age_days", dtype=Int64),
        Field(name="category_risk_score", dtype=Float32),
    ],
    source=merchant_stats_source,
    online=True
)
