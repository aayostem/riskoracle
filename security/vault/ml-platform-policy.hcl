path "secret/data/ml-platform/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/ml-platform/*" {
  capabilities = ["list"]
}

path "database/creds/ml-platform-role" {
  capabilities = ["read"]
}
