#!/bin/bash
set -e

# -------------------------------------------------------
# [EDC Tutorial DB Initializer]
# Bob STS DB에 클라이언트 정보를 강제로 주입합니다.
# (401 invalid_client 해결용)
# -------------------------------------------------------

NS=mxd
PGSVC="bob-postgres-service"

echo ">>> 🐘 Bob Postgres DB에 STS Client 정보 주입 중..."

kubectl run -n $NS tmppsql-fix --rm -i --restart=Never --image=postgres:16 -- bash -lc "
set -e
export PGPASSWORD=bob

psql -h ${PGSVC} -U bob -d bob -P pager=off -v ON_ERROR_STOP=1 <<'SQL'
-- 1) Bob STS client 등록 (없을 때만 INSERT)
INSERT INTO public.edc_sts_client
(id, client_id, did, name, secret_alias, private_key_alias, public_key_reference, created_at)
SELECT
  'bob-sts-client',
  'did:web:bob-ih%3A7083:bob',
  'did:web:bob-ih%3A7083:bob',
  'bob',
  'did:web:bob-ih%3A7083:bob-sts-client-secret',
  'key-1',
  'key-1',
  (extract(epoch from now())*1000)::bigint
WHERE NOT EXISTS (
  SELECT 1 FROM public.edc_sts_client WHERE client_id='did:web:bob-ih%3A7083:bob'
);

-- 2) 결과 확인
SELECT client_id, secret_alias, private_key_alias FROM public.edc_sts_client WHERE client_id LIKE '%bob%';
SQL
"

echo ">>> ✅ DB 주입 완료."
