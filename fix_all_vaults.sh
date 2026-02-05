#!/bin/bash
set -e

NS=mxd

# Common key material (same as issuer key)
KEY_D="G7sL7PM49U8nCucXJMN-S62l7xHX8Bi6biWoNvGD5XE"
KEY_X="N6z9LC9L_5D_W2nKaUUHMYklUDQVlF37AFKSifNtV2c"

vault_put() {
  local pod=$1 key=$2 val=$3
  kubectl exec -n "$NS" "$pod" -- sh -c "
    export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root
    vault kv put secret/$key content='$val'
  " > /dev/null 2>&1
}

echo "=== Setting up Bob Vault ==="
BOB_KEY="{\"kty\":\"OKP\",\"d\":\"$KEY_D\",\"crv\":\"Ed25519\",\"kid\":\"did:web:bob-ih%3A7083:bob#key-1\",\"x\":\"$KEY_X\"}"
vault_put bob-vault-0 "bob-signing-key-1" "$BOB_KEY"
vault_put bob-vault-0 "key-1" "$BOB_KEY"
vault_put bob-vault-0 "bob-sts-client-secret" "password"
vault_put bob-vault-0 "password" "password"
vault_put bob-vault-0 "api-key" "password"
echo "Bob vault configured"

echo "=== Setting up Alice Vault ==="
ALICE_KEY="{\"kty\":\"OKP\",\"d\":\"$KEY_D\",\"crv\":\"Ed25519\",\"kid\":\"did:web:alice-ih%3A7083:alice#key-1\",\"x\":\"$KEY_X\"}"
vault_put alice-vault-0 "alice-signing-key-1" "$ALICE_KEY"
vault_put alice-vault-0 "key-1" "$ALICE_KEY"
vault_put alice-vault-0 "alice-sts-client-secret" "password"
vault_put alice-vault-0 "password" "password"
vault_put alice-vault-0 "api-key" "password"
echo "Alice vault configured"

echo "=== Setting up Issuer Vault ==="
ISSUER_KEY="{\"kty\":\"OKP\",\"d\":\"$KEY_D\",\"crv\":\"Ed25519\",\"kid\":\"did:web:dataspace-issuer#key-1\",\"x\":\"$KEY_X\"}"
vault_put dataspace-issuer-vault-0 "key-1" "$ISSUER_KEY"
vault_put dataspace-issuer-vault-0 "statuslist-signing-key" "$ISSUER_KEY"
vault_put dataspace-issuer-vault-0 "issuer-secret" "password"
vault_put dataspace-issuer-vault-0 "password" "password"
vault_put dataspace-issuer-vault-0 "api-key" "password"
echo "Issuer vault configured"

echo "=== Done ==="
