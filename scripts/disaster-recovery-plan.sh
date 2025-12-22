#!/bin/bash
# disaster-recovery-plan.md
cat > docs/runbooks/disaster-recovery.md << 'EOF'
# Disaster Recovery Plan - ML Platform

## Overview
This document outlines the disaster recovery procedures for the ML Platform in case of regional outages, data corruption, or security incidents.

## Recovery Objectives

### Recovery Time Objective (RTO)
- **Critical Services**: 2 hours
- **Non-critical Services**: 8 hours
- **Full Platform**: 24 hours

### Recovery Point Objective (RPO)
- **Transactional Data**: 15 minutes
- **ML Models & Features**: 1 hour
- **Metadata & Logs**: 4 hours

## Disaster Scenarios

### 1. Region Outage (AWS us-east-1)
**Impact**: Complete platform unavailability
**Recovery Procedure**:
```bash
# 1. Failover to secondary region (us-west-2)
./scripts/failover-to-west.sh

# 2. Update DNS records
aws route53 change-resource-record-sets \
    --hosted-zone-id ZONE_ID \
    --change-batch file://dns-failover.json

# 3. Notify stakeholders
./scripts/notify-outage.sh --region-failover --eta=2h