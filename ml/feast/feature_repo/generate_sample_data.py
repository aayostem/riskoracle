import pandas as pd
import numpy as np
from datetime import datetime, timedelta

def generate_customer_stats(n_customers=1000):
    """Generate sample customer statistics"""
    np.random.seed(42)
    
    dates = pd.date_range(
        start=datetime.now() - timedelta(days=90),
        end=datetime.now(),
        freq='D'
    )
    
    data = []
    for customer_id in range(n_customers):
        for date in dates[-30:]:  # Last 30 days
            data.append({
                'customer_id': f'customer_{customer_id}',
                'event_timestamp': date + timedelta(hours=np.random.randint(0, 24)),
                'created_timestamp': date,
                'avg_transaction_amount': np.random.exponential(500),
                'total_transactions': np.random.poisson(50),
                'transaction_frequency_7d': np.random.uniform(0, 10),
                'transaction_frequency_30d': np.random.uniform(0, 50),
                'avg_transaction_amount_7d': np.random.exponential(450),
                'max_transaction_amount': np.random.exponential(2000),
                'min_transaction_amount': np.random.exponential(100),
                'std_transaction_amount': np.random.exponential(200),
                'total_fraud_transactions': np.random.binomial(50, 0.01),
                'fraud_rate': np.random.beta(1, 99)
            })
    
    df = pd.DataFrame(data)
    df.to_parquet('data/customer_stats.parquet', index=False)
    print(f"Generated customer stats: {len(df)} rows")

def generate_transaction_stats(n_transactions=10000):
    """Generate sample transaction statistics"""
    np.random.seed(42)
    
    dates = pd.date_range(
        start=datetime.now() - timedelta(days=30),
        end=datetime.now(),
        freq='H'
    )
    
    data = []
    transaction_id = 0
    for date in dates:
        n_daily = np.random.poisson(20)
        for _ in range(n_daily):
            data.append({
                'transaction_id': f'transaction_{transaction_id}',
                'event_timestamp': date + timedelta(minutes=np.random.randint(0, 60)),
                'created_timestamp': date,
                'amount': np.random.exponential(1000),
                'time_of_day': np.random.randint(0, 24),
                'day_of_week': np.random.randint(0, 7),
                'is_weekend': 1 if np.random.randint(0, 7) in [5, 6] else 0,
                'is_holiday': np.random.binomial(1, 0.05),
                'merchant_category': np.random.randint(0, 20),
                'device_type': np.random.randint(0, 5),
                'ip_country': np.random.randint(0, 50),
                'billing_country': np.random.randint(0, 50),
                'shipping_country': np.random.randint(0, 50)
            })
            transaction_id += 1
    
    df = pd.DataFrame(data)
    df.to_parquet('data/transaction_stats.parquet', index=False)
    print(f"Generated transaction stats: {len(df)} rows")

if __name__ == "__main__":
    # Create data directory
    import os
    os.makedirs('data', exist_ok=True)
    
    # Generate sample data
    generate_customer_stats(1000)
    generate_transaction_stats(10000)
    print("Sample data generation complete!")
