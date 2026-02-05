# 10-Minute EDR Demo (Portfolio)

This walkthrough is optimized for a fast, reproducible demo of catalog -> negotiation -> transfer using the EDR API.
It prioritizes clarity over production hardening.

## What is essential vs demo-only

Essential EDC flow:
- Terraform deployment of connectors, IdentityHub, Vault, Postgres.
- Catalog request (consumer -> provider).
- Contract negotiation and transfer (EDR wraps these but does not skip them).
- Data fetch (via proxy or provider data plane).

Demo-only shortcuts:
- Use EDR API to collapse negotiation + transfer into fewer manual steps.
- Use consumer proxy for data fetch (simpler than direct data-plane calls).
- Pre-seed assets/policies/contracts via Postman collections.

## Prereqs (assumed already installed)

- KinD or equivalent Kubernetes runtime
- Terraform
- kubectl
- Postman (recommended for seeding and validation)

## 0) Deploy (2-3 minutes)

```bash
terraform init
terraform apply
```

## 1) Port-forward (1 minute)

```bash
./port-forward.sh
```

Expected ports:
- Alice control plane: `http://localhost:8282`
- Bob control plane: `http://localhost:8283`

Quick health check:

```bash
curl -sS http://localhost:8282/health/api/check/liveness | jq
curl -sS http://localhost:8283/health/api/check/liveness | jq
```

## 2) Seed demo data (1-2 minutes)

Use Postman collection `postman/mxd-seed.json` and run all requests.

This creates assets, policies, and contract definitions used by the demo.

## 3) Catalog request (1 minute)

Run from your host (Bob as consumer):

```bash
cat <<'JSON' | curl -sS -X POST "http://localhost:8283/management/v3/catalog/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" -d @- | jq
{
  "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
  "counterPartyAddress":"http://alice-tractusx-connector-controlplane.mxd.svc.cluster.local:8084/api/v1/dsp",
  "protocol":"dataspace-protocol-http"
}
JSON
```

From the response, pick one dataset and capture:
- `dcat:dataset[*].odrl:hasPolicy.@id` (offer id)
- `dcat:dataset[*].@id` (asset id)
- `dcat:service[0].dcat:endpointUrl` (provider connector address)
- `dcat:service[0].tx:participantId` (provider id)

## 4) Start EDR negotiation (1-2 minutes)

```bash
cat <<'JSON' | curl -sS -X POST "http://localhost:8283/management/v3/edrs" \
  -H "Content-Type: application/json" -H "x-api-key: password" -d @- | jq
{
  "@context": {"odrl":"http://www.w3.org/ns/odrl/2/"},
  "@type": "NegotiationInitiateRequestDto",
  "counterPartyAddress": "<PROVIDER_PROTOCOL_URL>",
  "protocol": "dataspace-protocol-http",
  "counterPartyId": "<PROVIDER_ID>",
  "providerId": "<PROVIDER_ID>",
  "offer": {
    "offerId": "<OFFER_ID>",
    "assetId": "<ASSET_ID>",
    "policy": { "@type": "odrl:Set" }
  }
}
JSON
```

The response returns a negotiation id (`@id`).

## 5) Fetch EDR and download data (2-3 minutes)

Wait ~20-60s, then list EDRs and fetch the latest transfer id:

```bash
curl -sS "http://localhost:8283/management/v3/edrs/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' | jq
```

Option A (demo shortcut): consumer proxy

```bash
cat <<'JSON' | curl -sS -X POST "http://localhost:8283/proxy/aas/request" \
  -H "Content-Type: application/json" -H "x-api-key: password" -d @- | jq
{
  "assetId": "<ASSET_ID>",
  "providerId": "<PROVIDER_ID>"
}
JSON
```

Option B (direct): get EDR data address

```bash
curl -sS "http://localhost:8283/management/v3/edrs/<TRANSFER_PROCESS_ID>/dataaddress" \
  -H "x-api-key: password" | jq
```

Use the returned `edc:endpoint` and `edc:authCode` to fetch data directly.

## Known blocker (documented)

Negotiation can stall in `REQUESTED`/`TERMINATED` if BDRS VP validation or STS alignment fails.
See `debug_progress.md` and `APPLY_FIXES.md` for the investigation trail.

We are **not** applying any config bypasses in this demo guide.
