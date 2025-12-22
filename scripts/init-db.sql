-- Initialize ML Platform Database
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create MLflow tables (MLflow will create these automatically on first run)
-- Create additional tables for our platform

CREATE TABLE IF NOT EXISTS platform_models (
    model_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    version VARCHAR(50) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'development',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    metadata JSONB,
    UNIQUE(name, version)
);

CREATE TABLE IF NOT EXISTS model_deployments (
    deployment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id UUID REFERENCES platform_models(model_id),
    environment VARCHAR(50) NOT NULL,
    endpoint_url VARCHAR(500),
    status VARCHAR(50) DEFAULT 'active',
    deployed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deployed_by VARCHAR(255),
    metrics JSONB,
    config JSONB
);

CREATE TABLE IF NOT EXISTS data_sources (
    source_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    type VARCHAR(50) NOT NULL,
    connection_config JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS feature_sets (
    feature_set_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    schema JSONB,
    source_id UUID REFERENCES data_sources(source_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100),
    entity_id VARCHAR(255),
    user_id VARCHAR(255),
    user_ip INET,
    details JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_platform_models_status ON platform_models(status);
CREATE INDEX idx_model_deployments_env_status ON model_deployments(environment, status);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX idx_audit_logs_event_type ON audit_logs(event_type);

-- Create functions
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_platform_models_updated_at 
    BEFORE UPDATE ON platform_models 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_data_sources_updated_at 
    BEFORE UPDATE ON data_sources 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_feature_sets_updated_at 
    BEFORE UPDATE ON feature_sets 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create sample data
INSERT INTO platform_models (name, version, description, status, created_by) 
VALUES 
    ('fraud-detection', '1.0.0', 'Fraud detection model using XGBoost', 'production', 'system'),
    ('customer-churn', '2.1.0', 'Customer churn prediction model', 'staging', 'system'),
    ('recommendation', '1.2.0', 'Product recommendation engine', 'development', 'system')
ON CONFLICT DO NOTHING;