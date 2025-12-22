from feast import Entity

# Define entities
customer = Entity(
    name="customer",
    description="Customer entity",
    join_keys=["customer_id"]
)

transaction = Entity(
    name="transaction",
    description="Transaction entity",
    join_keys=["transaction_id"]
)

merchant = Entity(
    name="merchant",
    description="Merchant entity",
    join_keys=["merchant_id"]
)
