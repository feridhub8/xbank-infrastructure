#!/bin/sh
# specs/secrets-store: AppRole per service and environment, userpass for people,
# repeatable setup, and (once the root token is revoked) no root token left.

vault_api() {
  curl -s -H "X-Vault-Token: $VAULT_ADMIN_TOKEN" "$@"
}

ADMIN_LOGIN=$(curl -s -w '\n%{http_code}' "$VAULT_ADDR/v1/auth/userpass/login/admin" \
  -d "{\"password\":\"$VAULT_ADMIN_PASSWORD\"}")
expect_eq "admin signs in with userpass" 200 "$(echo "$ADMIN_LOGIN" | tail -n1)"
VAULT_ADMIN_TOKEN=$(echo "$ADMIN_LOGIN" | head -n1 | jq -r .auth.client_token)
on_exit "curl -s -o /dev/null -X POST -H 'X-Vault-Token: $VAULT_ADMIN_TOKEN' $VAULT_ADDR/v1/auth/token/revoke-self"

# --- admin can manage Vault
expect_eq "admin lists policies" 200 \
  "$(http_status -H "X-Vault-Token: $VAULT_ADMIN_TOKEN" -X LIST "$VAULT_ADDR/v1/sys/policies/acl")"
expect_eq "admin writes a secret" 200 \
  "$(http_status -H "X-Vault-Token: $VAULT_ADMIN_TOKEN" "$VAULT_ADDR/v1/secret/data/xbank-tests/check" -d '{"data":{"check":"ok"}}')"
on_exit "vault_api -X DELETE $VAULT_ADDR/v1/secret/metadata/xbank-tests/check >/dev/null"

# --- AppRole ms-auth-local reads only its own path
ROLE_ID=$(vault_api "$VAULT_ADDR/v1/auth/approle/role/ms-auth-local/role-id" | jq -r .data.role_id)
SECRET=$(vault_api -X POST "$VAULT_ADDR/v1/auth/approle/role/ms-auth-local/secret-id")
SECRET_ID=$(echo "$SECRET" | jq -r .data.secret_id)
SECRET_ACCESSOR=$(echo "$SECRET" | jq -r .data.secret_id_accessor)
on_exit "vault_api $VAULT_ADDR/v1/auth/approle/role/ms-auth-local/secret-id-accessor/destroy -d '{\"secret_id_accessor\":\"$SECRET_ACCESSOR\"}' >/dev/null"

APPROLE_TOKEN=$(curl -s "$VAULT_ADDR/v1/auth/approle/login" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" | jq -r .auth.client_token)
on_exit "curl -s -o /dev/null -X POST -H 'X-Vault-Token: $APPROLE_TOKEN' $VAULT_ADDR/v1/auth/token/revoke-self"

expect_ne "ms-auth-local is not denied its own path" 403 \
  "$(http_status -H "X-Vault-Token: $APPROLE_TOKEN" "$VAULT_ADDR/v1/secret/data/xbank/local/ms-auth")"
expect_eq "ms-auth-local is denied the prod path" 403 \
  "$(http_status -H "X-Vault-Token: $APPROLE_TOKEN" "$VAULT_ADDR/v1/secret/data/xbank/prod/ms-auth")"

# --- the setup can run again and keeps role IDs
RERUN_EXIT=0
VAULT_TOKEN="$VAULT_ADMIN_TOKEN" sh /vault/setup/init-auth.sh >/dev/null 2>&1 || RERUN_EXIT=$?
expect_eq "setup runs again without errors" 0 "$RERUN_EXIT"
expect_eq "setup rerun keeps the ms-auth-local role ID" "$ROLE_ID" \
  "$(vault_api "$VAULT_ADDR/v1/auth/approle/role/ms-auth-local/role-id" | jq -r .data.role_id)"

# --- no token with the root policy stays valid
ROOT_TOKENS=0
for accessor in $(vault_api -X LIST "$VAULT_ADDR/v1/auth/token/accessors" | jq -r '.data.keys[]'); do
  if vault_api "$VAULT_ADDR/v1/auth/token/lookup-accessor" -d "{\"accessor\":\"$accessor\"}" \
      | jq -e '.data.policies | index("root")' >/dev/null; then
    ROOT_TOKENS=$((ROOT_TOKENS + 1))
  fi
done
expect_eq "no root token is left" 0 "$ROOT_TOKENS"
