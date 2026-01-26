#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# [EDC Tutorial Vault Initializer - FINAL FIX v2]
# 1. Issuer Vault가 비어있으면 원본 키를 자동 복구합니다.
# 2. Issuer의 key-1을 Alice/Bob에게 복사합니다.
# 3. STS Client Secret을 3가지 버전(Colon/Encoded)으로 주입합니다.
# 4. API Key(password)를 주입합니다.
# -------------------------------------------------------

NS=mxd
SECRET_VAL='password'

# --- 0. Pod 찾기 ---
echo ">>> 🔍 Vault Pod 찾는 중..."
ALICE_VAULT_POD=$(kubectl get pod -n $NS | grep -i alice-vault | awk '{print $1}' | head -n 1 || true)
BOB_VAULT_POD=$(kubectl get pod -n $NS | grep -i bob-vault   | awk '{print $1}' | head -n 1 || true)
ISSUER_VAULT_POD=$(kubectl get pod -n $NS | grep -i dataspace-issuer-vault | awk '{print $1}' | head -n 1 || true)

if [ -z "${ALICE_VAULT_POD:-}" ] || [ -z "${BOB_VAULT_POD:-}" ] || [ -z "${ISSUER_VAULT_POD:-}" ]; then
  echo "❌ Error: Vault Pod를 찾을 수 없습니다. (Alice, Bob, Issuer Vault 확인 필요)"
  exit 1
fi

echo "✅ Alice Vault:  $ALICE_VAULT_POD"
echo "✅ Bob Vault:    $BOB_VAULT_POD"
echo "✅ Issuer Vault: $ISSUER_VAULT_POD"

# --- 1. Issuer Vault 복구 (Self-Healing) ---
echo "------------------------------------------------"
echo ">>> 🛠️ Issuer Vault 상태 점검 및 복구..."

# 원본 키 (assets/issuer.key.json 내용)
ISSUER_KEY_CONTENT='{"kty":"OKP","d":"G7sL7PM49U8nCucXJMN-S62l7xHX8Bi6biWoNvGD5XE","crv":"Ed25519","kid":"did:web:dataspace-issuer#key-1","x":"N6z9LC9L_5D_W2nKaUUHMYklUDQVlF37AFKSifNtV2c"}'

kubectl exec -n $NS "$ISSUER_VAULT_POD" -- sh -lc "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=root
  
  if vault kv get secret/key-1 > /dev/null 2>&1; then
    echo '  -> OK: Issuer Key already exists.'
  else
    echo '  -> WARNING: Issuer Key missing! Injecting default key...'
    vault kv put secret/key-1 content='$ISSUER_KEY_CONTENT'
    echo '  -> REPAIRED.'
  fi
"

# --- 2. key-1 추출 및 전파 ---
echo "------------------------------------------------"
echo ">>> 🔑 key-1(JWK) 추출 및 전파 중..."

KEY1_JSON=$(kubectl exec -n $NS "$ISSUER_VAULT_POD" -- sh -lc "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=root
  vault kv get -format=json secret/key-1
" 2>/dev/null || true)

# JSON 파싱 (Python 사용)
KEY1_JWK=$(printf '%s' "$KEY1_JSON" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['data']['data']['content']) if 'content' in data['data']['data'] else print('')" 2>/dev/null || true)

if [ -z "${KEY1_JWK:-}" ]; then
  echo "❌ Error: Issuer Vault에서 key-1을 추출하지 못했습니다."
  exit 1
fi

# Base64 인코딩 (전송 안전성 확보)
KEY1_B64=$(printf '%s' "$KEY1_JWK" | base64 -w0)

put_key1 () {
  local pod="$1"
  echo "  -> Injecting key-1 to $pod..."
  kubectl exec -n $NS "$pod" -- sh -lc "
    set -e
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=root
    
    # Base64 디코딩 후 파일 저장 -> Vault 입력
    echo '$KEY1_B64' | base64 -d > /tmp/key1.jwk
    vault kv put secret/key-1 content=\"\$(cat /tmp/key1.jwk)\" > /dev/null
  "
}

put_key1 "$ALICE_VAULT_POD"
put_key1 "$BOB_VAULT_POD"
echo "✅ key-1 전파 완료"

# --- 3. STS Client Secret & API Key 주입 ---
# [중요] 1. 순수 콜론(:) 버전
ALICE_ALIAS_REAL='did:web:alice-ih:7083:alice-sts-client-secret'
BOB_ALIAS_REAL='did:web:bob-ih:7083:bob-sts-client-secret'

# 2. Human (%3A) 버전
ALICE_ALIAS_HUMAN='did:web:alice-ih%3A7083:alice-sts-client-secret'
BOB_ALIAS_HUMAN='did:web:bob-ih%3A7083:bob-sts-client-secret'

# 3. Encoded (%253A) 버전
ALICE_ALIAS_ENC='did%3Aweb%3Aalice-ih%253A7083%3Aalice-sts-client-secret'
BOB_ALIAS_ENC='did%3Aweb%3Abob-ih%253A7083%3Abob-sts-client-secret'

inject_secrets () {
  local pod="$1"
  local my_real="$2"
  local my_human="$3"
  local my_enc="$4"
  local other_real="$5"
  local other_human="$6"
  local other_enc="$7"

  echo "------------------------------------------------"
  echo ">>> 💉 Secrets Injection Target: $pod"
  
  kubectl exec -n $NS "$pod" -- sh -lc "
    set -e
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=root

    put() {
      local k=\"\$1\"
      vault kv put \"secret/\${k}\" content='${SECRET_VAL}' value='${SECRET_VAL}' secret='${SECRET_VAL}' > /dev/null
    }

    echo '  1. API Key (password) 주입...'
    put 'password'
    put 'api-key'

    echo '  2. STS Client Secrets (3 Versions)...'
    put \"${my_real}\"
    put \"${my_human}\"
    put \"${my_enc}\"
    put \"${other_real}\"
    put \"${other_human}\"
    put \"${other_enc}\"
    
    echo '  ✅ All secrets injected.'
  "
}

inject_secrets "$ALICE_VAULT_POD" \
  "$ALICE_ALIAS_REAL" "$ALICE_ALIAS_HUMAN" "$ALICE_ALIAS_ENC" \
  "$BOB_ALIAS_REAL"   "$BOB_ALIAS_HUMAN"   "$BOB_ALIAS_ENC"

inject_secrets "$BOB_VAULT_POD" \
  "$BOB_ALIAS_REAL"   "$BOB_ALIAS_HUMAN"   "$BOB_ALIAS_ENC" \
  "$ALICE_ALIAS_REAL" "$ALICE_ALIAS_HUMAN" "$ALICE_ALIAS_ENC"

echo "------------------------------------------------"
echo ">>> 🎉 [SUCCESS] 모든 Vault 설정이 완벽하게 복구되었습니다."
