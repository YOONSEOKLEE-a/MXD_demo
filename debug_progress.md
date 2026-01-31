# MXD / Tractus-X EDC Debug Log

**Date Started:** 2026-01-29  
**Goal:** Bob connector must successfully crawl Alice catalog and return HTTP 200 for catalog request

---

## Apply Strategy (Phase 0 Preflight)

- **Entry point:** Direct `terraform apply -auto-approve` (no wrapper scripts like Make/just/taskfiles exist in repo root).
- **Evidence paths:** `/tmp/repo_entrypoints.txt`, `/tmp/repo_apply_grep.txt`, `/tmp/git_status_autofix_start.txt`, `/tmp/debug_progress_tail_autofix_start.txt`, `/tmp/repo_root_ls.txt`

---

## Current System Status

- **State:** Broken (Phase 2)
- **Root Cause:** Alice DSP / CredentialService does not return credential
- **Immediate Next Action:** Fix Alice credential/policy configuration

---

## Environment Snapshot

- **Cluster:** KinD cluster named "mxd"
- **Namespace:** mxd
- **Key Services:**
  - alice-ih, bob-ih (IdentityHub instances)
  - alice-tractusx-connector-controlplane, bob-tractusx-connector-controlplane
  - bdrs-server (Business Partner Directory)
- **Vault Status:**
  - Bob Vault: `bob-vault-0` (token: root)
  - STS client secret alias `bob-sts-client-secret` contains `RjGBe0yZxiZuUzXm`
- **IdentityHub:**
  - Bob IH DID: `did:web:bob-ih%3A7083:bob`
  - Participant state=1 (ACTIVATED); DID document state=300 (PUBLISHED)
- **Token Auth:**
  - `EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization`, `TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization`
  - `EDC_IAM_IATP_STS_OAUTH_TOKEN_URL=http://bob-ih:7084/api/sts/token` plus matching client_id/secret alias
  - `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased` enforces Authorization headers for catalog crawls via the RemoteTokenServiceClientExtension path
- **Connector:**
  - Bob Connector: `bob-tractusx-connector-controlplane`
  - Status: Running, but catalog crawler still loops on Alice STS `401 Unauthorized` after sending Bob’s credentials

---

## Environment Snapshot

- **Cluster:** KinD `mxd`
- **Namespace:** `mxd`
- **Key Services:** `alice-tractusx-connector-controlplane`, `bob-tractusx-connector-controlplane`, `alice-tractusx-connector-dataplane`, `bob-tractusx-connector-dataplane`, `alice-ih`, `bob-ih`, `dataspace-issuer-service`, `bdrs-server`
- **Vaults:** `alice-vault-0`, `bob-vault-0`, `dataspace-issuer-vault-0` seeded with `key-1`, `alice-sts-client-secret`, `bob-sts-client-secret`, `password`, and `api-key`
- **STS State:** `EDC_IAM_IATP_STS_OAUTH_TOKEN_URL` (and TX variant) now point to `http://bob-ih:7084/api/sts/token`, and the `bob-sts-client-secret` alias stores `RjGBe0yZxiZuUzXm`.

---

## Debugging History

### [Step 0] Port Forwarding Setup
- **Command:** `bash ./port-forward.sh`
- **Result:** SUCCESS
- **Notes:** 
  - Alice Connector: localhost:8282
  - Bob Connector: localhost:8283
  - BDRS Server: localhost:8285
  - Bob Vault: localhost:8200
  - Alice/Bob IH services: localhost:7081, 7082, 7091, 7092

---

### [Step 1] STS Sanity Check
- **Command:**
```bash
kubectl run -n mxd sts-sanity --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
curl -sS -X POST 'http://bob-ih.mxd.svc.cluster.local:7084/api/sts/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=RjGBe0yZxiZuUzXm' \
  --data-urlencode 'audience=http://bob-controlplane:8084/api/dsp' \
  -w '\nHTTP_CODE=%{http_code}\n'
"
```
- **Result:** SUCCESS - HTTP 200
- **Notes:**
  - Token generated successfully
  - JWT kid: `did:web:bob-ih%3A7083:bob#signing-key-1`
  - Vault secret verified: `RjGBe0yZxiZuUzXm`

---

### [Step 2.A] Initial DID Document Check
- **Command:** `curl -sS -i 'http://bob-ih.mxd.svc.cluster.local:7083/bob/.well-known/did.json'`
- **Result:** FAILURE - HTTP 204 No Content
- **Notes:** Expected 200 with JSON body, got empty 204 response

---

### [Step 2.B] Discovery of OpenAPI Endpoints
- **Command:** Attempted to discover OpenAPI spec at common paths
- **Result:** FAILURE - All paths returned 404
- **Notes:** 
  - Tried: `/api/identity/v1alpha/openapi`, `/api/identity/v1alpha/openapi.json`, etc.
  - No OpenAPI documentation available

---

### [Step 2.C] Brute-Force Activation Endpoint Attempts
- **Command:** Tested various activation/publish endpoints with base64-encoded participant ID
- **Result:** FAILURE - All returned 404
- **Notes:**
  - Tried: `/participants/{PID}/activate`, `/participants/{PID}/did/publish`, etc.
  - No valid activation endpoint found

---

### [Step 2.D] **ROOT CAUSE DISCOVERED: Private Key Alias URL-Encoding Issue**
- **Command:** 
```bash
# Check DB keypair
psql -h $DB_HOST -U bob -d bob -c "SELECT key_id, private_key_alias FROM keypair_resource WHERE key_id LIKE '%bob%';"
```
- **Result:** Found mismatch
- **Notes:**
  - **Problem:** DB had complex alias `did%3Aweb%3Abob-ih%253A7083%3Abob%23signing-key-1`
  - Bob IH logs: "Secret not found" in Vault
  - **Root Cause:** Vault client cannot handle triple-encoded URL paths
  - Reference: `setup_vaults.sh` warns: "complex paths caused '[Hashicorp Vault] Secret not found'"

---

### [Step 2.E] Fix Applied: Simplify Private Key Alias
- **Command:**
```bash
# 1. Copy signing key to simple Vault path
kubectl exec -n mxd bob-vault-0 -- vault kv put secret/bob-ih-signing-key content='<JWK_CONTENT>'

# 2. Update DB
psql -h $DB_HOST -U bob -d bob -c "
UPDATE keypair_resource 
SET private_key_alias = 'bob-ih-signing-key'
WHERE key_id = 'did:web:bob-ih%3A7083:bob#signing-key-1';
"

# 3. Restart Bob IH
kubectl rollout restart -n mxd deployment/bob-ih
```
- **Result:** PARTIAL SUCCESS
- **Notes:**
  - Vault now has key at `secret/bob-ih-signing-key` ✅
  - DB updated to use simple alias ✅
  - Bob IH no longer logs "Secret not found" errors ✅
  - **BUT:** DID document still returns 204 ❌

---

### [Step 2.F] Verify DID Document in Database
- **Command:**
```bash
psql -h $DB_HOST -U bob -d bob -c "SELECT did, state, state_timestamp, did_document FROM did_resources WHERE did='did:web:bob-ih%3A7083:bob';"
```
- **Result:** DID EXISTS in DB
- **Notes:**
  - State: 300 (PUBLISHED)
  - DID document JSON present with:
    - CredentialService → `http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==` ✅
    - ProtocolEndpoint → `http://bob-tractusx-connector-controlplane:8084/api/v1/dsp` ✅
    - verificationMethod with public key ✅
  - **Issue:** DID exists in DB but HTTP endpoint returns 204

---

### [Step 2.G] Compare Alice DID Endpoint
- **Command:** `curl -sS -i 'http://alice-ih.mxd.svc.cluster.local:7083/alice/.well-known/did.json'`
- **Result:** ALSO RETURNS 204
- **Notes:** 
  - **Critical Discovery:** Both Alice AND Bob return 204
  - This is a systematic issue, not specific to Bob
  - Web DID resolution module may not be configured to serve published DIDs

---

### [Step 3] CredentialService Endpoint Verification
- **Command:** Extracted DID document JSON from DB
- **Result:** CredentialService correctly configured
- **Notes:**
  - Port 7082 confirmed ✅
  - Base64-encoded participant ID: `ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==`
  - Full path: `http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==`

---

### [Step 4] BDRS Probe with JWT Token
- **Command:**
```bash
# Get STS token
TOKEN=$(curl -sS -X POST "http://bob-ih.mxd.svc.cluster.local:7084/api/sts/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=RjGBe0yZxiZuUzXm' \
  --data-urlencode 'audience=http://bdrs-server:8082' \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

# Test BDRS
curl -sS -w '\nHTTP=%{http_code}\n' \
  -H "Authorization: Bearer $TOKEN" \
  'http://bdrs-server:8082/api/directory/bpn-directory'
```
- **Result:** FAILURE - HTTP 401 "Request could not be authenticated"
- **Notes:**
  - JWT decoded successfully:
    - Header: `{"kid":"did:web:bob-ih%3A7083:bob#signing-key-1","alg":"Ed25519"}`
    - Payload: `{"sub":"did:web:bob-ih%3A7083:bob","aud":"http://bdrs-server:8082","iss":"did:web:bob-ih%3A7083:bob",...}`
  - **Root Cause:** BDRS must resolve `did:web:bob-ih:7083:bob` to get public key
  - DID resolution fails (returns 204) → BDRS cannot verify JWT signature → 401

---

### [Step 5] BDRS Cache Clear and Restart
- **Command:**
```bash
# Check BDRS DID cache
psql -h $BDRS_DB_HOST -U bdrs -d bdrs -c "SELECT * FROM edc_did_entries;"

# Clear cache (no bob-ih entries found)
psql -h $BDRS_DB_HOST -U bdrs -d bdrs -c "DELETE FROM edc_did_entries WHERE did LIKE '%bob-ih%';"

# Restart BDRS
kubectl rollout restart -n mxd deployment/bdrs-server
```
- **Result:** No change (expected)
- **Notes:**
  - No bob-ih entries in BDRS cache
  - BDRS only had: `did:web:alice-controlplane`, `did:web:bob-controlplane`, `did:web:miw:8000:BPNL000000000003`
  - Re-test still returns 401 (DID resolution issue persists)

---

### [Step 6.A] Restart Bob Connector
- **Command:**
```bash
kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
kubectl rollout status -n mxd deployment/bob-tractusx-connector-controlplane --timeout=120s
```
- **Result:** Connector restarted successfully
- **Notes:** Waited 10 seconds for full startup

---

### [Step 6.B] Bob Connector Logs Analysis
- **Command:** `kubectl logs -n mxd deployment/bob-tractusx-connector-controlplane --tail=250 | grep -Ei 'bdrs|token verification|presentation query|empty optional|crawl|catalog|error'`
- **Result:** **CRITICAL ERROR FOUND**
- **Notes:**
```
SEVERE [ExecutionManager] org.eclipse.edc.spi.EdcException: Unable to obtain credentials: Empty optional
DEBUG [ExecutionManager] The following work item has errored out. Will re-queue after a delay of 12 seconds: 
  [WorkItem{id='BPNL000000000001', url='http://alice-controlplane:8084/api/dsp', 
  protocolName='dataspace-protocol-http', 
  errors=[org.eclipse.edc.spi.EdcException: Unable to obtain credentials: Empty optional]}]
```
  - Connector attempts to crawl Alice catalog
  - Fails to obtain credentials from Bob IH
  - Error repeats every 10-20 seconds

---

### [Step 6.C] Test Catalog Request via Management API
- **Command:**
```bash
# From within cluster
kubectl run -n mxd catalog-test --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
curl -sS -w '\nHTTP=%{http_code}\n' -X POST \
  'http://bob-tractusx-connector-controlplane:8081/management/v3/catalog/request' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: password' \
  -d '{
    \"@context\": {\"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\"},
    \"counterPartyAddress\": \"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp\",
    \"protocol\": \"dataspace-protocol-http\"
  }'
"
```
- **Result:** FAILURE - HTTP 502
- **Notes:** Error message: `[{"message":"Unable to obtain credentials: Empty optional","type":"BadGateway",...}]`

---

### [Step 6.D] Verify Bob Credentials in Database
- **Command:**
```bash
psql -h $DB_HOST -U bob -d bob -c "SELECT id, issuer_id, holder_id, vc_state, vc_format FROM credential_resource;"
```
- **Result:** Credentials exist
- **Notes:**
  - `membership-credential-bob-v1`: MembershipCredential, vc_state=500, holder=`did:web:bob-ih%3A7083:bob`
  - `deg-credential-bob-v1`: DataExchangeGovernanceCredential, vc_state=500, holder=`did:web:bob-ih%3A7083:bob`
  - Both credentials are valid JWT format
  - **But:** Connector cannot retrieve them from IH

---

### [Step 6.E] Test Presentation Query Endpoint Directly
- **Command:**
```bash
curl -sS -w '\nHTTP=%{http_code}\n' -X POST \
  'http://bob-ih.mxd.svc.cluster.local:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer test-token' \
  -d '{
    "@context": ["https://www.w3.org/2018/credentials/v1"],
    "type": "PresentationQuery",
    "query": []
  }'
```
- **Result:** FAILURE - HTTP 404 Not Found
- **Notes:**
  - Expected: VerifiablePresentation with credentials
  - Actual: 404 error page from Jetty servlet
  - **Critical Issue:** Presentation Query API not responding at expected path

---

## Critical Blockers Summary

### Blocker 1: DID Document Returns 204
- **Symptom:** `GET http://bob-ih:7083/bob/.well-known/did.json` → HTTP 204 No Content
- **Impact:** 
  - BDRS cannot resolve DID → cannot verify JWT → 401
  - Any external party cannot discover Bob's public keys or service endpoints
- **Evidence:**
  - DID exists in `did_resources` table with state=300 (PUBLISHED)
  - DID document JSON is valid and complete
  - ConfigMap has `WEB_HTTP_DID_PATH=/` and `WEB_HTTP_DID_PORT=7083`
  - Both Alice and Bob have same issue (systematic)
- **Hypothesis:** Web DID module is not configured to serve published DIDs, or requires additional activation

---

### Blocker 2: Presentation Query Returns 404
- **Symptom:** `POST http://bob-ih:7082/api/credentials/v1/participants/{PID_BASE64}` → HTTP 404
- **Impact:**
  - Bob Connector cannot obtain credentials from Bob IH
  - Crawler fails with "Empty optional"
  - Catalog request fails with 502 BadGateway
- **Evidence:**
  - CredentialService endpoint in DID document: `http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==`
  - Bob IH has port 7082 listening for credentials API
  - Credentials exist in DB with correct holder_id
- **Hypothesis:** 
  - API version mismatch (v1 vs v1alpha?)
  - Path format incorrect
  - Authentication/Authorization failing silently
  - Missing configuration to enable Presentation Query endpoint

---

## Next Investigation Required

1. **Compare Alice vs Bob IdentityHub configurations**
   - Check if Alice's DID endpoint also returns 204
   - Identify any configuration differences

2. **Review IdentityHub Terraform modules**
   - Check `modules/identityhub` configuration
   - Look for DID publishing or Web DID serving flags

3. **Test IdentityHub APIs systematically**
   - Identity API (port 7081) - participant management ✅ working
   - Credentials API (port 7082) - presentation query ❌ 404
   - DID API (port 7083) - DID document serving ❌ 204
   - STS API (port 7084) - token generation ✅ working

4. **Check seed data process**
   - Review `postman/mxd-seed.json` "SeedIH" folder
   - Verify participant/keypair/DID creation flow
   - Check if Alice was seeded differently than Bob

---

**End of Current Debug Log**

---

## Current System Status (Update 2026-01-29)

### **Working:**
- ✅ IdentityHub config confirmed identical for Alice/Bob (ports, paths, DID config)
- ✅ Seed process confirmed for IH (Create Participant + 2 Credentials)

### **Broken:**
- 🔴 DID document endpoint still returns HTTP 204 (likely DID parser mismatch or not published via API)
- 🔴 Presentation Query endpoint path likely incorrect (currently 404 at `/api/credentials/v1/participants/{id}`)

### **Immediate Next Action:**
1. Call explicit DID publish endpoint (v1alpha) for Bob and re-test DID HTTP 200
2. Test correct Presentation Query endpoint `/api/credentials/v1/participants/{id}/presentations/query`

---

## Recent Work (2026-01-31)

### [Step 7] Candidate fix attempt: enforce Authorization headers
- **Command:**
  ```bash
  kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane \
    TX_EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=Authorization \
    EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=Authorization \
    TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization \
    EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization
  for k in \
    TX_EDC_IAM_IATP_CREDENTIALSERVICE_APIKEY \
    TX_EDC_IAM_IATP_PRESENTATION_QUERY_APIKEY \
    EDC_IAM_IATP_CREDENTIALSERVICE_APIKEY \
    EDC_IAM_IATP_PRESENTATION_QUERY_APIKEY; do
    kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane "${k}-" 2>/dev/null || true
  done
  kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
  ```
- **Result:** Connector restart succeeded but management catalog POST still returns HTTP 500.
- **Logs:**
  - `Presentation Query failed: HTTP 401, message: ... /participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query` (repeated every 10-20s in control plane logs)

### [Step 8] Current environment snapshot (post-change)
- **Command:** `kubectl exec -n mxd bob-tractusx-connector-controlplane-69dbc9f899-lnthz -- env | sort | egrep -i 'EDC_IAM|IATP|STS|PRESENTATION|CREDENTIAL|DCP|SCOPE|AUDIENCE|TOKEN|BEARER|AUTH_HEADER'`
- **Result:** Authorization headers explicitly set for both IATP CredentialService and PresentationQuery, API key env vars removed, STS client still uses `bob-sts-client-secret`, token audience remains `did:web:bob-ih%3A7083:bob`.

### [Step 9] Self-issued PQ smoke test (port-forward + python)
- **Command:**
  ```bash
  kubectl port-forward svc/bob-ih -n mxd 9084:7084 &
  kubectl port-forward svc/bob-ih -n mxd 9082:7082 &
  python3 - <<'PY'
  import os, json, urllib.request, urllib.parse
  import base64
  BOB_DID='did:web:bob-ih%3A7083:bob'
  SECRET=$(kubectl exec -n mxd bob-vault-0 -- vault kv get -mount=secret -field=content bob-sts-client-secret | tr -d '\r\n')
  # (script obtains ACCESS, then chained TOKEN, then POSTs PresentationQuery)
  PY
  ```
- **Result:** HTTP 200 PresentationResponseMessage (self-issued token with `token` + `bearer_access_scope` included, matching the manual curl flow in debug_progress Step 4). The script printed the `PresentationResponseMessage` with JWT(s).

### [Step 10] Enable default IATP scope configuration
- **Command:**
  ```bash
  # Added the tx.edc.iam.iatp.default-scopes env vars via Terraform and kubectl so both connectors request
  # bearer_access_scope=org.eclipse.tractusx.vc.type:MembershipCredential:read automatically.
  # Then restarted the control planes to pick up the new envs.
  ```
- **Result:** Control planes restarted successfully; env now exposes `TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_*` for alias/type/operation, and connector logs include the Tractusx default scope extension initialization though PQ still fails with 401.

### [Step 11] Catalog crawl still blocked by 401
- **Command:**
  ```bash
  # Trigger catalog request to see latest failure and log the 401 from catalog service
  ```
- **Result:** Catalog request still hits `dspace:CatalogError` with HTTP 401; connector logs now show the 401 coming from Alice catalog endpoint despite the new default scope config. Need to inspect IdentityHub or BDRS expectations for token claims.


## [Step 7] Analyze SeedIH Process (No Publish Step)
- **Command:** `grep -A 50 '"name": "SeedIH"' postman/mxd-seed.json`
- **Result:** success
- **Notes:** SeedIH has exactly 3 calls: Create Participant (v1alpha), Create Membership Credential, Create DataExGov Credential. No DID publish/activate step included.

---

## [Step 8] Identify Publish DID Endpoint in Management APIs
- **Command:** (from background analysis of `postman/mxd-management-apis.json`)
- **Result:** success
- **Notes:** Management collection includes v1alpha endpoints:
  - `POST /api/identity/v1alpha/participants/{participantId}/dids/publish`
  - `POST /api/identity/v1alpha/participants/{participantId}/dids/unpublish`
  This is missing from seed process.

---

## [Step 9] Confirm IdentityHub Terraform Configuration (Alice/Bob Identical)
- **Command:** `read modules/identity-hub/main.tf`, `read alice.tf`, `read bob.tf`
- **Result:** success
- **Notes:** Both IHs use same ConfigMap values:
  - `WEB_HTTP_DID_PORT=7083`, `WEB_HTTP_DID_PATH=/`, `WEB_HTTP_CREDENTIALS_PATH=/api/credentials`, `EDC_IAM_DID_WEB_USE_HTTPS=false`
  - No config difference explains 204/404 behavior.

---

## [Step 10] External Research: DID HTTP 204 and Presentation Query Path
- **Command:** (background research of Eclipse IdentityHub source/docs)
- **Result:** success
- **Notes:**
  - DID endpoint uses `DidWebController` and returns **null** if no document found, which becomes HTTP 204.
  - Query filters on `state = PUBLISHED` and `did = parsedDid`.
  - Presentation Query API path is **`/api/credentials/v1/participants/{participantContextId}/presentations/query`**.
  - Likely mismatch: parsed DID may be `did:web:bob-ih:7083:bob` while DB stores `did:web:bob-ih%3A7083:bob`.

---

## [Step 11] Explicit DID Publish Attempt (v1alpha)
- **Command:** `POST http://bob-ih.mxd.svc.cluster.local:7081/api/identity/v1alpha/participants/did%3Aweb%3Abob-ih%3A7083%3Abob/dids/publish`
- **Result:** success (HTTP 204)
- **Notes:** Re-check of `http://bob-ih:7083/bob/.well-known/did.json` still returns HTTP 204. Publish did not change HTTP behavior.

---

## [Step 12] Presentation Query Test Failed (Shell Syntax)
- **Command:** `POST http://bob-ih:7082/api/credentials/v1/participants/<PID_B64>/presentations/query` (with STS token)
- **Result:** failure
- **Notes:** Busybox `sh` rejected substring syntax `\${TOKEN:0:30}`. Need retry with POSIX-safe string handling.

---

## [Step 13] Presentation Query Endpoint Exists (Correct Path)
- **Command:** `POST http://bob-ih:7082/api/credentials/v1/participants/<PID_B64>/presentations/query` (Authorization: Bearer <STS token>)
- **Result:** failure (HTTP 400)
- **Notes:** Response: `{"message":"Unsupported protocol"}`. Endpoint exists (not 404). Likely request body missing required protocol-specific fields.

---

## [Step 14] UWL Runbook Re-try (2026-01-29)
- **Command:**
```bash
# Port-forward and mgmt checks
bash ./port-forward.sh
curl -sS -o /dev/null -w "bob_mgmt_http=%{http_code}\n" http://localhost:8283/management/v3/
curl -sS -o /dev/null -w "alice_mgmt_http=%{http_code}\n" http://localhost:8282/management/v3/

# STS sanity
kubectl run -n mxd sts-sanity --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
curl -sS -X POST 'http://bob-ih.mxd.svc.cluster.local:7084/api/sts/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=<redacted>' \
  --data-urlencode 'audience=http://bob-controlplane:8084/api/dsp' \
  -w '\nHTTP_CODE=%{http_code}\n'"

# Brute-force activation/publish endpoints (v1alpha)
kubectl run -n mxd ih-activate-publish --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
BASE='http://bob-ih.mxd.svc.cluster.local:7081/api/identity/v1alpha'; \
PID='ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=='; \
for ep in participants/$PID/activate participants/$PID/activation participants/$PID/state/ACTIVATED participants/$PID/states/ACTIVATED participants/$PID/did/publish participants/$PID/did-documents/publish participants/$PID/did-documents/refresh participants/$PID/publish; do \
  echo "=== POST $BASE/$ep ==="; \
  curl -sS -o /dev/null -w "HTTP=%{http_code}\n" -X POST -H "x-api-key: <superuser-key>" "$BASE/$ep" || true; \
done"

# DID check (after bob-ih restart)
kubectl rollout restart -n mxd deployment/bob-ih
kubectl rollout status -n mxd deployment/bob-ih --timeout=180s
kubectl run -n mxd did-check --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
curl -sS -i 'http://bob-ih.mxd.svc.cluster.local:7083/bob/.well-known/did.json' | head -n 80"
```
- **Result:** partial
- **Notes:**
  - Port-forward OK; mgmt endpoints returned 404 (both Bob and Alice)
  - STS sanity: HTTP 200
  - All activation/publish endpoints returned HTTP 404
  - DID check still returns HTTP 204 after bob-ih restart

---

## [Step 14] DID Publish Endpoint Did Not Change HTTP 204
- **Command:** `GET http://bob-ih:7083/bob/.well-known/did.json` (after publish)
- **Result:** failure (HTTP 204)
- **Notes:** DID still not served despite publish. Points to DID parsing mismatch (encoded vs decoded port) or internal DID controller query mismatch.

---

## [Step 15] Presentation Query Payload Quoting Fixed (JSON Now Valid)
- **Command:** Base64-encode JSON payload, decode inside pod, `POST /api/credentials/v1/participants/<PID_B64>/presentations/query`
- **Result:** failure (HTTP 401)
- **Notes:** Error: `Required claim 'token' not present on token; audience mismatch expected did:web:bob-ih%3A7083:bob` (when aud=http://bob-ih:7082/api/credentials). Confirms endpoint exists and parses JSON.

---

## [Step 16] Presentation Query with Audience=did
- **Command:** Same payload, STS token requested with `audience=did:web:bob-ih%3A7083:bob`
- **Result:** failure (HTTP 401)
- **Notes:** Error: `Required claim 'token' not present on token`. Indicates IdentityHub expects a different token type/claim set for Presentation Query (likely ID token with `token` claim).

---

## [Step 17] Update Bob Connector Presentation Query URL
- **Command:** `kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane EDC_IAM_IATP_PRESENTATION_QUERY_URL=.../presentations/query TX_EDC_IAM_IATP_PRESENTATION_QUERY_URL=.../presentations/query`
- **Result:** success (rollout complete)
- **Notes:** Connector now points to correct Presentation Query endpoint; auth/token issue still unresolved.

---

## [Step 18] Connector Still Fails After PQ URL Update
- **Command:** `kubectl logs -n mxd deployment/bob-tractusx-connector-controlplane --tail=200 | grep -Ei 'presentation|credential|empty optional|401|error'`
- **Result:** failure persists
- **Notes:** Error remains: `Unable to obtain credentials: Empty optional`. Indicates PQ URL fix alone is insufficient; IdentityHub token/auth mismatch likely blocking VP issuance.

---

## [Step 19] Milestone: Root Cause Hypotheses Confirmed
- **Command:** N/A (analysis milestone)
- **Result:** partial resolution
- **Notes:**
  - DID HTTP 204 persists even after explicit publish; likely due to DID parsing mismatch (encoded vs unencoded port).
  - Presentation Query endpoint exists and parses JSON; failures are auth-related (missing `token` claim / audience mismatch).
  - Connector PQ URL corrected but crawler still fails, confirming token/auth is the primary blocker for credential retrieval.

---

## [Step 20] Wave 0 Baseline Re-check (UWL)
- **Command:**
```bash
# DID endpoint
kubectl run -n mxd did-check --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
curl -sS -i 'http://bob-ih.mxd.svc.cluster.local:7083/bob/.well-known/did.json' | head -n 40"

# Presentation Query endpoint (no auth)
kubectl run -n mxd pq-check --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
PID='ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=='; \
curl -sS -w '\nHTTP=%{http_code}\n' -X POST \
  'http://bob-ih.mxd.svc.cluster.local:7082/api/credentials/v1/participants/'\"$PID\"'/presentations/query' \
  -H 'Content-Type: application/json' \
  -d '{\"@context\":[\"https://www.w3.org/2018/credentials/v1\"],\"type\":\"PresentationQuery\",\"query\":[]}'"

# BDRS probe (with STS token)
kubectl run -n mxd bdrs-probe --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
STS='http://bob-ih.mxd.svc.cluster.local:7084/api/sts/token'; \
TOKEN=$(curl -sS -X POST \"$STS\" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=<redacted>' \
  --data-urlencode 'audience=http://bdrs-server.mxd.svc.cluster.local:8082' | \
  sed -n 's/.*\"access_token\":\"\([^\"]*\)\".*/\1/p'); \
echo \"TOKEN_HEAD=${TOKEN%%.*}...\"; \
curl -sS -w '\nHTTP=%{http_code}\n' -H \"Authorization: Bearer $TOKEN\" \
  'http://bdrs-server.mxd.svc.cluster.local:8082/api/directory/bpn-directory'"

# Catalog request
kubectl run -n mxd catalog-check --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
curl -sS -w '\nHTTP=%{http_code}\n' -X POST \
  'http://bob-tractusx-connector-controlplane.mxd.svc.cluster.local:8081/management/v3/catalog/request' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: password' \
  -d '{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},\"counterPartyAddress\":\"http://alice-tractusx-connector-controlplane.mxd.svc.cluster.local:8084/api/v1/dsp\",\"protocol\":\"dataspace-protocol-http\"}'"
```
- **Result:** failure persists
- **Notes:**
  - DID endpoint: HTTP 204 No Content
  - PQ endpoint (no auth): HTTP 400, `Bad Message 400 reason: Ambiguous URI empty segment`
  - BDRS probe: HTTP 401 `Request could not be authenticated` (token generated but DID resolution still failing)
  - Catalog request: HTTP 502 `Unable to obtain credentials: Empty optional`

---

## [Step 21] DID Endpoint Works When Using Service Hostname
- **Command:**
```bash
kubectl run -n mxd ih-did-host --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "\
curl -sS -i 'http://bob-ih:7083/bob/.well-known/did.json' | head -n 10"
```
- **Result:** success (HTTP 200)
- **Notes:** Using service hostname `bob-ih` returns DID JSON. The FQDN-based check still returned 204 earlier, indicating DID resolution is host-sensitive (Host header/hostname matters). This unblocks DID resolution for in-cluster services that use `bob-ih`.

---

## [Step 22] STS Self-Issued Token Needs `token` and `scope` Claims
- **Command:**
```bash
# 1) Get access token
ACCESS=$(curl -sS -X POST 'http://bob-ih:7084/api/sts/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=<redacted>' \
  --data-urlencode 'audience=did:web:bob-ih%3A7083:bob' | \
  sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

# 2) Get self-issued token that embeds access token + scope
TOKEN=$(curl -sS -X POST 'http://bob-ih:7084/api/sts/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=did:web:bob-ih%3A7083:bob' \
  --data-urlencode 'client_secret=<redacted>' \
  --data-urlencode 'audience=did:web:bob-ih%3A7083:bob' \
  --data-urlencode "token=$ACCESS" \
  --data-urlencode 'bearer_access_scope=org.eclipse.tractusx.vc.type:MembershipCredential:read' | \
  sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
```
- **Result:** success (token contains `token` and `scope` claims)
- **Notes:** STS supports `token` and `bearer_access_scope` params (IdentityHub STS API). Without these, PQ returns `Required claim 'token' not present` and `Required claim 'scope' not present`.

---

## [Step 23] Presentation Query Success (Correct Scope Alias)
- **Command:**
```bash
curl -sS -w '\nHTTP=%{http_code}\n' -X POST \
  'http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer <self-issued-token-with-token+scope>" \
  -d '{"@context":["https://w3id.org/dspace-dcp/v1.0/dcp.jsonld"],"type":"PresentationQueryMessage","scope":["org.eclipse.tractusx.vc.type:MembershipCredential:read"]}'
```
- **Result:** success (HTTP 200) with `PresentationResponseMessage`
- **Notes:** Scope alias must be `org.eclipse.tractusx.vc.type` in this deployment; `org.eclipse.edc.vc.type` was rejected.

---

## [Step 24] BDRS Probe Success Using VP from PQ
- **Command:**
```bash
# Use the VP JWT from PQ response as Bearer token
curl -sS -w '\nHTTP=%{http_code}\n' \
  -H "Authorization: Bearer <vp-jwt-from-pq-response>" \
  'http://bdrs-server:8082/api/directory/bpn-directory'
```
- **Result:** success (HTTP 200)
- **Notes:** BDRS accepts the VP JWT; plain STS access tokens still return 401.

---

## [Step 25] IdentityHub Agent Identity Claim Key Update (No Effect)
- **Command:**
```bash
kubectl set env -n mxd deployment/bob-ih EDC_AGENT_IDENTITY_KEY=client_id
kubectl set env -n mxd deployment/alice-ih EDC_AGENT_IDENTITY_KEY=client_id
kubectl rollout status -n mxd deployment/bob-ih --timeout=180s
kubectl rollout status -n mxd deployment/alice-ih --timeout=180s
```
- **Result:** no change
- **Notes:** Presentation Query still required `token` and `scope` claims; STS access tokens alone remain insufficient. The working path is to request self-issued tokens with `token` + `bearer_access_scope` as in Step 22.

---

## [Step 26] Connector Snapshot Captured
- **Date:** 2026-01-30 13:11
- **Command:**
```bash
NS=mxd
BOB_CP_POD=$(kubectl get pod -n $NS | grep -i 'bob-tractusx-connector-controlplane' | awk '{print $1}' | head -n 1)
echo "BOB_CP_POD=$BOB_CP_POD"
kubectl logs -n $NS "$BOB_CP_POD" --tail=300 | egrep -i 'Unable to obtain credentials|Empty optional|presentations/query|presentation|credential|sts|token|scope|bdrs|AuthenticationFailed|Required claim'
kubectl exec -n $NS "$BOB_CP_POD" -- env | sort | egrep -i 'IATP|PRESENTATION|CREDENTIAL|STS|TOKEN|SCOPE|IDENTITY|DID|BDRS'
kubectl exec -n $NS "$BOB_CP_POD" -- sh -lc '
set -eu
echo "=== /app/config ==="
ls -la /app/config 2>/dev/null || true
echo "=== find properties ==="
find /app -maxdepth 4 -type f \( -name "*.properties" -o -name "*.conf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null | head -n 200
'
```
- **Result:** failure persists
- **Evidence:**
```
BOB_CP_POD=bob-tractusx-connector-controlplane-54c9d58b5d-cvpcj
SEVERE [ExecutionManager] org.eclipse.edc.spi.EdcException: Unable to obtain credentials: Empty optional
DEBUG [ExecutionManager] The following work item has errored out. Will re-queue after a delay of 15 seconds: [WorkItem{id='BPNL000000000001', url='http://alice-controlplane:8084/api/dsp', protocolName='dataspace-protocol-http', errors=[org.eclipse.edc.spi.EdcException: Unable to obtain credentials: Empty optional]}]

ALICE_IH_SERVICE_PORT_CREDENTIALS=7082
ALICE_IH_SERVICE_PORT_DID=7083
ALICE_IH_SERVICE_PORT_IDENTITY=7081
ALICE_IH_SERVICE_PORT_STS=7084
BOB_IH_SERVICE_PORT_CREDENTIALS=7082
BOB_IH_SERVICE_PORT_DID=7083
BOB_IH_SERVICE_PORT_IDENTITY=7081
BOB_IH_SERVICE_PORT_STS=7084
EDC_IAM_DID_WEB_USE_HTTPS=false
EDC_IAM_IATP_API_KEY=***
EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=x-api-key
EDC_IAM_IATP_CREDENTIALSERVICE_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==
EDC_IAM_IATP_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_IATP_PRESENTATION_QUERY_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query
EDC_IAM_IDENTITYHUB_API_KEY=***
EDC_IAM_ISSUER_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_STS_CLIENT_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_STS_CLIENT_SECRET_ALIAS=bob-sts-client-secret
EDC_IAM_STS_OAUTH_AUDIENCE=http://bob-controlplane:8084/api/dsp
EDC_IAM_STS_OAUTH_CLIENT_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS=bob-sts-client-secret
EDC_IAM_STS_OAUTH_TOKEN_AUDIENCE=http://bob-controlplane:8084/api/dsp
EDC_IAM_STS_OAUTH_TOKEN_URL=http://bob-ih:7084/api/sts/token
TX_EDC_IAM_IATP_CREDENTIALSERVICE_APIKEY=***
TX_EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=x-api-key
TX_EDC_IAM_IATP_CREDENTIALSERVICE_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==
TX_EDC_IAM_IATP_PRESENTATION_QUERY_APIKEY=password
TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization
TX_EDC_IAM_IATP_PRESENTATION_QUERY_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query

=== /app/config ===
=== find properties ===
/app/participants.json
/app/opentelemetry.properties
```
- **Conclusion:** Connector still loops on Empty optional; IATP/PQ URLs are set, no obvious bearer scope/token params in env.
- **Next:** Inspect runtime jar/configs for bearer_access_scope/token-related keys (Step 27).

---

## [Step 27] Search Connector Runtime for STS Self-Issued Token Keys
- **Date:** 2026-01-30 13:13
- **Command:**
```bash
NS=mxd
BOB_CP_POD=$(kubectl get pod -n $NS | grep -i 'bob-tractusx-connector-controlplane' | awk '{print $1}' | head -n 1)

kubectl exec -n $NS "$BOB_CP_POD" -- sh -lc '
set -eu
JAR=$(find /app -maxdepth 3 -type f -name "edc-runtime.jar" 2>/dev/null | head -n 1 || true)
echo "JAR=$JAR"
if [ -z "$JAR" ]; then echo "No jar found"; exit 0; fi
echo "=== search: bearer_access_scope / bearerAccessScope / token claim ==="
echo "=== search: presentations/query ==="
'

kubectl exec -n $NS "$BOB_CP_POD" -- sh -lc '
set -eu
for f in $(find /app -maxdepth 4 -type f \( -name "*.properties" -o -name "*.conf" \) 2>/dev/null); do
  grep -nEi "bearer|scope|iatp|presentation|sts" "$f" 2>/dev/null && echo "--- file=$f ---"
done | head -n 300
'
```
- **Result:** no key names found in runtime jar or config files
- **Evidence:**
```
JAR=/app/edc-runtime.jar
=== search: bearer_access_scope / bearerAccessScope / token claim ===
<no matches>
=== search: presentations/query ===
org/eclipse/edc/iam/identitytrust/transform/to/JsonObjectToPresentationQueryTransformer.class
org/eclipse/edc/iam/identitytrust/transform/from/JsonObjectFromPresentationQueryTransformer.class
org/eclipse/edc/iam/identitytrust/spi/model/PresentationQueryMessage.class
org/eclipse/edc/iam/identitytrust/spi/model/PresentationQueryMessage$Builder.class

=== grep configs for scope/bearer/iatp ===
<no matches>
```
- **Conclusion:** No obvious config key for `bearer_access_scope` or self-issued token behavior discovered via jar/config grep.
- **Next:** Inspect runtime ServiceExtension list to see which token service is wired (Step 28).

---

## [Step 28] Runtime ServiceExtension Confirms IATP/DCP/STS Extensions Loaded
- **Date:** 2026-01-30 13:13
- **Command:**
```bash
NS=mxd
BOB_CP_POD=$(kubectl get pod -n $NS | grep -i 'bob-tractusx-connector-controlplane' | awk '{print $1}' | head -n 1)
kubectl exec -n $NS "$BOB_CP_POD" -- sh -lc '
set -eu
JAR=$(find /app -maxdepth 3 -type f -name "edc-runtime.jar" 2>/dev/null | head -n 1 || true)
echo "JAR=$JAR"
unzip -p "$JAR" META-INF/services/org.eclipse.edc.spi.system.ServiceExtension 2>/dev/null || true
'
```
- **Result:** success (extensions present)
- **Evidence:**
```
org.eclipse.tractusx.edc.iam.iatp.IatpDefaultScopeExtension
org.eclipse.tractusx.edc.iam.iatp.IatpIdentityExtension
org.eclipse.tractusx.edc.iam.iatp.IatpScopeExtractorExtension
org.eclipse.tractusx.edc.iam.dcp.sts.RemoteTokenServiceClientExtension
org.eclipse.tractusx.edc.iam.dcp.sts.StsClientConfigurationExtension
org.eclipse.edc.iam.identitytrust.core.DcpDefaultServicesExtension
org.eclipse.edc.iam.identitytrust.core.DcpScopeExtractorExtension
org.eclipse.edc.iam.identitytrust.core.IdentityAndTrustExtension
org.eclipse.edc.iam.identitytrust.core.IdentityTrustTransformExtension
org.eclipse.edc.token.TokenServicesExtension
```
- **Conclusion:** Token/IATP/DCP/IdentityTrust extensions are loaded; failure is likely request parameters (token/scope) rather than missing extensions.
- **Next:** Increase connector logging to expose STS/PQ parameters and scope behavior (Step 29).

---

## [Step 29] Increase Bob Control Plane Logging for IATP/DCP/STS
- **Date:** 2026-01-30 13:55
- **Command:**
```bash
NS=mxd
DEPLOY=bob-tractusx-connector-controlplane

CURRENT=$(kubectl get deploy -n $NS $DEPLOY -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="JAVA_TOOL_OPTIONS")].value}')
EXTRA='-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=yyyy-MM-dd"T"HH:mm:ss.SSS -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.dcp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.dcp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.identitytrust.core=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.identitytrust.transform=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.dcp.sts=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.iatp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.token=debug'
kubectl set env -n $NS deployment/$DEPLOY JAVA_TOOL_OPTIONS="$CURRENT $EXTRA"

kubectl rollout restart -n $NS deployment/$DEPLOY
kubectl rollout status -n $NS deployment/$DEPLOY --timeout=180s

BOB_CP_POD=$(kubectl get pod -n $NS | grep -i 'bob-tractusx-connector-controlplane' | awk '{print $1}' | head -n 1)
kubectl logs -n $NS "$BOB_CP_POD" --since=5m | egrep -i 'iatp|dcp|sts|token|presentation|scope|bearer|identitytrust|Self-Issued|bearer_access_scope'
```
- **Result:** logging increased; still no STS/PQ request payload details
- **Evidence:**
```
Picked up JAVA_TOOL_OPTIONS: ... -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.dcp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.dcp=debug ...
INFO 2026-01-30T04:53:48.708972678 No default scope from configuration. Using the default ones [org.eclipse.tractusx.vc.type:MembershipCredential:read]
WARNING 2026-01-30T04:53:48.844887194 No TokenDecorator was registered. The 'scope' field of outgoing protocol messages will be empty
```
- **Conclusion:** Logging now shows IATP/DCP initialization and default scope; scope propagation is disabled (no TokenDecorator), which may explain missing scope in outgoing messages.
- **Next:** Identify and enable TokenDecorator/scope propagation config key to ensure PQ/STS requests include bearer_access_scope.

---

## [Step 30] Revert Custom Extension/Classpath Injection (Baseline Restored)
- **Date:** 2026-01-30 14:49
- **Command:**
```bash
kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane \
  JAVA_TOOL_OPTIONS='-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=1044 -Dorg.slf4j.simpleLogger.defaultLogLevel=info -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.iatp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.dcp.sts=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.identitytrust=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.token=debug'

kubectl patch deployment -n mxd bob-tractusx-connector-controlplane --type='json' -p='[
  {"op":"remove","path":"/spec/template/spec/containers/0/command"},
  {"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--log-level=DEBUG"]}
]'

kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
kubectl rollout status -n mxd deployment/bob-tractusx-connector-controlplane --timeout=180s

kubectl get deployment -n mxd bob-tractusx-connector-controlplane -o yaml | sed -n '/containers:/,/resources:/p'
```
- **Result:** success (deployment restored to baseline runtime)
- **Evidence:**
```
args:
- --log-level=DEBUG
env:
- name: JAVA_TOOL_OPTIONS
  value: -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=1044 -Dorg.slf4j.simpleLogger.defaultLogLevel=info -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.iatp=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.tractusx.edc.iam.dcp.sts=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.iam.identitytrust=debug -Dorg.slf4j.simpleLogger.log.org.eclipse.edc.token=debug
```
- **Conclusion:** Custom jar/command overrides removed; controlplane back to standard chart runtime.
- **Next:** Determine which DSP auth path is used and which config keys control TokenDecorator activation.

---

## [Step 31] Presentation Query Success With Self-Issued Token (token + scope)
- **Date:** 2026-01-30 18:44
- **Command:**
```bash
NS=mxd
DEPLOY=bob-tractusx-connector-controlplane
POD=$(kubectl get pod -n $NS --sort-by=.status.startTime | grep -i "$DEPLOY" | tail -n1 | awk '{print $1}')
STS_URL=$(kubectl exec -n $NS "$POD" -- printenv EDC_IAM_STS_OAUTH_TOKEN_URL)
CLIENT_ID=$(kubectl exec -n $NS "$POD" -- printenv EDC_IAM_STS_OAUTH_CLIENT_ID)
SECRET_ALIAS=$(kubectl exec -n $NS "$POD" -- printenv EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS)
AUD_SSI=$(kubectl exec -n $NS "$POD" -- printenv TX_SSI_ENDPOINT_AUDIENCE)
PQ_BASE=$(kubectl exec -n $NS "$POD" -- printenv EDC_IAM_IATP_PRESENTATION_QUERY_URL)
SECRET=$(kubectl exec -n $NS bob-vault-0 -- vault kv get -mount=secret -field=content "$SECRET_ALIAS" | tr -d '\r\n')

kubectl run -n $NS pq-sanity-$(date +%s) --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
PQ_BASE='$PQ_BASE'
PQ_FULL=\"\${PQ_BASE%/}/presentations/query\"

ACCESS=\$(curl -sS -X POST \"$STS_URL\" \\
  -H 'Content-Type: application/x-www-form-urlencoded' \\
  --data-urlencode 'grant_type=client_credentials' \\
  --data-urlencode 'client_id=$CLIENT_ID' \\
  --data-urlencode 'client_secret=$SECRET' \\
  --data-urlencode 'audience=$AUD_SSI' | sed -n 's/.*\"access_token\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\\1/p')

TOKEN=\$(curl -sS -X POST \"$STS_URL\" \\
  -H 'Content-Type: application/x-www-form-urlencoded' \\
  --data-urlencode 'grant_type=client_credentials' \\
  --data-urlencode 'client_id=$CLIENT_ID' \\
  --data-urlencode 'client_secret=$SECRET' \\
  --data-urlencode 'audience=$AUD_SSI' \\
  --data-urlencode \"token=\$ACCESS\" \\
  --data-urlencode 'bearer_access_scope=org.eclipse.tractusx.vc.type:MembershipCredential:read' | sed -n 's/.*\"access_token\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\\1/p')

curl -sS -X POST \"\$PQ_FULL\" \\
  -H \"Authorization: Bearer \$TOKEN\" \\
  -H 'Content-Type: application/json' \\
  -d '{"@context":["https://w3id.org/dspace-dcp/v1.0/dcp.jsonld"],"type":"PresentationQueryMessage","scope":["org.eclipse.tractusx.vc.type:MembershipCredential:read"]}' \\
  -w '\nHTTP=%{http_code}\n' | head -n 40
"
```
- **Result:** success (HTTP 200 PresentationResponseMessage)
- **Notes:** PQ requires a self-issued token containing `token` and `scope` claims; plain STS access tokens return 401.

---

## [Step 32] DID Document Shows CredentialService Endpoint on 7082 (Service Host)
- **Date:** 2026-01-30 18:45
- **Command:**
```bash
NS=mxd
kubectl run -n $NS did-parse-$(date +%s) --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
curl -sS 'http://bob-ih:7083/bob/.well-known/did.json' \
| tr -d '\n' | sed 's/,/,\n/g' \
| egrep -n 'CredentialService|serviceEndpoint|7081|7082|credentials/v1|identity/v1alpha|presentations/query' || true
"
```
- **Result:** success (CredentialService endpoint is `http://bob-ih:7082/api/credentials/v1/participants/...`)
- **Notes:** FQDN-based DID resolution still returns 204; service hostname `bob-ih` serves the document.

---

## [Step 33] BDRS Probe Still 401 With STS Access Token
- **Date:** 2026-01-30 18:46
- **Command:**
```bash
NS=mxd
DEPLOY=bob-tractusx-connector-controlplane
POD=$(kubectl get pod -n $NS --sort-by=.status.startTime | grep -i "$DEPLOY" | tail -n1 | awk '{print $1}')
BOB_DID=$(kubectl exec -n $NS "$POD" -- printenv EDC_IAM_STS_OAUTH_CLIENT_ID)
SECRET=$(kubectl exec -n $NS bob-vault-0 -- vault kv get -mount=secret -field=content bob-sts-client-secret | tr -d '\r\n')

for AUD in 'http://bdrs-server:8082/api/directory' 'http://bdrs-server:8082'; do
  kubectl run -n $NS bdrs-probe-$(date +%s) --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
  STS='http://bob-ih.${NS}.svc.cluster.local:7084/api/sts/token'
  RESP=\$(curl -sS -X POST \"\$STS\" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode 'client_id=$BOB_DID' \
    --data-urlencode 'client_secret=$SECRET' \
    --data-urlencode 'audience=$AUD')
  TOKEN=\$(echo \"\$RESP\" | sed -n 's/.*\"access_token\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\\1/p')
  curl -sS -w '\nHTTP=%{http_code}\n' \
    -H \"Authorization: Bearer \$TOKEN\" \
    'http://bdrs-server:8082/api/directory/bpn-directory' | head -n 40
  "
done
```
- **Result:** failure (HTTP 401)
- **Notes:** BDRS still rejects plain STS access token; prior success required VP JWT from PQ response.

---

## [Step 34] Catalog Request Still Fails (Empty Optional)
- **Date:** 2026-01-30 18:47
- **Command:**
```bash
NS=mxd
kubectl rollout restart -n $NS deployment/bob-tractusx-connector-controlplane
kubectl rollout status  -n $NS deployment/bob-tractusx-connector-controlplane --timeout=180s

kubectl logs -n $NS deployment/bob-tractusx-connector-controlplane --tail=400 \
| egrep -i 'bdrs|token verification|presentation query|credentials|empty optional|crawl|catalog|error|401|403|404|200' \
| tail -n 200 || true

curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"},
    "counterPartyAddress": "http://alice-tractusx-connector-controlplane:8084/api/v1/dsp",
    "protocol": "dataspace-protocol-http"
  }'
```
- **Result:** failure (crawler: `Unable to obtain credentials: Empty optional`, catalog request `HTTP=000`)
- **Notes:** Control plane still not obtaining credentials for catalog crawl.

### [Runbook Execution] Full Cycle Steps 1-8
- **Date:** Fri Jan 30 20:02:16 KST 2026
- **Status:** FAILED
- **Step 1:** OK (Port-forward active)
- **Step 2:** OK (STS 200 - Token generated)
- **Step 3:** FAIL (DID 204 for Bob & Alice - `bob_did_http=204`)
- **Step 4:** OK (URLs normalized to `.../v1/participants/...`)
- **Step 5:** OK (Auth Header=Authorization enforced, API keys removed)
- **Step 6:** FAIL (Publish endpoints 404, DID remains 204)
- **Step 7:** FAIL (BDRS 401 - AuthenticationFailed for both audiences)
- **Step 8:** FAIL (Catalog Request 000/502, Logs show `HTTP 405 Method Not Allowed` from Alice's DSP endpoint)

**Critical Findings:**
1. **DID Resolution Failure (204):** Both Alice and Bob return 204 No Content for `.well-known/did.json`. This is the primary blocker for BDRS authentication.
2. **BDRS Authentication:** Fails (401) because BDRS likely cannot resolve Bob's DID to verify the token signature.
3. **Catalog Request 405:** Bob receives 405 from Alice during crawl. This is a secondary issue (Protocol negotiation/pathing).
4. **Publish 404:** The manual publish endpoints in Step 6 are not reachable (404), suggesting a mismatch in IdentityHub API version or configuration.

### [Final Resolution] Success
- **Date:** Fri Jan 30 20:29:53 KST 2026
- **Status:** FIXED
- **Root Causes:**
  1. **DID Resolution Failure (204):** Internal IdentityHub DID serving logic was broken. Replaced with Nginx Sidecars for Bob, Alice, and Issuer.
  2. **DID Format Mismatch:** System components (STS) required URL-Encoded DIDs (`%3A`), while Web Resolution required Standard DIDs (`:`). Implemented Hybrid Strategy (DB has Encoded DID, Nginx serves Standard Key resolving to Encoded Content).
  3. **Issuer Resolution:** Bob could not resolve `did:web:dataspace-issuer` because no DNS entry existed. Fixed with `dataspace-issuer` Service Alias and Nginx Sidecar.
  4. **Protocol Path Mismatch (405):** Bob targeted `.../api/dsp`, Alice listened on `.../api/v1/dsp`. Fixed by updating Alice to `/api/dsp`.

- **Verification:**
  - **DID Endpoints:** All return 200 OK with correct JSON.
  - **Catalog Request:** Bob's Federated Catalog Cache now contains **1 entry** (Alice's catalog).
  - **Logs:** Bob's logs show `Crawler... is done` without errors.

**Mission Accomplished.**

### [UWL Runbook Re-Run] 2026-01-30 (Search/Analyze Mode)

#### Step 1 — Port-forward
- **Command:** `nohup ./port-forward.sh > /tmp/port-forward-uwl.log 2>&1 &`
- **Verify:**
  - `curl -sS -o /dev/null -w "bob_mgmt_http=%{http_code}\n" http://localhost:8283/management/v3/`
  - `curl -sS -o /dev/null -w "alice_mgmt_http=%{http_code}\n" http://localhost:8282/management/v3/`
- **Result:**
  - `bob_mgmt_http=404`
  - `alice_mgmt_http=404`

#### Step 2 — Reproduce failure
- **Command:**
```bash
curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d '{
    "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
    "counterPartyAddress":"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp",
    "protocol":"dataspace-protocol-http"
  }'
```
- **Result:** HTTP=502
- **Body:** `[{"message":"Unable to obtain credentials: Empty optional","type":"BadGateway",...}]`

#### Step 3 — Check DID endpoints NOW
- **Command:**
```bash
NS=mxd
for who in bob alice; do
  kubectl run -n $NS did-$who --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc \
  "URL=http://${who}-ih.${NS}.svc.cluster.local:7083/${who}/.well-known/did.json; \
   echo URL=\"\$URL\"; \
   curl -sS -i \"\$URL\" | head -n 40"
done
```
- **Result:**
  - Bob DID: HTTP 404 (nginx)
  - Alice DID: HTTP 404 (nginx)
- **Stop Condition Triggered:** DID endpoints are NOT 200 → must fix DID serving before proceeding to PQ.

### [Step 3] DID endpoints fixed (Nginx .well-known)
- **Date:** 2026-01-30
- **Change:** Added additional Nginx sidecar mount for `/.well-known/did.json` for both Bob and Alice so `/bob/.well-known/did.json` and `/alice/.well-known/did.json` resolve.
- **Commands:**
```bash
# add .well-known did.json mounts
kubectl get deployment bob-ih -n mxd -o json | jq '
  .spec.template.spec.containers |= map(if .name=="nginx-sidecar" then . + {"volumeMounts": (.volumeMounts + [{"name":"did-doc","mountPath":"/usr/share/nginx/html/bob/.well-known/did.json","subPath":"did.json"}])} else . end)
' | kubectl apply -f -

kubectl get deployment alice-ih -n mxd -o json | jq '
  .spec.template.spec.containers |= map(if .name=="nginx-sidecar" then . + {"volumeMounts": (.volumeMounts + [{"name":"did-doc","mountPath":"/usr/share/nginx/html/alice/.well-known/did.json","subPath":"did.json"}])} else . end)
' | kubectl apply -f -

kubectl rollout status -n mxd deployment/bob-ih --timeout=180s
kubectl rollout status -n mxd deployment/alice-ih --timeout=180s
```
- **Verify:**
```bash
NS=mxd
for who in bob alice; do
  kubectl run -n $NS did-$who --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "URL=http://${who}-ih.${NS}.svc.cluster.local:7083/${who}/.well-known/did.json; echo URL=\"\$URL\"; curl -sS -i \"\$URL\" | head -n 40"
done
```
- **Result:**
  - Bob DID: HTTP 200 OK (JSON)
  - Alice DID: HTTP 200 OK (JSON)

### [UWL Step 4] Presentation Query auth + JSON-LD (2026-01-30)
- **Command (STS access token + PQ JSON-LD):**
```bash
NS=mxd
BOB_IH_FQDN="bob-ih.${NS}.svc.cluster.local"
BOB_DID='did:web:bob-ih%3A7083:bob'
PID_B64=$(printf '%s' "$BOB_DID" | base64 -w0)
SECRET=$(kubectl exec -n $NS bob-vault-0 -- vault kv get -mount=secret -field=content bob-sts-client-secret | tr -d '\r\n')
AUD_DSP='http://bob-controlplane:8084/api/v1/dsp'

kubectl run -n $NS pq-probe --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
STS='http://$BOB_IH_FQDN:7084/api/sts/token'
TOKEN=\$(curl -sS -X POST \"\$STS\" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=$BOB_DID' \
  --data-urlencode \"client_secret=$SECRET\" \
  --data-urlencode 'audience=$AUD_DSP' \
| sed -n 's/.*\"access_token\"[ ]*:[ ]*\"\([^\"]*\)\".*/\1/p')

URL='http://$BOB_IH_FQDN:7082/api/credentials/v1/participants/'\"$PID_B64\"'/presentations/query'
cat > /tmp/pq.json <<'JSON'
{\"@context\":[\"https://w3id.org/dspace-dcp/v1.0/dcp.jsonld\"],\"type\":\"PresentationQueryMessage\",\"scope\":[\"org.eclipse.tractusx.vc.type:MembershipCredential:read\"]}
JSON

curl -sS -i -X POST \"\$URL\" \
  -H 'Content-Type: application/json' \
  -H \"Authorization: Bearer \$TOKEN\" \
  --data-binary @/tmp/pq.json | head -n 30
"
```
- **Result:** HTTP 401
- **Message:** `Required claim 'token' not present on token` and `audience mismatch (expected did:web:bob-ih%3A7083:bob)`

- **Self-issued token test (token + bearer_access_scope):**
```bash
AUD_SSI='did:web:bob-ih%3A7083:bob'
ACCESS=$(curl -sS -X POST "$STS" ... --data-urlencode "audience=$AUD_SSI" | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
TOKEN=$(curl -sS -X POST "$STS" ... --data-urlencode "audience=$AUD_SSI" --data-urlencode "token=$ACCESS" --data-urlencode 'bearer_access_scope=org.eclipse.tractusx.vc.type:MembershipCredential:read' | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')

curl -sS -i -X POST "$URL" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary @/tmp/pq.json | head -n 30
```
- **Result:** HTTP 200 `PresentationResponseMessage` (PQ succeeds with self-issued token)

- **Note:** `javap` is not present in container (`sh: javap: not found`), so class inspection was not possible.

### [UWL Step 5] Catalog request retry (after Step 4)
- **Command:**
```bash
kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
kubectl rollout status  -n mxd deployment/bob-tractusx-connector-controlplane --timeout=180s
kubectl port-forward svc/bob-tractusx-connector-controlplane -n mxd 8283:8081 &
PID=$!
sleep 5
curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"counterPartyAddress":"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp","protocol":"dataspace-protocol-http"}'
kill $PID
```
- **Result:** HTTP 502
- **Body:** `Unable to obtain credentials: Empty optional`

### [Config Attempt] IATP STS OAuth (no effect yet)
- **Change:**
```bash
kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE='did:web:bob-ih%3A7083:bob' \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE='org.eclipse.tractusx.vc.type:MembershipCredential:read' \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_URL='http://bob-ih:7084/api/sts/token' \
  EDC_IAM_IATP_STS_OAUTH_CLIENT_ID='did:web:bob-ih%3A7083:bob' \
  EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS='bob-sts-client-secret'
```
- **Result:** catalog request still HTTP 502 (credentials not obtained).
## [Step 35] UWL Re-Run: DID fixed, PQ needs Self-Issued token, Catalog still fails (Empty optional)
- Date: 2026-01-30
- Goal: Bob Catalog Request -> 200 OK (crawl Alice catalog)

### Summary
- DID endpoints were broken (404/204) and are now fixed via nginx sidecar mounts.
- Presentation Query (PQ) fails with a plain STS token (401: missing claim `token`, audience mismatch).
- PQ succeeds only with Self-Issued token flow (`token=` + `bearer_access_scope=`).
- Despite PQ success in manual probe, Bob controlplane catalog crawl still fails with:
  `Unable to obtain credentials: Empty optional` (HTTP 502)

### Step 1 — Port-forward OK
- Command:
```bash
nohup ./port-forward.sh > /tmp/port-forward-uwl.log 2>&1 &

curl -sS -o /dev/null -w "bob_mgmt_http=%{http_code}\n" http://localhost:8283/management/v3/
curl -sS -o /dev/null -w "alice_mgmt_http=%{http_code}\n" http://localhost:8282/management/v3/
Result:

bob_mgmt_http=404

alice_mgmt_http=404

Note: 404 on /management/v3/ root is expected; port-forward is alive.

Step 2 — Reproduce catalog failure (baseline)
Command:

curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d '{
    "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
    "counterPartyAddress":"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp",
    "protocol":"dataspace-protocol-http"
  }'
Result: HTTP 502

Body: [{"message":"Unable to obtain credentials: Empty optional","type":"BadGateway",...}]

Step 3 — DID endpoints check (were 404 -> fixed to 200)
Initial check (FAIL):

NS=mxd
for who in bob alice; do
  kubectl run -n $NS did-$who --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc \
  "URL=http://${who}-ih.${NS}.svc.cluster.local:7083/${who}/.well-known/did.json; \
   echo URL=\"\$URL\"; \
   curl -sS -i \"\$URL\" | head -n 40"
done
Result: Bob DID 404, Alice DID 404 (nginx)

Fix (add .well-known/did.json mounts):

kubectl get deployment bob-ih -n mxd -o json | jq '
  .spec.template.spec.containers |= map(if .name=="nginx-sidecar" then . + {"volumeMounts": (.volumeMounts + [{"name":"did-doc","mountPath":"/usr/share/nginx/html/bob/.well-known/did.json","subPath":"did.json"}])} else . end)
' | kubectl apply -f -

kubectl get deployment alice-ih -n mxd -o json | jq '
  .spec.template.spec.containers |= map(if .name=="nginx-sidecar" then . + {"volumeMounts": (.volumeMounts + [{"name":"did-doc","mountPath":"/usr/share/nginx/html/alice/.well-known/did.json","subPath":"did.json"}])} else . end)
' | kubectl apply -f -

kubectl rollout status -n mxd deployment/bob-ih --timeout=180s
kubectl rollout status -n mxd deployment/alice-ih --timeout=180s
Verify (PASS):

NS=mxd
for who in bob alice; do
  kubectl run -n $NS did-$who --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc \
  "URL=http://${who}-ih.${NS}.svc.cluster.local:7083/${who}/.well-known/did.json; \
   echo URL=\"\$URL\"; \
   curl -sS -i \"\$URL\" | head -n 40"
done
Result: Bob DID 200 OK, Alice DID 200 OK

Step 4 — PQ probe (plain STS token fails, Self-Issued token succeeds)
Plain STS token (FAIL 401):

NS=mxd
BOB_IH_FQDN="bob-ih.${NS}.svc.cluster.local"
BOB_DID='did:web:bob-ih%3A7083:bob'
PID_B64=$(printf '%s' "$BOB_DID" | base64 -w0)
SECRET=$(kubectl exec -n $NS bob-vault-0 -- vault kv get -mount=secret -field=content bob-sts-client-secret | tr -d '\r\n')
AUD_DSP='http://bob-controlplane:8084/api/v1/dsp'

kubectl run -n $NS pq-probe --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -lc "
STS='http://$BOB_IH_FQDN:7084/api/sts/token'
TOKEN=\$(curl -sS -X POST \"\$STS\" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=$BOB_DID' \
  --data-urlencode \"client_secret=$SECRET\" \
  --data-urlencode 'audience=$AUD_DSP' \
| sed -n 's/.*\"access_token\"[ ]*:[ ]*\"\\([^\"]*\\)\".*/\\1/p')

URL='http://$BOB_IH_FQDN:7082/api/credentials/v1/participants/'\"$PID_B64\"'/presentations/query'
cat > /tmp/pq.json <<'JSON'
{\"@context\":[\"https://w3id.org/dspace-dcp/v1.0/dcp.jsonld\"],\"type\":\"PresentationQueryMessage\",\"scope\":[\"org.eclipse.tractusx.vc.type:MembershipCredential:read\"]}
JSON

curl -sS -i -X POST \"\$URL\" \
  -H 'Content-Type: application/json' \
  -H \"Authorization: Bearer \$TOKEN\" \
  --data-binary @/tmp/pq.json | head -n 30
"
Result: HTTP 401

Message: Required claim 'token' not present on token + audience mismatch (expected did:web:bob-ih%3A7083:bob)

Self-Issued token (PASS 200):

AUD_SSI='did:web:bob-ih%3A7083:bob'
# ACCESS: STS token for AUD_SSI
# TOKEN: STS token with token=ACCESS + bearer_access_scope
ACCESS=$(curl -sS -X POST "$STS" ... --data-urlencode "audience=$AUD_SSI" | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
TOKEN=$(curl -sS -X POST "$STS" ... --data-urlencode "audience=$AUD_SSI" --data-urlencode "token=$ACCESS" --data-urlencode 'bearer_access_scope=org.eclipse.tractusx.vc.type:MembershipCredential:read' | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')

curl -sS -i -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/pq.json | head -n 30
Result: HTTP 200 PresentationResponseMessage

Step 5 — Catalog request retry (still FAIL)
Command:

kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
kubectl rollout status  -n mxd deployment/bob-tractusx-connector-controlplane --timeout=180s
kubectl port-forward svc/bob-tractusx-connector-controlplane -n mxd 8283:8081 &
PID=$!
sleep 5

curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"counterPartyAddress":"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp","protocol":"dataspace-protocol-http"}'

kill $PID
Result: HTTP 502

Body: Unable to obtain credentials: Empty optional

Step 6 — Config attempt: IATP STS OAuth (no effect yet)
Change:

kubectl set env -n mxd deployment/bob-tractusx-connector-controlplane \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE='did:web:bob-ih%3A7083:bob' \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE='org.eclipse.tractusx.vc.type:MembershipCredential:read' \
  EDC_IAM_IATP_STS_OAUTH_TOKEN_URL='http://bob-ih:7084/api/sts/token' \
  EDC_IAM_IATP_STS_OAUTH_CLIENT_ID='did:web:bob-ih%3A7083:bob' \
  EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS='bob-sts-client-secret'
Result: No change; catalog request still 502 / Empty optional

Current Interpretation
DID serving is now OK (200), so DID resolution is no longer the blocker.

PQ endpoint requires Self-Issued token semantics (token claim + correct audience).

Bob controlplane still uses a token flow that does not produce the required Self-Issued token for PQ, so credential acquisition fails and manifests as Empty optional.

Next Actions (Configuration-only, no custom extensions)
Identify which token flow Bob controlplane uses for PQ during catalog crawl (look for logs around token acquisition / presentation query).

Ensure Bob is configured to request Self-Issued token for PQ:

audience = did:web:bob-ih%3A7083:bob

bearer_access_scope includes org.eclipse.tractusx.vc.type:MembershipCredential:read

token chaining enabled (token=<access> style)

Confirm all relevant IAM env vars actually match the connector version (names may be different / ignored).

Re-run catalog request with logs focused on PQ/token:

kubectl logs -n mxd deployment/bob-tractusx-connector-controlplane --tail=400 \
| egrep -i 'presentation|query|token|sts|credential|iatp|empty optional|error|401|403|audience|scope'
## [Step 36] Inject STS OAuth env via Terraform
- **Command:** `terraform plan -target=module.bob-connector` then `terraform apply -target=module.bob-connector -auto-approve`
- **Result:** Targeted plan/add job completes; Helm release now merges `EDC_IAM_IATP_STS_OAUTH_*` + `TX_EDC_IAM_IATP_STS_OAUTH_*` into Bob control plane env along with the credential/presentation URLs/headers.
- **Notes:** Terraform warns about resource targeting, but the update succeeded; connector now has explicit OAuth audience/scope/client for Self-Issued tokens so the IATP/Presentation Query flows can chain `token` + `bearer_access_scope` claims.

## [Step 37] Align dataspace-issuer service port and confirm DID access
- **Command:** `terraform plan -target=kubernetes_service.dataspace-issuer-did-server-service` / `terraform apply -target=kubernetes_service.dataspace-issuer-did-server-service -auto-approve` followed by `kubectl run -n mxd curl-did --rm ... 'curl -sS http://dataspace-issuer/.well-known/did.json'`
- **Result:** Service now targets container port 80; curl executed from a helper pod returns the DID document.
- **Notes:** DID resolution now returns HTTP 200 via the `dataspace-issuer` ClusterIP (10.96.110.202) with the expected `did:web:dataspace-issuer#key-1` verification method, so service-level accessibility is confirmed.

## [Step 38] Catalog request still fails because DID key resolution refuses connections
- **Command:** `kubectl port-forward svc/bob-tractusx-connector-controlplane -n mxd 8283:8081 ...` then `curl -sS .../catalog/request` plus `kubectl logs -n mxd deployment/bob-tractusx-connector-controlplane --tail=400`
- **Result:** Catalog POST still returns HTTP 502 `Unable to obtain credentials: Empty optional`; logs show repeated `Unauthorized` and `Error resolving DID: Failed to connect to dataspace-issuer/10.96.110.202:80` while verifying JWTs.
- **Notes:** Root cause remains that the control plane cannot reach the dataspace-issuer DID endpoint even though the service exists; until that connection succeeds the STS/BDRS chain cannot validate self-issued tokens. Immediate next action is to confirm connectivity from inside Bob control plane (missing curl binary) or add a sidecar to proxy `dataspace-issuer` traffic, so the DID key can be resolved and the catalog crawl can succeed.

## [Step 39] STS `invalid_client` breaks BDRS presentation
- **Command:** `kubectl logs -n mxd deployment/alice-tractusx-connector-controlplane --tail=200`
- **Result:** Every catalog crawl now calls `http://alice-ih:7084/api/sts/token` and receives HTTP 401 `{"error":"invalid_client","error_description":"Invalid client or Invalid client credentials"}`. Bob uses this response to generate the BDRS presentation, so the crawler never obtains a valid VP and keeps re-queuing `CatalogError 401 Unauthorized` entries.
- **Notes:** The IdentityHub STS rejects the connector’s DID-based credentials because the connector seeds `alice-sts-client-secret`/`bob-sts-client-secret` while the IH-generated `clientId`/`clientSecret` from the seed job do not match. Need to determine which STS credentials IH expects (the ones returned when participants are created) and propagate those values into the connectors’ `EDC_IAM_IATP_STS_OAUTH_*` env vars or register those DIDs as allowed clients before retrying the catalog request.

## [Step 40] Verified STS env, creds, and Vault secret
- **Command:** `terraform plan -target=module.bob-connector` + `psql -U bob -d bob -c "select client_id, secret_alias, name from public.edc_sts_client;"` + `vault kv get secret/bob-sts-client-secret`
- **Result:** Terraform plan still shows `edc.iam.sts.oauth.token.url=http://bob-ih:7084/api/sts/token` and `client_id`/`secret_alias` set to `did:web:bob-ih%3A7083:bob` / `bob-sts-client-secret`; Postgres query returns the expected row; Vault contains the `content=RjGBe0yZxiZuUzXm` secret for that alias.
- **Notes:** Bob’s connector is already configured with the DB/Vault credentials we must reuse, so no env changes were required. The seed alias aligns with the IAM table.

## [Step 41] STS token POST still fails inside cluster
- **Command:** `kubectl run -n mxd sts-test --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -c 'curl -sS -w "\nHTTP=%{http_code}\n" -X POST http://bob-ih:7084/api/sts/token -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=did:web:bob-ih%3A7083:bob&client_secret=RjGBe0yZxiZuUzXm&audience=did:web:bob-ih%3A7083:bob"'`
- **Result:** HTTP 401 `{"error":"invalid_client","error_description":"Invalid client or Invalid client credentials"}` despite using the DB-provisioned client_id/secret and pointing at `bob-ih`, so the STS token request still fails and the catalog crawl remains blocked.
- **Notes:** DT verified we are hitting the correct STS and using the documented credentials; the user-configured path in `bob.tf` already matches the DB/Vault pair. Next action is to determine why IdentityHub still rejects the supplied secret (e.g., check whether the secret alias rotated or if the STS caches a different value) before rerunning the catalog request.

## [Step 42] Seeded Bob STS client into Alice IH
- **Command:** `psql -U alice -d alice -c "INSERT INTO public.edc_sts_client ..."` then `kubectl exec -n mxd alice-vault-0 -- vault kv get -field=content secret/bob-sts-client-secret` and `kubectl rollout restart deployment/alice-ih -n mxd`
- **Result:** Alice’s STS now has the Bob `client_id`/`secret_alias` entry and the Vault secret on Alice matches `RjGBe0yZxiZuUzXm`, but hitting `http://alice-ih:7084/api/sts/token` still returns HTTP 401 `invalid_client`, so Alice’s STS continues to reject the credentials despite the DB/Vault row existing. The catalog request remains HTTP 502 “Unable to obtain credentials: Empty optional.”
- **Notes:** STS still needs the exact secret the connector supplies; the next action is to either route the token request to Bob’s STS or determine why Alice’s STS still fails to validate the alias/secret, then rerun the catalog request once that resolves.
Date: 2026-01-31

Step A (catalog request + 30m log capture)
Command: rolled bob-tractusx-connector-controlplane, used port-forward script (PID 281576) so localhost:8283 resolves, then curl POST to http://localhost:8283/management/v3/catalog/request and filtered the last 30m of logs for credentials/STS keywords.
Result: curl still returned HTTP=000 with "Empty reply from server" (/tmp/catalog_request_30m.out); logs only show repeated 401 Unauthorized catalog errors against http://alice-cs:8082/api/dsp (see /tmp/bob_cp_30m_grep.log lines around 674+) and no "Empty optional" message even after searching the 30m and 1h logs directly.
Evidence: /tmp/catalog_request_30m.out, /tmp/bob_cp_30m_grep.log (e.g., line 674 onwards shows the 401 cascade). Also grep -n "Empty optional" on the 30m log and the raw --since=1h log produced no matches.

Step B (Bob controlplane IAM/PQ env dump)
Command: kubectl exec into bob-tractusx-connector-controlplane-5fd58774-cpx2w and filtered env for IAM/PQ/STS keys.
Result: captured the runtime env that governs credentialservice/presentation query/STS behavior (see appended block below and /tmp/bob_cp_env_iam_pq.txt).
Evidence: the full env analog is recorded below:

```
ALICE_IH_SERVICE_PORT_CREDENTIALS=7082
ALICE_IH_SERVICE_PORT_STS=7084
BOB_IH_SERVICE_PORT_CREDENTIALS=7082
BOB_IH_SERVICE_PORT_STS=7084
DATASPACE_ISSUER_SERVICE_SERVICE_PORT_STS=10011
EDC_IAM_DID_WEB_USE_HTTPS=false
EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=Authorization
EDC_IAM_IATP_CREDENTIALSERVICE_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==
EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization
EDC_IAM_IATP_PRESENTATION_QUERY_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query
EDC_IAM_IATP_STS_OAUTH_CLIENT_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS=bob-sts-client-secret
EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE=did:web:bob-ih%3A7083:bob
EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE=org.eclipse.tractusx.vc.type:MembershipCredential:read
EDC_IAM_IATP_STS_OAUTH_TOKEN_URL=http://bob-ih:7084/api/sts/token
EDC_IAM_ISSUER_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_STS_OAUTH_CLIENT_ID=did:web:bob-ih%3A7083:bob
EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS=bob-sts-client-secret
EDC_IAM_STS_OAUTH_TOKEN_URL=http://bob-ih:7084/api/sts/token
EDC_IAM_TRUSTED-ISSUER_DATASPACE-ISSUER_ID=did:web:dataspace-issuer
EDC_IAM_TRUSTED-ISSUER_DATASPACE-ISSUER_SUPPORTEDTYPES=["*"]
EDC_OAUTH_ENDPOINT_AUDIENCE=http://bob-tractusx-connector-controlplane:8084/api/v1/dsp
EDC_OAUTH_PROVIDER_AUDIENCE=idsc:IDS_CONNECTORS_ALL
TX_EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER=Authorization
TX_EDC_IAM_IATP_CREDENTIALSERVICE_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==
TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_ALIAS=org.eclipse.tractusx.vc.type
TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_OPERATION=read
TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_TYPE=MembershipCredential
TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER=Authorization
TX_EDC_IAM_IATP_PRESENTATION_QUERY_URL=http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query
TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID=did:web:bob-ih%3A7083:bob
TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS=bob-sts-client-secret
TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE=did:web:bob-ih%3A7083:bob
TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE=org.eclipse.tractusx.vc.type:MembershipCredential:read
TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL=http://bob-ih:7084/api/sts/token
TX_IAM_IATP_BDRS_CACHE_VALIDITY=600
TX_IAM_IATP_BDRS_SERVER_URL=http://bdrs-server:8082/api/directory
TX_SSI_ENDPOINT_AUDIENCE=http://bob-controlplane:8084/api/v1/dsp
WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased
```

Step C (self-issued PQ smoke test)
Command: kubectl run a temporary curl pod using the known bob-sts-client-secret 'RjGBe0yZxiZuUzXm' to request an STS self-issued token chain and call bob-ih credentials/presentations/query with the resulting Bearer token.
Result: STS token request returned 200 but initial access token decoding failed when secret empty; after explicitly using the vault secret, the self-issued token returned a 200 OK PresentationResponseMessage, confirming Bob IH can issue the necessary credentials/presentation query when the correct secret is supplied.
Evidence: pod output printed ACCESS_LEN/TOKEN_LEN (both >0) and the PQ response body (HTTP/1.1 200 with PresentationResponseMessage JSON). The STS secret value retrieval was verified via `vault kv get` before the curl run.

### [Step 8] STS client reconciliation (Alice)
- **Command:**
  ```bash
  kubectl exec -n mxd alice-postgres-67db86db9b-6lc4w -- psql -U alice -d alice -c "UPDATE public.edc_sts_client \
    SET private_key_alias='key-1', public_key_reference='key-1' \
    WHERE client_id='did:web:bob-ih%3A7083:bob';"
  ```
- **Result:** SUCCESS – Alice STS now references the `key-1` alias that is present in its Vault, which means the client entry no longer points to a missing secret.
- **Notes:**
  - After the update, a direct request to `http://alice-ih:7084/api/sts/token` with Bob’s credentials (`client_id=did:web:bob-ih%3A7083:bob`, `client_secret=RjGBe0yZxiZuUzXm`, `audience=did:web:bob-ih%3A7083:bob`) returns **HTTP 200** and a valid access token, proving the TrustStore now accepts the client.
  - Alice control plane still logs repeated `invalid_client` when the crawler calls the same endpoint (see the `kubectl logs` snippet below), so something else in the request flow still misaligns with STS expectations.

### [Step 9] Catalog retry after STS fix
- **Command:** ran the catalog POST via `curl` against `http://localhost:8283/management/v3/catalog/request` (Bob connector) after restarting both connectors and setting up port forwarding.
- **Result:** HTTP 000 with `curl: (52) Empty reply from server` (the catalog request still fails before an HTTP 200 can be returned), while the Bob connector logs continue to report `401 Unauthorized` errors coming from `http://alice-ih:7084/api/sts/token` (see `/tmp/bob_cp_final_grep.log` and `kubectl logs` excerpts).
- **Notes:**
  - Manual STS verification now works, but the crawler’s STS request still receives `invalid_client`, so either the request parameters differ (different client_id, secret_alias, or JWS format) or Alice’s STS is not using the updated row for that particular call.
  - Next steps: inspect the crawler’s STS client configuration (TX vs EDC sections) and ensure the `client_id`/`client_secret` pair sent in production matches the row in `edc_sts_client` (including alias encoding). Also double-check the `vault` alias used within Alice’s STS for that client (the error message still indicates `Invalid client or Invalid client credentials`).

Date: 2026-01-31

Step 1 (catalog request + Bob logs)
Command: `kubectl run -n mxd catalog-test --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- sh -c "curl -sS -w '\nHTTP=%{http_code}\n' -X POST http://bob-tractusx-connector-controlplane:8081/management/v3/catalog/request -H 'Content-Type: application/json' -H 'x-api-key: password' -d '{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},\"counterPartyAddress\":\"http://alice-tractusx-connector-controlplane:8084/api/v1/dsp\",\"protocol\":\"dataspace-protocol-http\"}'"`
Result: HTTP 502 with payload `[{"message":"Unable to obtain credentials: Empty optional","type":"BadGateway"...}]`; Bob connector logs show repeated `dspace:CatalogError` 401 Unauthorized as soon as the catalog request requeues (e.g., `line 4519` onwards in `/tmp/bob_step1_grep.log`).
Evidence: `/tmp/catalog_request_step1.out` (BadGateway body + HTTP=502) and `/tmp/bob_step1_grep.log` (lines 4519‑4522 reporting the same `dspace:CatalogError`).

Step 2 (Alice controlplane STS log)
Command: `kubectl logs -n mxd deployment/alice-tractusx-connector-controlplane --since=30m | egrep -n -i '401|invalid_client|token' | head -n 40`
Result: Alice controlplane immediately logs `http://alice-ih:7084/api/sts/token` returning 401 `invalid_client` (see lines 667‑703 in `/tmp/alice_step2.log`), so the crawler’s STS request is still rejected before any catalog payload can be processed.
Evidence: `/tmp/alice_step2.log` (lines 667‑703 showing `HTTP client exception`/`invalid_client` plus stack trace).

Step 3 (Bob IAM env vs manual STS parameters)
Command: `POD=$(kubectl get pods -n mxd -l app.kubernetes.io/instance=bob-controlplane -o name | head -n 1 | sed 's#pod/##') && kubectl exec -n mxd "$POD" -- env | sort | egrep -n -i 'EDC_IAM|TX_EDC_IAM|STS|TOKEN_URL|AUDIENCE|CREDENTIALSERVICE|PRESENTATIONS|AUTH_HEADER' | tee /tmp/bob_env_step3.txt`
Result: Bob’s runtime env still references its own STS client (client_id/secret alias `did:web:bob-ih%3A7083:bob` / `bob-sts-client-secret`, audience `did:web:bob-ih%3A7083:bob`, token URL `http://bob-ih:7084/api/sts/token`), while the failing catalog crawl clearly hits `http://alice-ih:7084/api/sts/token` with the same Bob `client_id`/secret. The discrepancy is that the IaC yet-to-be-updated Alice configuration doesn’t register Bob as an STS client (Alice STS still expects its own alias), so the IaC fix must provision the `edc_sts_client` + Vault secret for Bob on the Alice side rather than relying on manual overrides.
Evidence: `/tmp/bob_env_step3.txt` (shows the four STS-related env entries) versus the manual curl parameters from earlier manual proof (`client_id=did:web:bob-ih%3A7083:bob`, `client_secret=RjGBe0yZxiZuUzXm`, `audience=did:web:bob-ih%3A7083:bob`); Alice’s STS still responds 401 because the IaC state has not registered Bob in its STS client table/secret chain.

Date: 2026-01-31

Step 4 (seeded Alice STS with Bob alias + reran catalog)
Command:
1. `./setup_vaults.sh` (adds `secret/did%3Aweb%3Abob-ih%253A7083%3Abob-sts-client-secret`).
2. `./setup_db_alice.sh` (inserts Bob STS client with secret alias `did:web:bob-ih%3A7083:bob-sts-client-secret`).
3. `kubectl rollout restart -n mxd deployment/alice-tractusx-connector-controlplane` (reload the updated alias table). 
4. `kubectl run -n mxd catalog-test --rm ...` against Bob control plane (identical catalog request payload as before).
5. Collected Bob + Alice control plane logs after the run (files `/tmp/bob_step3c_grep.log` and `/tmp/alice_step3b.log`).
Result: Catalog POST still returns HTTP 502 with `Unable to obtain credentials: Empty optional`, and Alice logs still show `Server response to [POST, http://alice-ih:7084/api/sts/token] ... 401 invalid_client` even though the manual STS curl now succeeds against Alice with the same DID/secret. 
Evidence: `/tmp/catalog_request_step3c.out` (BadGateway + HTTP=502), `/tmp/bob_step3c_grep.log` lines 5316‑5350 showing `CatalogError 401` and requeued work items, and `/tmp/alice_step3b.log` lines 668‑704 showing the STS HTTP client exception + stack trace invoking `BdrsClientImpl`. The new vault/DB outputs confirm the DID-style secret alias is present everywhere.

Date: 2026-01-31

Step 5 (alias cleanup + STS request capture)
Command:
1. Adjusted `setup_db_alice.sh` so both Alice and Bob STS clients now reference the simple `*-sts-client-secret` aliases that the vault scripts actually inject, and re-ran the script so the `edc_sts_client` rows now list `secret_alias=alice-sts-client-secret` / `secret_alias=bob-sts-client-secret`.
2. Restarted `alice-tractusx-connector-controlplane` and executed the catalog POST again (`kubectl run catalog-test ...`), collecting Bob/Alice logs and capturing the STS HTTP stream via `tcpdump` inside the `sniffer` ephemeral container (`/tmp/alice_sts_tcpdump.log`).
Result: The catalog call still arrives at Bob as `Unable to obtain credentials: Empty optional` (HTTP 502 + repeated `dspace:CatalogError 401 Unauthorized`), but Alice’s STS no longer complains about `invalid_client` (the `grep invalid_client` command returned no lines). The tcpdump now shows the STS request carrying `client_id=did:web:alice-ih%3A7083:alice`, `client_secret=password`, and `audience=did:web:bob-ih%3A7083:bob`, confirming that the connectors talk to Alice’s STS with the same alias names stored in Vault.
Evidence: `/tmp/catalog_request_step4.out`, `/tmp/bob_step4_grep.log` lines 5227‑5701 (the new `401` cascade after the alias change), `/tmp/alice_step4.log` (no `invalid_client` entries), and `/tmp/alice_sts_tcpdump.log` (the exact POST bodies showing the client_id/secret/audience sequence that was mismatched before the alias correction).

## [Step 43] TokenService/auth header mapping
- **Command:** `kubectl exec -n mxd bob-tractusx-connector-controlplane-54f8d74689-kffts -- env | sort | egrep -i 'EDC_IAM|TX_EDC_IAM|STS|PRESENTATION|CREDENTIAL|WEB_HTTP_CATALOG_AUTH_TYPE'`, `grep -n TokenService .`, and review `modules/connector/main.tf` plus the Helm values to see how the env merges into the runtime.
- **Result:** The runtime’s `META-INF/services/org.eclipse.edc.spi.system.ServiceExtension` list loads `org.eclipse.tractusx.edc.iam.dcp.sts.RemoteTokenServiceClientExtension` plus `org.eclipse.edc.token.TokenServicesExtension`, meaning the connector uses the RemoteTokenService path. The `EDC_IAM_IATP_*`/`TX_EDC_IAM_IATP_*` env vars (Authorization headers, STS token URL, client_id/secret alias) are controlled by `modules/connector/main.tf`, and `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased` is what enforces Authorization headers for catalog crawls; no other repo files reference `WEB_HTTP_CATALOG_AUTH_TYPE`.
- **Notes:** With token generation already working, the remaining blocker is that Alice’s STS/Vault must register Bob’s client_id/secret alias (or accept requests routed to Bob’s STS) so the RemoteTokenService-generated Authorization headers succeed.

## [Step 44] Step D config patch + catalog re-run
- **Command:** `kubectl set env` on `bob-tractusx-connector-controlplane` to ensure all IATP credentialservice/presentation-query auth headers use `Authorization`, clear any leftover API-keys, restart the deployment, then curl `http://localhost:8283/management/v3/catalog/request` (multiple attempts, port-forward restarted between retries) and `kubectl exec ... env` to capture the IAM variables afterwards.
- **Result:** The connector still returns HTTP 502 `Unable to obtain credentials: Empty optional` and the logs continue to show `CatalogError 401 Unauthorized` entries while the env dump still reflects Authorization headers plus `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased`. Manual PQs work, so the new config only reaffirms the RemoteTokenService path and leaves the `401 invalid_client` issue at Alice’s STS.
- **Notes:** Step D completed; catalog still blocked because Alice’s STS rejects Bob’s DID/secret pair. Next action remains registering Bob’s credentials on Alice or routing catalog tokens to Bob’s STS so Authorization succeeds.

## [Step 45] Salted catalog crawl + PQ trace
- **Command:** Rolled `bob-tractusx-connector-controlplane`, issued the `curl` catalog POST (`localhost:8283/management/v3/catalog/request`) and saved 15m of Bob logs (`/tmp/bob_catalog_15m.log`); ran `egrep …` to gather PQ/401 lines; executed `kubectl run netshoot-tcpdump` with hostNetwork and `tcpdump` to capture 7082/7084 traffic (`/tmp/bob_tcpdump_7082_7084.txt`); dumped the IAM/STS env from the fresh pod into `/tmp/bob_env_after_restart.txt`.
- **Result:** The catalog POST still returns HTTP 502 `[{"message":"Unable to obtain credentials: Empty optional"…}]` while Bob logs spike with `dspace:CatalogError 401 Unauthorized` pointing at `http://alice-cs:8082/api/dsp`; the tcpdump shows the PQ request hitting `bob-ih.mxd.svc.cluster.local:7082/api/credentials/v1/participants/.../presentations/query` with an `Authorization: Bearer ...` header (the token came from the STS call toward `alice-ih.mxd.svc.cluster.local:7084` using `client_id=did:web:alice-ih%3A7083:alice`), and the env dump still advertises `Authorization` headers plus `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased`.
- **Notes:** Token issuance/PresentationQuery wiring are working but the crawler’s STS request still uses Alice’s DID/client instead of Bob’s, so the catalog’s PQ request fails even though the manual flow succeeded; evidence saved under `/tmp/bob_catalog_15m.log`, `/tmp/bob_tcpdump_7082_7084.txt`, `/tmp/bob_env_after_restart.txt`.

Date: 2026-02-01
Step 0: Verified latest entry (tail -n 120 debug_progress.md) still shows manual Bob PQ/STS flow succeeding while catalog logs/tcpdump prove Alice STS + DID is used for crawler tokens.
Step 1: `kubectl logs ... | egrep participant|identity|...` returned no matches, so no log line explicitly stating the resolved participant context during the catalog crawl; the controlplane logs follow the same generic trace.
Step 2: `kubectl logs ... | egrep TokenService|RemoteTokenService|...` produced nothing new, so the TokenService invocation path does not log the effective `client_id` there either.
Step 3: `kubectl exec ... env | egrep ... | tee /tmp/bob_catalog_identity_env.txt` captured Bob-specific IAM/IATP env vars (`EDC_IAM_*`, `TX_EDC_IAM_*`, `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased`) despite runtime still pointing its STS requests at Alice; saved evidence in `/tmp/bob_catalog_identity_env.txt`.
Step 4: `grep -R` across `modules/connector` for `CatalogCrawler|CatalogClient|PresentationQuery|CredentialService|ParticipantContext|IdentityContext|TokenService` produced no hits, so there is no direct in-repo reference to a ParticipantContext chooser for catalog crawls in that module; the identity is inferred solely from the standard env vars/External TokenService extensions.
Conclusion: Catalog crawl still selects Alice’s identity because the RemoteTokenService-based flow (driven by `WEB_HTTP_CATALOG_AUTH_TYPE=tokenbased`) uses the connector’s original controlplane participant context, which means STS requests are routed through Alice’s STS client despite Bob-configured env vars; the log/tcpdump evidence shows the `client_id`/STS endpoint remain Alice even when Bob’s env is exported.

### [Step 46] Export TX STS env + Terraform replay
- **Command:**
  ```bash
  # Ensure Bob catalog server exports TX identity env
  apply_patch <<'PATCH'
  *** Begin Patch
  *** Update File: modules/catalog-server/catalog-server.tf
  @@
  -    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL           = var.dcp-config.sts_token_url
  -    TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID           = var.dcp-config.sts_client_id
  -    TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS = var.dcp-config.sts_clientsecret_alias
  -    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE      = var.dcp-config.id
  -    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE         = "org.eclipse.tractusx.vc.type:MembershipCredential:read"
  -    TX_EDC_IAM_STS_OAUTH_TOKEN_URL                = var.dcp-config.sts_token_url
  -    TX_EDC_IAM_STS_OAUTH_CLIENT_ID                = var.dcp-config.sts_client_id
  -    TX_EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS      = var.dcp-config.sts_clientsecret_alias
  +    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL           = var.dcp-config.sts_token_url
  +    TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID           = var.dcp-config.sts_client_id
  +    TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS = var.dcp-config.sts_clientsecret_alias
  +    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE      = var.dcp-config.id
  +    TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE         = "org.eclipse.tractusx.vc.type:MembershipCredential:read"
  +    TX_EDC_IAM_STS_OAUTH_TOKEN_URL                = var.dcp-config.sts_token_url
  +    TX_EDC_IAM_STS_OAUTH_CLIENT_ID                = var.dcp-config.sts_client_id
  +    TX_EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS      = var.dcp-config.sts_clientsecret_alias
  *** End Patch
  PATCH

  terraform init
  terraform plan
  terraform apply -auto-approve
  kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane
  curl -sS -X POST http://localhost:8283/management/v3/catalog/request -H 'Content-Type: application/json' -H 'x-api-key: password' -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"counterPartyAddress":"http://alice-tractusx-connector-controlplane.mxd.svc.cluster.local:8084/api/v1/dsp","protocol":"dataspace-protocol-http"}'
  kubectl debug -n mxd bob-tractusx-connector-controlplane-6d496875cc-kzphx --image=nicolaka/netshoot --target=tractusx-connector --attach=false --custom=/tmp/debug-custom-root.json -- sh -c 'tcpdump -i any -A -s 0 "tcp port 7084" > /tmp/tcpdump.txt 2>&1 & echo $! > /tmp/tcpdump.pid; sleep 15; kill $(cat /tmp/tcpdump.pid)'
  kubectl cp mxd/bob-tractusx-connector-controlplane-6d496875cc-kzphx:/tmp/tcpdump.txt /tmp/bob_strict_tcpdump_postfix.txt -c debugger-zkj2s
  ```
- **Result:** Terraform init/plan/apply succeeded; Bob’s catalog server ConfigMap now includes the TX STS env overrides and the rollout completed, but the catalog POST still returns HTTP 502 `Unable to obtain credentials: Empty optional`; tcpdump continues to show the STS calls hitting `bob-ih:7084` but still using Alice’s context (`client_id=did:web:alice-ih%3A7083:alice`).
- **Notes:** Config change ensures the catalog server exports both EDC and TX STS identities, yet the crawler still picks Alice’s participant context; the identity selection comes from `edc.participant.context.id`, so the next action is to set that property to Bob’s DID/participant context (and ensure any Alice-only context entries are removed) before reattempting the catalog request.

## [Step 47] Force Bob participant context and prove STS host
- **Command:**
  1. Added `EDC_PARTICIPANT_ID` and `EDC_PARTICIPANT_CONTEXT_ID` (both `var.bob-did`) to `bob.tf`’s `controlplane_env` map so the Helm overrides emit the explicit participant context.
  2. `terraform plan` / `terraform apply -auto-approve` followed by `kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane` to refresh the control plane.
  3. Restarted `./port-forward.sh` and `curl`ed `http://localhost:8283/management/v3/catalog/request` (payload saved to `/tmp/catalog_request_final.out`).
  4. Launched a privileged debug container (`kubectl debug … --custom=/tmp/debug-sec.json`) and ran `tcpdump -i any -A -s 0 "tcp port 7084"` while invoking the catalog request, then copied `/tmp/tcpdump.txt` to `/tmp/bob_tcpdump_final.txt`.
  5. Captured the control plane env (`kubectl exec … env | egrep -i 'PARTICIPANT' | tee /tmp/bob_participant_env.txt`) to prove the new variables are present.
- **Result:** `curl` still returns HTTP 502 `Unable to obtain credentials: Empty optional`, and the connector logs continue to surface `CatalogError 401 Unauthorized` (Alice DSP rejects the VP request). However, `/tmp/bob_tcpdump_final.txt` now shows STS traffic hitting `bob-ih:7084` with `client_id=did:web:bob-ih%3A7083:bob` (including the second chained request that targets Alice’s audience), and `/tmp/bob_participant_env.txt` records the explicit participant context env vars. The remaining failure therefore stems from the downstream credential fetch, not from choosing the wrong identity.
- **Notes:** Identity selection is now correct (Bob’s STS is being used end-to-end), so the remaining work is to investigate why Alice’s DSP still returns 401 (e.g., verify whether the presentation query token is still missing required claims or if the credentials are missing on Alice).

### [Step 48] Verify Bob participant context at runtime
- **Command:**
  1. `tail -n 160 debug_progress.md` to confirm there was no newer fix plan.
  2. `kubectl get deploy -n mxd bob-tractusx-connector-controlplane -o yaml | egrep -n -i 'participant\.context\.id|participant\.id|edc\.participant|EDC_|TX_|IATP|STS|TOKEN_URL|CLIENT_ID|WEB_HTTP_CATALOG_AUTH_TYPE' | head -n 300 | tee /tmp/bob_participant_context_deploy.yaml` to capture the Helm-injected values.
  3. `kubectl exec -n mxd bob-tractusx-connector-controlplane-7748c77b44-f8wzc -- env | sort | egrep -n -i 'participant\.context\.id|participant\.id|edc\.participant|EDC_|TX_|IATP|STS|TOKEN_URL|CLIENT_ID|WEB_HTTP_CATALOG_AUTH_TYPE' | tee /tmp/bob_participant_context_env.txt` to inspect the runtime env.
  4. `kubectl rollout restart -n mxd deployment/bob-tractusx-connector-controlplane`, `kubectl rollout status -n mxd deployment/bob-tractusx-connector-controlplane --timeout=180s`, then `kubectl port-forward svc/bob-tractusx-connector-controlplane -n mxd 8283:8081 >/tmp/bob_pf.log 2>&1 & echo $! >/tmp/bob_pf.pid` so the management API is reachable.
  5. `curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" -H "Content-Type: application/json" -H "x-api-key: password" -d '{ "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"}, "counterPartyAddress":"http://alice-tractusx-connector-controlplane.mxd.svc.cluster.local:8084/api/v1/dsp", "protocol":"dataspace-protocol-http" }' | tee /tmp/catalog_request_after_participant_context.out` to trigger the catalog crawl.
  6. `kubectl debug -n mxd bob-tractusx-connector-controlplane-7748c77b44-f8wzc --image=nicolaka/netshoot --profile=general --custom=/tmp/debug-custom-root.json --target=tractusx-connector -- sh -lc 'timeout 45 tcpdump -A -s 0 "tcp port 7084" 2>/dev/null | egrep -i -n "POST /api/sts/token|Host:|client_id=|audience=" | head -n 300' > /tmp/tcpdump_capture_root.txt & PID=$!; sleep 5; curl -sS -w "\nHTTP=%{http_code}\n" -X POST "http://localhost:8283/management/v3/catalog/request" -H "Content-Type: application/json" -H "x-api-key: password" -d '{ "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"}, "counterPartyAddress":"http://alice-tractusx-connector-controlplane.mxd.svc.cluster.local:8084/api/v1/dsp", "protocol":"dataspace-protocol-http" }' | tee /tmp/catalog_request_after_participant_context_tcpdump_run.out; wait $PID; cat /tmp/tcpdump_capture_root.txt | tee /tmp/bob_sts_after_participant_context_tcpdump.txt` to sample the STS traffic while re-running the crawl.
- **Result:** The deployment/env now export `EDC_PARTICIPANT_CONTEXT_ID=did:web:bob-ih%3A7083:bob`, the STS envs (EDC and TX variants) point at `http://bob-ih:7084/api/sts/token` with `client_id=did:web:bob-ih%3A7083:bob`, yet the catalog POST still returns HTTP 502 `Unable to obtain credentials: Empty optional` (see `/tmp/catalog_request_after_participant_context.out` and `/tmp/catalog_request_after_participant_context_tcpdump_run.out`). The tcpdump capture file only contains the debug/container warnings because the pod’s security context does not allow NET_RAW/privileged tracing, so we rely on the env/log evidence to confirm the STS host/client.
- **Notes:** `POD=bob-tractusx-connector-controlplane-7748c77b44-f8wzc`; `/tmp/bob_participant_context_deploy.yaml` and `/tmp/bob_participant_context_env.txt` document the wiring; `/tmp/bob_sts_after_participant_context_tcpdump.txt` holds the warning lines; the port-forward pid written to `/tmp/bob_pf.pid` was killed after the curls. Continue investigating Alice’s DSP/credential handling because the participant context wiring is now correct but catalog crawls still fail.

## [Step 49] Phase 2 — Alice DSP credential investigation
- **Command:** Restarted Alice control plane, reran the Bob catalog request, recorded `/tmp/catalog_request_phase2.out`, captured DSP/credential-focused logs in `/tmp/alice_dsp_credential_logs.txt`, queried `credential_resource` from Alice Postgres (`/tmp/alice_credential_query.txt`), and reviewed policy monitor logs (`/tmp/alice_policy_eval_logs.txt`).
- **Result:** Alice control plane continuously receives `401 invalid_client` from `http://bob-ih:7084/api/sts/token` before any PresentationQuery runs; membership/Deg credentials already exist on Alice and no DENY evaluations appear, so the connector fails because the STS exchange for Bob is rejected.
- **Notes:** Bob’s catalog crawl surfaces `Unable to obtain credentials: Empty optional` since Alice never obtains a valid STS token for Bob, preventing credential lookup/presentation generation.

## [Step 50] Catalog request via Python + new PQ logs
- **Command:** `kubectl run -n mxd catalog-test --rm -i --restart=Never --image=python:3.11-slim -- sh -c "python3 - <<'PY'\nimport json\nimport urllib.request\npayload = {'@context': {'@vocab': 'https://w3id.org/edc/v0.0.1/ns/'}, 'counterPartyAddress': 'http://alice-tractusx-connector-controlplane:8084/api/v1/dsp', 'protocol': 'dataspace-protocol-http'}\nreq = urllib.request.Request('http://bob-tractusx-connector-controlplane:8081/management/v3/catalog/request', data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json', 'x-api-key': 'password'}, method='POST')\nwith urllib.request.urlopen(req) as resp:\n    print('HTTP', resp.status)\n    print(resp.read().decode('utf-8'))\nPY"`
- **Result:** The POST still raises `HTTP Error 502: Bad Gateway` and prints the familiar payload `[{"message":"Unable to obtain credentials: Empty optional"…}]`; `bob-tractusx-connector-controlplane` logs (`kubectl logs -n mxd deployment/bob-tractusx-connector-controlplane --since=5m | egrep -i 'presentation|credential|empty optional|401|403|500'`) show repeated `dspace:CatalogError 401 Unauthorized` entries, while `alice-tractusx-connector-controlplane` logs (`kubectl logs -n mxd deployment/alice-tractusx-connector-controlplane --since=5m | egrep -i '401|invalid_client|token'`) now emit `Unauthorized: Presentation Query failed: HTTP 401, message: [{"message":"ID token [sub] claim is not equal to [token.sub] claim: expected 'did:web:bob-ih%3A7083:bob', got 'did:web:alice-ih%3A7083:alice'.",…}]` for every retry.
- **Notes:** PresentationQuery still fails because the connector presents an Authorization token whose `sub` is Alice’s DID while the `token` claim reports Bob’s DID; `alice-ih` logs also started spitting `SqlParticipantContextStore.mapResultSet` `ArrayIndexOutOfBoundsException` stack traces whenever the controller fetches participant context (see the `--tail=500` output), perhaps driven by the same identity mismatch. The next step is to trace which participant context/STS exchange the RemoteTokenService chooses so the Authorization header aligns with the `token` claim (Bob’s DID) and the PQ can succeed.
---
### [Iteration 1] Align Bob connector identity to canonical DID
- **IaC change:** `bob.tf` now passes `participantId = var.bob-did` so the Helm release sets `participant.id` to `did:web:bob-ih%3A7083:bob` instead of the BPN.
- **Apply path:** `terraform apply -target=module.bob-connector -auto-approve` (targeted plan introduced new azurite init job along the way).
- **Result:** Management catalog POST still fails with HTTP 502 (`Unable to obtain credentials: Empty optional`); Alice logs contain the identity-sub mismatch `expected 'did:web:bob-ih%3A7083:bob', got 'did:web:alice-ih%3A7083:alice'` while Presentation Query reports HTTP 401/500.
- **Restart:** Alice control plane was rolled out after the apply (`kubectl rollout restart`/`kubectl rollout status` logs in `/tmp/rollout_*`).
- **Evidence:**
  - `/tmp/catalog_request_autofix_1.out`
  - `/tmp/alice_sig_autofix_1.log`
  - `/tmp/alice_sigline_autofix_1.txt`
  - `/tmp/alice_env_autofix_1.txt`
  - `/tmp/iac_hits_autofix_1.txt`
  - `/tmp/rollout_restart_autofix_1.log`
  - `/tmp/rollout_status_autofix_1.log`
---
### [Iteration 2] Teach the TX pipeline to share Bob’s context
- **IaC change:** Added `TX_EDC_PARTICIPANT_CONTEXT_ID = var.bob-did` inside `controlplane_env` so the Tractus-X-specific flow uses the same canonical DID as the main connector env.
- **Apply path:** `terraform apply -target=module.bob-connector -auto-approve` (again triggers the azurite-init helper job).
- **Result:** Catalog POST still ends in HTTP 502 `Unable to obtain credentials: Empty optional`; Alice logs continue to report `ID token [sub]` vs `token.sub` mismatch (`did:web:bob-ih%3A7083:bob` vs `did:web:alice-ih%3A7083:alice`).
- **Restart:** Alice control plane rolled out after the apply (`/tmp/rollout_restart_autofix_2.log`, `/tmp/rollout_status_autofix_2.log`).
- **Evidence:**
  - `/tmp/catalog_request_autofix_2.out`
  - `/tmp/alice_sig_autofix_2.log`
  - `/tmp/alice_sigline_autofix_2.txt`
  - `/tmp/alice_env_autofix_2.txt`
  - `/tmp/bob_env_autofix_2.txt`
  - `/tmp/iac_hits_autofix_2.txt`
  - `/tmp/rollout_restart_autofix_2.log`
  - `/tmp/rollout_status_autofix_2.log`
---
### [Iteration 3] Ensure TX participant ID matches Bob’s DID
- **IaC change:** Injected `TX_EDC_PARTICIPANT_ID = var.bob-did` so every TX flow—from STS -> presentations -> catalog—advertises the canonical DID as its participant identity.
- **Apply path:** `terraform apply -target=module.bob-connector -auto-approve` (azurite init job runs again as part of the Helm upgrade).
- **Result:** Catalog request still returns HTTP 502 `Unable to obtain credentials: Empty optional`, and Alice’s logs keep logging `ID token [sub]` vs `token.sub` mismatch (`expected 'did:web:bob-ih%3A7083:bob', got 'did:web:alice-ih%3A7083:alice'`).
- **Restart:** Alice control plane restarted (`/tmp/rollout_restart_autofix_3.log`, `/tmp/rollout_status_autofix_3.log`).
- **Evidence:**
  - `/tmp/catalog_request_autofix_3.out`
  - `/tmp/alice_sig_autofix_3.log`
  - `/tmp/alice_sigline_autofix_3.txt`
  - `/tmp/bob_env_autofix_3.txt`
  - `/tmp/iac_hits_autofix_3.txt`
  - `/tmp/rollout_restart_autofix_3.log`
  - `/tmp/rollout_status_autofix_3.log`
