#!/bin/sh
# specs/identity-realms "FIN is the username", checked in realm xbankDev.

KC_REALM=xbankDev
KC_ADMIN_TOKEN=$(curl -s -d grant_type=password -d client_id=admin-cli \
  --data-urlencode "username=$KC_BOOTSTRAP_ADMIN_USERNAME" \
  --data-urlencode "password=$KC_BOOTSTRAP_ADMIN_PASSWORD" \
  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -r .access_token)

kc_admin() {
  curl -s -H "Authorization: Bearer $KC_ADMIN_TOKEN" "$@"
}

# kc_create_user <username> <email>: prints the HTTP status
kc_create_user() {
  http_status -H "Authorization: Bearer $KC_ADMIN_TOKEN" -H 'Content-Type: application/json' \
    "$KEYCLOAK_URL/admin/realms/$KC_REALM/users" \
    -d "{\"username\":\"$1\",\"email\":\"$2\",\"firstName\":\"Test\",\"lastName\":\"User\",\"enabled\":true,
         \"credentials\":[{\"type\":\"password\",\"value\":\"Passw0rd\",\"temporary\":false}]}"
}

kc_delete_by_email() {
  for id in $(kc_admin "$KEYCLOAK_URL/admin/realms/$KC_REALM/users?email=$1&exact=true" | jq -r '.[].id'); do
    kc_admin -X DELETE "$KEYCLOAK_URL/admin/realms/$KC_REALM/users/$id" >/dev/null
  done
}

FIN=$(random_fin)
FIN_LOWER=$(echo "$FIN" | tr 'A-Z' 'a-z')
EMAIL_A="test-$FIN_LOWER-a@xbank.test"
EMAIL_B="test-$FIN_LOWER-b@xbank.test"
on_exit "kc_delete_by_email $EMAIL_A; kc_delete_by_email $EMAIL_B"

expect_eq "new user with a FIN as username is created" 201 "$(kc_create_user "$FIN" "$EMAIL_A")"

STORED_USERNAME=$(kc_admin "$KEYCLOAK_URL/admin/realms/$KC_REALM/users?email=$EMAIL_A&exact=true" | jq -r '.[0].username')
expect_eq "stored username is the FIN, not the email" "$FIN_LOWER" "$STORED_USERNAME"

expect_eq "second user with the same FIN is rejected" 409 "$(kc_create_user "$FIN" "$EMAIL_B")"

CLIENT_UUID=$(kc_admin "$KEYCLOAK_URL/admin/realms/$KC_REALM/clients?clientId=xbank-ms-auth" | jq -r '.[0].id')
CLIENT_SECRET=$(kc_admin "$KEYCLOAK_URL/admin/realms/$KC_REALM/clients/$CLIENT_UUID/client-secret" | jq -r .value)
LOGIN_HAS_TOKEN=$(curl -s -d grant_type=password -d client_id=xbank-ms-auth \
  --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "username=$EMAIL_A" -d password=Passw0rd \
  "$KEYCLOAK_URL/realms/$KC_REALM/protocol/openid-connect/token" | jq -r 'has("access_token")')
expect_eq "user logs in with email" true "$LOGIN_HAS_TOKEN"
