#!/bin/sh
# Runs inside the Vault container. Sets up how services and people sign in to Vault.
# Needs VAULT_TOKEN (a root or admin token) and VAULT_ADMIN_PASSWORD (from vault/.env).
# Safe to run more than once: existing roles keep their role IDs.
set -eu

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
export VAULT_ADDR
: "${VAULT_ADMIN_PASSWORD:?VAULT_ADMIN_PASSWORD is required (vault/.env)}"

# Add a service here and rerun the script to give it an AppRole per environment.
SERVICES="ms-auth"
ENVIRONMENTS="local dev prod"

enable_auth() {
  vault auth list -format=json | grep -q "\"$1/\"" || vault auth enable "$1"
}

enable_auth approle
enable_auth userpass
vault secrets list -format=json | grep -q '"secret/"' || vault secrets enable -path=secret kv-v2

for service in $SERVICES; do
  for env in $ENVIRONMENTS; do
    name="$service-$env"
    printf 'path "secret/data/xbank/%s/%s" {\n  capabilities = ["read"]\n}\n' "$env" "$service" \
      | vault policy write "$name" - >/dev/null
    vault write "auth/approle/role/$name" \
      token_policies="$name" token_ttl=1h token_max_ttl=24h secret_id_ttl=0 >/dev/null
    echo "approle $name: reads secret/xbank/$env/$service"
  done
done

printf 'path "*" {\n  capabilities = ["create", "read", "update", "delete", "list", "sudo"]\n}\n' \
  | vault policy write admin - >/dev/null
vault write auth/userpass/users/admin password="$VAULT_ADMIN_PASSWORD" token_policies=admin >/dev/null
echo "userpass user admin: policy admin"
