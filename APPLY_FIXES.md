# How to Apply and Test Postman Collection Fixes

## ✅ Fixes Applied

### 1. BDRS BPN Mappings (CRITICAL - Root Cause)
**File:** `MXD Management API Seed.postman_collection.json`
- **Alice**: `BPNL000000000001` → `did:web:alice-ih%3A7083:alice` ✅
- **Bob**: `BPNL000000000002` → `did:web:bob-ih%3A7083:bob` ✅

### 2. DSP Endpoint URLs
**File:** `MXD Service APIs.postman_collection.json`
- Fixed: `alice-controlplane` → `alice-tractusx-connector-controlplane`
- Fixed: `/api/dsp` → `/api/v1/dsp`

### 3. Environment Variables
**File:** `MXD-Local-FIXED.postman_environment.json` (new)
- Populated all required variables with correct values

## 📋 Testing Instructions

### Step 1: Import Fixed Files into Postman

1. Open Postman
2. Import updated collections:
   - `MXD Management API Seed.postman_collection.json`
   - `MXD Service APIs.postman_collection.json`
3. Import environment:
   - `MXD-Local-FIXED.postman_environment.json`
4. Select "MXD-Local-FIXED" as active environment

### Step 2: Clear Existing BDRS Data

```bash
NS=mxd

# Delete old BPN mappings
kubectl exec -n $NS deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c "
DELETE FROM edc_did_entries 
WHERE bpn IN ('BPNL00000003AYRE', 'BPNL00000003AZ4L', 'BPNL000000000001', 'BPNL000000000002');
"

# Restart BDRS to clear cache
kubectl rollout restart -n $NS deploy/bdrs-server
kubectl rollout status -n $NS deploy/bdrs-server --timeout=60s
```

### Step 3: Re-Seed BDRS with Correct Mappings

#### Option A: Using Postman GUI
1. Open "MXD Management API Seed" collection
2. Run folder: "SeedBDRS"
3. Verify all 3 requests succeed (Alice, Bob, Trudy)

#### Option B: Using Newman CLI
```bash
cd /home/etri_lee/tutorial-resources/mxd

newman run "MXD Management API Seed.postman_collection.json" \
  --folder "SeedBDRS" \
  -e "MXD-Local-FIXED.postman_environment.json" \
  --env-var "BDRS_MGMT_URL=http://localhost/bdrs/management" \
  --env-var "ALICE_BPN=BPNL000000000001" \
  --env-var "BOB_BPN=BPNL000000000002" \
  --env-var "ALICE_DID=did:web:alice-ih%3A7083:alice" \
  --env-var "BOB_DID=did:web:bob-ih%3A7083:bob"
```

### Step 4: Verify BDRS Database

```bash
NS=mxd

kubectl exec -n $NS deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c "
SELECT bpn, did 
FROM edc_did_entries 
ORDER BY bpn;
"
```

**Expected Output:**
```
       bpn        |              did               
------------------+--------------------------------
 BPNL000000000001 | did:web:alice-ih%3A7083:alice
 BPNL000000000002 | did:web:bob-ih%3A7083:bob
 BPNL000000000003 | did:web:trudy-ih%3A7083:trudy
```

### Step 5: Monitor BDRS Logs

```bash
NS=mxd

# Watch for VP verification errors (should NOT appear anymore)
kubectl logs -n $NS deploy/bdrs-server --follow | grep -i "token verification"
```

**Success:** No "Token verification failed" messages appear after 1-2 minutes.

### Step 6: Test Contract Negotiation

#### Option A: Using Postman GUI
1. Open "MXD Service APIs" collection
2. Run folder: "Example Sequence"
3. Verify all requests succeed:
   - ✅ get cached catalog (200 OK)
   - ✅ initiate negotiation (200 OK)
   - ✅ get all negotiations (200 OK, status: FINALIZED)
   - ✅ start transfer (200 OK)
   - ✅ get EDRs (200 OK)
   - ✅ Download Data (200 OK)

#### Option B: Using curl
```bash
# Step 1: Alice requests Bob's catalog
curl -X POST http://localhost/alice/management/v3/catalog/request \
  -H "x-api-key: password" \
  -H "Content-Type: application/json" \
  -d '{
    "@context": {"edc": "https://w3id.org/edc/v0.0.1/ns/"},
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://bob-tractusx-connector-controlplane:8084/api/v1/dsp",
    "protocol": "dataspace-protocol-http"
  }'

# Should return catalog with assets (not 401 error!)
```

### Step 7: Verify Alice Logs

```bash
NS=mxd

# Check Alice connector logs (should NOT show BDRS errors)
kubectl logs -n $NS deploy/alice-tractusx-connector-controlplane --tail=50 | grep -i bdrs
```

**Success:** No "Could not obtain data from BDRS" or "401 Unauthorized" messages.

## 🎯 Success Criteria

| Check | Before Fix | After Fix |
|-------|-----------|-----------|
| BDRS BPN mapping | ❌ `did:web:alice-controlplane` | ✅ `did:web:alice-ih%3A7083:alice` |
| BDRS VP verification | ❌ "Token verification failed" | ✅ No errors |
| Alice→BDRS auth | ❌ 401 Unauthorized | ✅ 200 OK |
| Contract negotiation | ❌ Stuck in REQUESTED | ✅ Progresses to FINALIZED |
| Data transfer | ❌ Never starts | ✅ Completes successfully |

## 🔍 Troubleshooting

### Issue: BDRS still shows "Token verification failed"

**Check 1:** Verify BPN mappings were updated
```bash
kubectl exec -n mxd deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c "
SELECT * FROM edc_did_entries WHERE bpn='BPNL000000000001';
"
```
Should show `did:web:alice-ih%3A7083:alice` (not `alice-controlplane`)

**Check 2:** Restart connectors to refresh DID caches
```bash
kubectl rollout restart -n mxd deploy/alice-tractusx-connector-controlplane
kubectl rollout restart -n mxd deploy/bob-tractusx-connector-controlplane
```

**Check 3:** Test DID resolution from BDRS pod
```bash
BDRS_POD=$(kubectl get pod -n mxd -l app=bdrs-server -o name | head -1)
kubectl exec -n mxd $BDRS_POD -- curl -s http://alice-ih:7083/alice/.well-known/did.json
```
Should return DID document with `id: "did:web:alice-ih%3A7083:alice"`

### Issue: Catalog request returns 404

**Cause:** Wrong DSP endpoint URL

**Fix:** Verify DSP endpoint in request:
```json
"counterPartyAddress": "http://bob-tractusx-connector-controlplane:8084/api/v1/dsp"
```
Note the `/v1/` in the path!

### Issue: Contract negotiation stuck in REQUESTED

**Cause:** BDRS authentication still failing

**Fix:** Check BDRS logs for specific error:
```bash
kubectl logs -n mxd deploy/bdrs-server --tail=100 | grep -i error
```

## 📚 Reference Files

- ✅ `MXD Management API Seed.postman_collection.json` - Fixed collection
- ✅ `MXD Service APIs.postman_collection.json` - Fixed collection
- ✅ `MXD-Local-FIXED.postman_environment.json` - Fixed environment
- 📄 `POSTMAN_FIXES_SUMMARY.md` - Detailed explanation of issues
- 🔧 `APPLY_FIXES.md` - This file

## 🆘 Still Having Issues?

1. Check `/home/etri_lee/tutorial-resources/mxd/debug_progress.md` for debugging history
2. Review `POSTMAN_FIXES_SUMMARY.md` for technical deep dive
3. Verify all terraform variables match:
   ```bash
   grep -E "alice-did|alice-bpn" alice_variables.tf
   grep -E "bob-did|bob-bpn" bob_variables.tf
   ```
4. Ensure issuer DID document has `assertionMethod`:
   ```bash
   curl http://localhost/.well-known/did.json | jq '.assertionMethod'
   ```
   Should return: `["did:web:dataspace-issuer#key-1"]`

