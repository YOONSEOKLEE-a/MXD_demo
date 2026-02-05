#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# [MXD Vault Initializer - UPDATED v3]
#
# Goal (based on real debugging results):
# 1) Ensure Issuer vault has key-1 (self-heal).
# 2) Copy issuer key-1 to Alice/Bob vaults (secret/key-1).
# 3) Inject STS client secrets using SIMPLE aliases (NO colons, NO did:web:... paths),
#    because complex paths caused "[Hashicorp Vault] Secret not found".
# 4) Inject common API key ("password") also as a simple alias.
#
# Notes:
# - We intentionally DO NOT inject colon/%3A/%253A variants anymore.
# - We store ONLY "content" field to avoid mismatched parsing.
# -------------------------------------------------------

NS=mxd
SECRET_VAL='password'

# --- 0. Find vault pods ---
echo ">>> 🔍 Finding Vault pods in namespace: $NS"
ALICE_VAULT_POD=$(kubectl get pod -n "$NS" | awk '/alice-vault/{print $1; exit}' || true)
BOB_VAULT_POD=$(kubectl get pod -n "$NS" | awk '/bob-vault/{print $1; exit}' || true)
ISSUER_VAULT_POD=$(kubectl get pod -n "$NS" | awk '/dataspace-issuer-vault/{print $1; exit}' || true)

if [[ -z "${ALICE_VAULT_POD:-}" || -z "${BOB_VAULT_POD:-}" || -z "${ISSUER_VAULT_POD:-}" ]]; then
  echo "❌ Error: Cannot find one or more vault pods."
  echo "   ALICE_VAULT_POD=${ALICE_VAULT_POD:-<empty>}"
  echo "   BOB_VAULT_POD=${BOB_VAULT_POD:-<empty>}"
  echo "   ISSUER_VAULT_POD=${ISSUER_VAULT_POD:-<empty>}"
  exit 1
fi

echo "✅ Alice Vault:  $ALICE_VAULT_POD"
echo "✅ Bob Vault:    $BOB_VAULT_POD"
echo "✅ Issuer Vault: $ISSUER_VAULT_POD"

vault_exec() {
  local pod="$1"
  shift
  kubectl exec -n "$NS" "$pod" -- sh -lc "
    set -e
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=root
    $*
  "
}

vault_put_content() {
  local pod="$1"
  local key="$2"
  local content="$3"

  # Write via base64 to avoid quoting issues
  local b64
  b64=$(printf '%s' "$content" | base64 -w0)

  vault_exec "$pod" "
    echo '$b64' | base64 -d > /tmp/v
    vault kv put secret/$key content=\"\$(cat /tmp/v)\" > /dev/null
  "
}

# --- 1. Self-heal issuer key-1 if missing ---
echo "------------------------------------------------"
echo ">>> 🛠️ Checking issuer key-1 (self-heal if missing)..."

# Original issuer key (assets/issuer.key.json content)
ISSUER_KEY_CONTENT='{"kty":"OKP","d":"G7sL7PM49U8nCucXJMN-S62l7xHX8Bi6biWoNvGD5XE","crv":"Ed25519","kid":"did:web:dataspace-issuer#key-1","x":"N6z9LC9L_5D_W2nKaUUHMYklUDQVlF37AFKSifNtV2c"}'

if vault_exec "$ISSUER_VAULT_POD" "vault kv get secret/key-1 >/dev/null 2>&1"; then
  echo "  -> OK: issuer secret/key-1 exists."
else
  echo "  -> WARNING: issuer secret/key-1 missing. Injecting default issuer key-1..."
  vault_put_content "$ISSUER_VAULT_POD" "key-1" "$ISSUER_KEY_CONTENT"
  echo "  -> REPAIRED: issuer secret/key-1 injected."
fi

# --- 2. Extract key-1 content from issuer vault and propagate ---
echo "------------------------------------------------"
echo ">>> 🔑 Extracting issuer key-1 and propagating to Alice/Bob vaults..."

KEY1_JWK=$(vault_exec "$ISSUER_VAULT_POD" "vault kv get -field=content secret/key-1 | tr -d '\r\n'" 2>/dev/null || true)
if [[ -z "${KEY1_JWK:-}" ]]; then
  echo "❌ Error: Failed to extract issuer key-1 content."
  exit 1
fi

vault_put_content "$ALICE_VAULT_POD" "key-1" "$KEY1_JWK"
vault_put_content "$BOB_VAULT_POD"   "key-1" "$KEY1_JWK"
echo "✅ key-1 propagated to Alice/Bob."

# --- 3. Inject SIMPLE STS client secrets + API key ---
echo "------------------------------------------------"
echo ">>> 💉 Injecting SIMPLE STS client secrets (no colons) + API key..."

# Simple aliases (the ones that actually worked in debugging)
ALICE_STS_ALIAS="alice-sts-client-secret"
BOB_STS_ALIAS="bob-sts-client-secret"
BOB_STS_DID_ALIAS="did%3Aweb%3Abob-ih%253A7083%3Abob-sts-client-secret"

# Simple API key aliases
APIKEY_ALIAS_1="password"
APIKEY_ALIAS_2="api-key"

inject_simple_secrets() {
  local pod="$1"

  echo "  -> Target pod: $pod"
  vault_put_content "$pod" "$APIKEY_ALIAS_1" "$SECRET_VAL"
  vault_put_content "$pod" "$APIKEY_ALIAS_2" "$SECRET_VAL"

  # Put both aliases into both vaults so any side can validate if needed
  vault_put_content "$pod" "$ALICE_STS_ALIAS" "$SECRET_VAL"
  vault_put_content "$pod" "$BOB_STS_ALIAS"   "$SECRET_VAL"
  vault_put_content "$pod" "$BOB_STS_DID_ALIAS" "$SECRET_VAL"

  echo "     ✅ injected: secret/$APIKEY_ALIAS_1, secret/$APIKEY_ALIAS_2, secret/$ALICE_STS_ALIAS, secret/$BOB_STS_ALIAS, secret/$BOB_STS_DID_ALIAS"
}

inject_simple_secrets "$ALICE_VAULT_POD"
inject_simple_secrets "$BOB_VAULT_POD"

echo "------------------------------------------------"
echo ">>> ✅ [DONE] Vaults prepared with key-1 + simple STS secrets."
echo
echo "Next (NOT done by this script):"
echo "1) Ensure IH STS client table (edc_sts_client) uses secret_alias = bob-sts-client-secret / alice-sts-client-secret"
echo "2) Ensure controlplane uses EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS=bob-sts-client-secret"
echo "3) Fix CredentialService auth header/key (x-api-key/password) and correct PresentationQuery payload."
