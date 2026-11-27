#!/bin/sh
# The tools are reachable from the test container over xbank_network.

expect_eq "keycloak realm xbankDev is served" 200 "$(http_status "$KEYCLOAK_URL/realms/xbankDev")"
expect_eq "keycloak realm xbank is served" 200 "$(http_status "$KEYCLOAK_URL/realms/xbank")"
expect_eq "vault is initialized and unsealed" 200 "$(http_status "$VAULT_ADDR/v1/sys/health")"
