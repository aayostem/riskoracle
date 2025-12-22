# 1. Isolate affected systems
./scripts/isolate-compromised.sh --pod=$COMPROMISED_POD

# 2. Rotate all credentials
./scripts/rotate-credentials.sh --all

# 3. Restore from clean backup
./scripts/restore-from-clean-backup.sh --date=$CLEAN_DATE

# 4. Conduct security audit
./scripts/security-audit.sh --full