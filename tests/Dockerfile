# The Vault image gives the tests the same vault CLI the setup script uses.
FROM hashicorp/vault:1.21.4
RUN apk add --no-cache curl jq
WORKDIR /tests
COPY *.sh ./
ENTRYPOINT ["sh", "/tests/run.sh"]
