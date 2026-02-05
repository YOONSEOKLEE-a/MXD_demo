# MXD Postman Collections - Issues and Fixes

## Executive Summary

**ROOT CAUSE OF BDRS VP VERIFICATION FAILURE:**
The BDRS BPN directory was seeded with **wrong DIDs** - using control-plane DIDs instead of IdentityHub DIDs. This causes Alice's VP (signed by her IdentityHub) to fail verification because BDRS cannot resolve the correct DID document.

---

## Critical Issues Fixed

### 1. ❌ **BDRS BPN Mappings - WRONG DIDs** (BLOCKER)

**File:** `MXD Management API Seed.postman_collection.json`
**Location:** SeedBDRS folder → "Create Alice BPN Mapping" (line 765) and "Create Bob BPN Mapping" (line 817)

**Problem:**
```json
// WRONG - Current config
{
  "bpn": "BPNL00000003AYRE",        // ❌ Wrong BPN
  "did": "did:web:alice-controlplane"  // ❌ Wrong DID (control-plane)
}
```

**Why This Breaks Everything:**
1. Alice connector uses IdentityHub DID: `did:web:alice-ih%3A7083:alice`
2. When Alice sends VP to BDRS, the VP is signed by her IdentityHub private key
3. BDRS looks up Alice's BPN → finds `did:web:alice-controlplane` (WRONG!)
4. BDRS tries to resolve `http://alice-controlplane/.well-known/did.json` → **404 NOT FOUND**
5. **VP signature verification fails** → HTTP 401 Unauthorized
6. Contract negotiation blocked

**Fix:**
```json
// CORRECT - Fixed config
{
  "bpn": "BPNL000000000001",              // ✅ Correct BPN (from alice_variables.tf)
  "did": "did:web:alice-ih%3A7083:alice"  // ✅ Correct DID (IdentityHub)
}

{
  "bpn": "BPNL000000000002",            // ✅ Correct BPN (from bob_variables.tf)
  "did": "did:web:bob-ih%3A7083:bob"    // ✅ Correct DID (IdentityHub)
}
```

**Source of Truth:** `/home/etri_lee/tutorial-resources/mxd/alice_variables.tf` and `bob_variables.tf`

---

### 2. ❌ **DSP Endpoint URL Inconsistencies**

**File:** `MXD Service APIs.postman_collection.json`
**Location:** Multiple requests (catalog, negotiation, transfer)

**Problem:**
```json
// WRONG - Inconsistent DSP paths
"counterPartyAddress": "http://alice-controlplane:8084/api/dsp"     // Missing /v1
"counterPartyAddress": "http://alice-controlplane:8084/api/v1/dsp"  // Correct path, wrong hostname
```

**Why This Breaks:**
- Missing `/v1` → 404 Not Found (wrong API path)
- Wrong hostname → Should use full service name in K8s: `alice-tractusx-connector-controlplane`

**Fix:**
```json
// CORRECT - Consistent DSP URLs
"counterPartyAddress": "http://alice-tractusx-connector-controlplane:8084/api/v1/dsp"
```

**Affected Requests:**
- "get cached catalog" (line 53)
- "initiate negotiation" (line 84)
- "start transfer" (line 178)

**Source of Truth:** `/home/etri_lee/tutorial-resources/mxd/modules/connector/main.tf` line 115
```hcl
EDC_DSP_CALLBACK_ADDRESS = "http://${kubernetes_service.controlplane-service.metadata.0.name}:8084/api/v1/dsp"
```

---

### 3. ❌ **Wrong API Endpoint for Credential Creation**

**File:** `MXD Management API Seed.postman_collection.json`
**Location:** SeedIH folder → "Create Membership Credential" (line 1063)

**Problem:**
```json
// WRONG - Uses catalog API instead of IdentityHub credentials API
"url": {
  "raw": "http://localhost:8286/management/v3/catalog/dataset/request"
}
```

**Why This Breaks:**
- Tries to create a credential using the catalog API (wrong service)
- Should use IdentityHub's credentials API

**Fix:**
```json
// CORRECT - Uses IdentityHub credentials API
"url": {
  "raw": "{{ALICE_IH_URL}}/api/identity/v1alpha/participants/{{PARTICIPANT_CONTEXT_ID_BASE64}}/credentials"
}
```

**Pattern for Alice:** `http://localhost:7081/api/identity/v1alpha/participants/ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U=/credentials`
**Pattern for Bob:** `http://localhost:7091/api/identity/v1alpha/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/credentials`

---

### 4. ⚠️ **Empty Environment Variables**

**File:** `MXD-Local.postman_environment.json`

**Problem:**
All values are empty strings - requests will fail without proper configuration.

**Fix:** See `MXD-Local-FIXED.postman_environment.json` with populated values:
- `ALICE_MANAGEMENT_URL`: `http://localhost/alice/management`
- `BOB_MANAGEMENT_URL`: `http://localhost/bob/management`
- `BDRS_MGMT_URL`: `http://localhost/bdrs/management`
- `ALICE_BPN`: `BPNL000000000001`
- `BOB_BPN`: `BPNL000000000002`
- `ALICE_DID`: `did:web:alice-ih%3A7083:alice`
- `BOB_DID`: `did:web:bob-ih%3A7083:bob`
- `ALICE_IH_URL`: `http://localhost:7081`
- `BOB_IH_URL`: `http://localhost:7091`

---

## How to Apply Fixes

### Quick Fix (Manual)

**1. Fix BDRS BPN Mappings (CRITICAL):**

In `MXD Management API Seed.postman_collection.json`, find the "SeedBDRS" folder and update:

**Alice BPN Mapping** (around line 765):
```json
{
  "bpn": "BPNL000000000001",
  "did": "did:web:alice-ih%3A7083:alice"
}
```

**Bob BPN Mapping** (around line 817):
```json
{
  "bpn": "BPNL000000000002",
  "did": "did:web:bob-ih%3A7083:bob"
}
```

**2. Fix DSP Endpoints:**

In `MXD Service APIs.postman_collection.json`, find and replace:
- `http://alice-controlplane:8084/api/dsp` → `http://alice-tractusx-connector-controlplane:8084/api/v1/dsp`
- `http://bob-tractusx-connector-controlplane:8084/api/v1/dsp` (Bob's endpoint - keep as is)

**3. Use Fixed Environment:**

Import `MXD-Local-FIXED.postman_environment.json` into Postman and select it as active environment.

**4. Re-run Seed Collection:**

```bash
# Delete existing BDRS entries
kubectl exec -n mxd deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c "DELETE FROM edc_did_entries WHERE bpn IN ('BPNL00000003AYRE', 'BPNL00000003AZ4L', 'BPNL000000000001', 'BPNL000000000002');"

# Re-run seed collection with fixes
newman run "MXD Management API Seed.postman_collection.json" \
  --folder "SeedBDRS" \
  -e "MXD-Local-FIXED.postman_environment.json"
```

**5. Verify Fix:**

```bash
# Check BDRS database
kubectl exec -n mxd deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c "SELECT bpn, did FROM edc_did_entries;"

# Expected output:
# BPNL000000000001 | did:web:alice-ih%3A7083:alice
# BPNL000000000002 | did:web:bob-ih%3A7083:bob

# Check BDRS logs (should stop showing VP verification errors)
kubectl logs -n mxd deploy/bdrs-server --tail=50 | grep "Token verification failed"
# Expected: No output (errors stopped)
```

---

## Expected Outcome After Fix

### Before Fix:
```
[BDRS] WARNING Error validating BDRS client VP: Token verification failed
[Alice] SEVERE Could not obtain data from BDRS server: code: 401, message: Unauthorized
[Negotiation] Status: REQUESTED (stuck, never progresses)
```

### After Fix:
```
[BDRS] INFO Successfully validated VP from did:web:alice-ih%3A7083:alice
[Alice] DEBUG Successfully retrieved DID for BPN BPNL000000000002 from BDRS
[Negotiation] Status: REQUESTED → AGREED → FINALIZED
[Transfer] Status: STARTED → COMPLETED
```

---

## Why This Happened

The Postman collection was likely created before the IdentityHub DIDs were finalized. The seed script used placeholder values (`did:web:alice-controlplane`, `did:web:bob-controlplane`) that don't match the actual terraform configuration.

**Lesson:** Always verify seeded data against terraform variable definitions (`alice_variables.tf`, `bob_variables.tf`) as the single source of truth.

---

## Verification Commands

```bash
# 1. Check terraform variables (source of truth)
grep -E "alice-did|alice-bpn" /home/etri_lee/tutorial-resources/mxd/alice_variables.tf
grep -E "bob-did|bob-bpn" /home/etri_lee/tutorial-resources/mxd/bob_variables.tf

# 2. Verify BDRS database contents
kubectl exec -n mxd deploy/bdrs-postgres -- psql -U bdrs -d bdrs -c \
  "SELECT bpn, did FROM edc_did_entries ORDER BY bpn;"

# 3. Test DID resolution from BDRS pod
BDRS_POD=$(kubectl get pod -n mxd -l app=bdrs-server -o name | head -1)
kubectl exec -n mxd $BDRS_POD -- curl -s http://alice-ih:7083/alice/.well-known/did.json | jq '.id'
# Expected: "did:web:alice-ih%3A7083:alice"

# 4. Test contract negotiation
newman run "MXD Service APIs.postman_collection.json" \
  --folder "Example Sequence" \
  -e "MXD-Local-FIXED.postman_environment.json"
```

---

## Files Modified

- ✅ Created: `MXD-Local-FIXED.postman_environment.json`
- ⚠️ Manual fix required: `MXD Management API Seed.postman_collection.json` (BPN mappings)
- ⚠️ Manual fix required: `MXD Service APIs.postman_collection.json` (DSP endpoints)

---

## Technical Deep Dive

### How BDRS VP Verification Works

1. **Alice Initiates Contract Negotiation:**
   - Alice connector calls BDRS to resolve Bob's BPN → DID
   - BDRS requires VP authentication (IATP)

2. **Alice Creates VP:**
   - Alice's IdentityHub generates VP containing:
     - `iss`: `did:web:alice-ih%3A7083:alice`
     - `sub`: `did:web:alice-ih%3A7083:alice`
     - `vc`: MembershipCredential signed by `did:web:dataspace-issuer`
   - VP is signed with Alice's IdentityHub private key

3. **BDRS Validates VP:**
   ```
   Step 1: Extract issuer from VP → did:web:alice-ih%3A7083:alice
   Step 2: Look up Alice's BPN in database → BPNL000000000001
   Step 3: Look up DID for BPN → [THIS IS WHERE IT FAILS!]
           Database returns: did:web:alice-controlplane (WRONG!)
   Step 4: Try to resolve http://alice-controlplane/.well-known/did.json
           Result: 404 NOT FOUND
   Step 5: VP verification FAILS → 401 Unauthorized
   ```

**With Fix:**
```
Step 3: Look up DID for BPN → did:web:alice-ih%3A7083:alice (CORRECT!)
Step 4: Resolve http://alice-ih:7083/alice/.well-known/did.json
        Result: 200 OK (DID document with public key)
Step 5: Verify VP signature with public key → SUCCESS ✅
```

---

## Contact & Support

If issues persist after applying fixes:
1. Check `debug_progress.md` for historical context
2. Verify all services are healthy: `kubectl get pods -n mxd`
3. Check BDRS logs: `kubectl logs -n mxd deploy/bdrs-server --tail=100`
4. Verify DID resolution: Test all DIDs are reachable from BDRS pod
