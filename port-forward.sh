#!/bin/bash
NS=mxd

# 기존 포트포워딩 프로세스 종료
pkill -f "kubectl port-forward" 2>/dev/null
sleep 1

echo "=== Starting port forwards ==="

# Alice Connector (8282 -> 8081)
kubectl port-forward svc/alice-tractusx-connector-controlplane -n $NS 8282:8081 &
echo "✓ Alice Connector: localhost:8282"

# Bob Connector (8283 -> 8081)
kubectl port-forward svc/bob-tractusx-connector-controlplane -n $NS 8283:8081 &
echo "✓ Bob Connector: localhost:8283"

# BDRS Server (8285 -> 8081)
kubectl port-forward svc/bdrs-server -n $NS 8285:8081 &
echo "✓ BDRS Server: localhost:8285"

# Dataspace Issuer Service - Identity API (8286 -> 10015)
kubectl port-forward svc/dataspace-issuer-service -n $NS 8286:10015 &
echo "✓ Issuer Service (Identity): localhost:8286"

# Bob Vault (8200 -> 8200)
kubectl port-forward svc/bob-vault -n $NS 8200:8200 &
echo "✓ Bob Vault: localhost:8200"

# Issuer Service - Issuer Admin API (10013 -> 10013)
kubectl port-forward svc/dataspace-issuer-service -n $NS 10013:10013 &
echo "✓ Issuer Service (Issuer Admin): localhost:10013"

# Alice IdentityHub - Credentials API (7082 -> 7082)
kubectl port-forward svc/alice-ih -n $NS 7082:7082 &
echo "✓ Alice IH (Credentials): localhost:7082"

# Alice IdentityHub - Identity API (7081 -> 7081)
kubectl port-forward svc/alice-ih -n $NS 7081:7081 &
echo "✓ Alice IH (Identity): localhost:7081"

# Bob IdentityHub - Credentials API (7092 -> 7082)
kubectl port-forward svc/bob-ih -n $NS 7092:7082 &
echo "✓ Bob IH (Credentials): localhost:7092"

# Bob IdentityHub - Identity API (7091 -> 7081)
kubectl port-forward svc/bob-ih -n $NS 7091:7081 &
echo "✓ Bob IH (Identity): localhost:7091"

echo ""
echo "=== All port forwards started ==="
echo "Press Ctrl+C to stop all"

wait
