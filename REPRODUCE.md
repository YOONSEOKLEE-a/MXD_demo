# Rebuild This MXD Demo on a New Machine

This guide rebuilds the lab environment from scratch for a reproducible demo.
It is optimized for clarity and a fast, working transfer demo, not production hardening.

Tested on: Ubuntu 22.04 (WSL2). Other Linux environments should work similarly.

## Essential vs demo-only

Essential (core EDC flow):
- Terraform deployment of connectors, IdentityHub, Vault, Postgres.
- Catalog request -> contract negotiation -> transfer (EDR wraps these but does not skip them).
- Data fetch via proxy or provider data plane.

Demo-only shortcuts:
- Use EDR API to reduce manual steps.
- Seed assets/policies/contracts via Postman collection.
- Use port-forwarding for access (no ingress controller required).

## Prerequisites

- JDK 17+ and JAVA_HOME set
- Docker (or compatible container runtime)
- kubectl
- KinD
- Terraform 1.0+
- Optional: Postman, jq

## 1) Clone repositories

```bash
git clone https://github.com/YOONSEOKLEE-a/MXD_demo.git
cd MXD_demo
```

The runtime images are built from a sibling repo:

```bash
git clone <YOUR_MXD_RUNTIMES_REPO_URL> ../mxd-runtimes
```

(This repo contains the EDC runtime images built for this demo.)

## 2) Create a local cluster (KinD)

```bash
kind create cluster -n mxd --config kind.config.yaml
```

## 3) Build runtime images

```bash
cd ../mxd-runtimes
./gradlew dockerize
```

## 4) Load images into KinD

```bash
kind load docker-image --name mxd data-service-api tx-identityhub tx-catalog-server tx-issuerservice
```

## 5) Deploy with Terraform

```bash
cd ../mxd
terraform init
terraform apply
```

Expected result:
- All pods in namespace `mxd` are Running
- No CrashLoopBackOff

ARM note (Apple Silicon):

```bash
terraform apply -var="useSVE=true"
```

## 6) Start port forwards

```bash
./port-forward.sh
```

Expected access points:
- Alice control plane: http://localhost:8282
- Bob control plane: http://localhost:8283

Health checks:

```bash
curl -sS http://localhost:8282/health/api/check/liveness | jq
curl -sS http://localhost:8283/health/api/check/liveness | jq
```

## 7) Seed demo data (Postman)

Import and run:
- `postman/mxd-seed.json`
- Optional: `MXD-Local.postman_environment.json`

This creates assets, policies, and contract definitions needed for the demo.

## 8) Run the demo

Follow the fast EDR flow in:
- `DEMO.md`

## Known blocker (documented)

Negotiation can stall in `REQUESTED`/`TERMINATED` due to BDRS VP validation or STS alignment issues.
See `debug_progress.md` and `APPLY_FIXES.md` for the investigation trail.

We are **not** applying any config bypass in this guide.

## Optional recovery scripts (manual, demo-only)

These exist to recover or stabilize the demo environment when negotiation fails:
- `setup_vaults.sh`
- `fix_all_vaults.sh`
- `setup_db.sh`
- `setup_db_alice.sh`

Run them only if you know why you need them. They are not part of the default rebuild.
