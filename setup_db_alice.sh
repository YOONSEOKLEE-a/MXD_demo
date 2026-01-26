#!/bin/bash
set -e

# -------------------------------------------------------
# [EDC Tutorial DB Initializer - ALICE]
# Alice STS DB에 클라이언트 정보를 강제로 주입합니다.
# (401 invalid_client 해결용)
# -------------------------------------------------------

NS=mxd
PGSVC="alice-postgres-service"

echo ">>> 🐘 Alice Postgres DB에 STS Client 정보 주입 중..."

kubectl run -n $NS tmppsql-fix-alice --rm -i --restart=Never --image=postgres:16 -- bash -lc "
set -e
export PGPASSWORD=alice

psql -h ${PGSVC} -U alice -d alice -P pager=off -v ON_ERROR_STOP=1 <<'SQL'
-- 1) Alice STS client 등록 (없을 때만 INSERT)
INSERT INTO public.edc_sts_client
(id, client_id, did, name, secret_alias, private_key_alias, public_key_reference, created_at)
SELECT
  'alice-sts-client',
  'did:web:alice-ih%3A7083:alice',
  'did:web:alice-ih%3A7083:alice',
  'alice',
  'did:web:alice-ih%3A7083:alice-sts-client-secret',
  'key-1',
  'key-1',
  (extract(epoch from now())*1000)::bigint
WHERE NOT EXISTS (
  SELECT 1 FROM public.edc_sts_client WHERE client_id='did:web:alice-ih%3A7083:alice'
);

-- 2) 결과 확인
SELECT client_id, secret_alias, private_key_alias FROM public.edc_sts_client WHERE client_id LIKE '%alice%';
SQL
"

echo ">>> ✅ Alice DB 주입 완료."
