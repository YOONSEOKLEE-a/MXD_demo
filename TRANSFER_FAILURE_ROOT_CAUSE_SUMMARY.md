# MXD_demo Transfer Failure Root Cause Summary

## Scope

이 문서는 `/mnt/d/MXD_demo` 안의 파일만 읽고 정리한 분석 문서다.
실행 결과를 새로 만들지 않았고, 아래 자료를 근거로 실패 원인을 요약했다.

- `debug_progress.md`
- `APPLY_FIXES.md`
- `POSTMAN_FIXES_SUMMARY.md`
- `MXD Management API Seed.postman_collection.json`
- `MXD Service APIs.postman_collection.json`
- `seed_data.tf`
- `modules/*`

## Bottom Line

이 폴더에서 transfer가 실패한 원인은 하나가 아니라, 시점에 따라 겹쳐 있었다.

가장 가능성이 큰 흐름은 아래 순서다.

1. 초기에는 `BDRS + DID resolution` 문제가 실제 blocker였다.
2. 그 문제를 일부 고친 뒤에는 `STS / Presentation Query / scope` 정렬 문제가 남았다.
3. 그와 별개로, 현재 폴더 스냅샷 기준으로는 `수동 Postman transfer 요청 자체가 일관되지 않아서` transfer 검증이 계속 실패할 가능성이 높다.
4. Terraform job 리소스들이 완료까지 기다리는 구조라, 실제 서비스는 일부 떠 있어도 `terraform apply`가 실패처럼 보였을 가능성이 크다.

즉, 이 폴더의 실패는 "한 번의 단일 버그"라기보다
`IAM/credential chain 문제 + 수동 요청 불일치 + 배포 대기 semantics`
가 겹친 케이스로 보는 게 맞다.

## 1. Historical Primary Blocker: BDRS / DID / VP Verification

`debug_progress.md` 앞부분의 핵심 메시지는 매우 일관적이다.

- `BDRS 401 VP validation`
- `DID endpoint 204/404`
- `Presentation Query 404/401`
- `catalog crawl blocked`

특히 다음 서술이 반복된다.

- `debug_progress.md` 초반 요약:
  - BDRS directory endpoint는 존재하지만 VP auth가 실패한다고 기록
  - Alice outbound BDRS auth가 immediate next action으로 적혀 있음
- 중간 단계:
  - Bob/Alice DID endpoint가 `204 No Content` 또는 `404`
  - BDRS가 DID를 못 풀어서 JWT/VP 검증 실패
  - Contract negotiation / catalog crawl이 막힘
- 후반 단계:
  - DID는 어느 정도 고쳤지만 STS/PQ scope 문제로 여전히 negotiation 실패

즉, 실패 당시 실제 첫 번째 큰 원인은
`BDRS가 올바른 DID를 확인하지 못해 VP를 검증하지 못한 것`
으로 보는 게 맞다.

## 2. What the Snapshot Shows Now: BDRS Seed Looks Mostly Fixed

현재 스냅샷의 `MXD Management API Seed.postman_collection.json`을 보면,
문서에서 "이미 고쳤다"고 적은 BDRS BPN mapping은 실제로도 반영돼 있다.

- Alice:
  - `BPNL000000000001`
  - `did:web:alice-ih%3A7083:alice`
- Bob:
  - `BPNL000000000002`
  - `did:web:bob-ih%3A7083:bob`

즉, `APPLY_FIXES.md`와 `POSTMAN_FIXES_SUMMARY.md`가 말하는
"BDRS가 control-plane DID를 보고 있어서 틀렸다"는 문제는
이 폴더의 현재 스냅샷 기준으로는 이미 일부 수정된 상태다.

그래서 이 폴더를 지금 다시 본다면,
`BDRS mapping`은 "과거 root cause"였고,
`현재 스냅샷에서 바로 눈에 띄는 blocker`는 따로 있다.

## 3. Current Snapshot Blocker: Manual Transfer Requests Are Inconsistent

현재 폴더에서 가장 직접적으로 보이는 문제는
`MXD Service APIs.postman_collection.json` 안의 수동 transfer 흐름이
서로 다른 시점의 정보를 섞어 쓰고 있다는 점이다.

### 3.1 Negotiation request is malformed and stale

`MXD Service APIs.postman_collection.json`의 `initiate negotiation` 요청은 문제점이 여러 개다.

- raw body가 `'{`로 시작한다.
  - JSON 앞에 작은따옴표가 붙어 있어 request body 자체가 깨질 수 있다.
- `counterPartyAddress`가 `http://alice-controlplane:8084/api/v1/dsp`
  - 현재 다른 파일들은 `alice-tractusx-connector-controlplane` 또는 service hostname 기반을 쓰는데,
    여기만 old hostname이 남아 있다.

이 요청은 negotiation 단계 자체를 불안정하게 만든다.

### 3.2 Transfer request points to Bob, not Alice

같은 컬렉션의 `start transfer` 요청은 더 직접적으로 틀려 있다.

- `counterPartyAddress`가 `http://bob-tractusx-connector-controlplane:8084/api/v1/dsp`
- `counterPartyParticipantId`도 Bob (`BPNL000000000002`)
- `assetId`가 `"1"`

하지만 실제 seeded asset 패턴은 `asset-1`, `asset-2`, `asset-3`이고,
Bob이 가져와야 하는 대상은 Alice다.

즉 이 transfer request는
`Bob -> Alice`가 아니라 사실상 `Bob -> Bob`처럼 잘못 구성되어 있다.
이 상태면 negotiation이 되더라도 transfer는 정상 완료되기 어렵다.

## 4. Current Snapshot Blocker: Alice SeedIH Still Advertises an Old DSP Endpoint

`MXD Management API Seed.postman_collection.json`의 participant creation payload도 비대칭이 있다.

- Bob participant의 `ProtocolEndpoint`
  - `http://bob-tractusx-connector-controlplane:8084/api/v1/dsp`
- Alice participant의 `ProtocolEndpoint`
  - `http://alice-controlplane:8084/api/dsp`

즉 Alice만 아직 old hostname + old path 조합을 쓰고 있다.

이건 단순 cosmetic 문제가 아니라,
상대측이 Alice의 participant metadata를 보고 DSP endpoint를 참조하는 흐름에서
오래된 주소를 보게 만들 수 있다.

정리하면, BDRS mapping은 고쳤더라도
Alice participant metadata가 여전히 stale하면
negotiation / catalog / transfer 중 하나는 다시 꼬일 수 있다.

## 5. Terraform Could Have Looked "Failed" Even When the System Was Partially Up

`seed_data.tf`, `modules/connector/azurite-container.tf`, `modules/minio/s3bucket_job.tf`를 보면
여러 `kubernetes_job` 리소스가 있다.

이 구조의 특징은:

- seed/newman job
- azurite init job
- minio bucket create job
- minio upload job

같은 초기화 job들이 느리거나 image pull이 오래 걸리면,
실제 런타임 pod는 많이 떠 있어도 `terraform apply`는 실패처럼 보일 수 있다는 점이다.

즉 네가 당시 "transfer 시도 전에 이미 deployment가 실패했다"고 느꼈다면,
그중 일부는 진짜 connector failure가 아니라
`job completion wait 때문에 apply가 먼저 실패한 것`
일 가능성이 크다.

## 6. The Folder Is Already a Local Fork, Not an Upstream-As-Is Snapshot

이 폴더는 upstream tutorial-resources를 그대로 둔 복사본이 아니라,
이미 로컬 수정이 많이 들어간 포크 상태다.

예:

- Helm / Kubernetes provider 버전이 명시적으로 고정돼 있음
- connector chart version이 `0.11.2`
- `vault_seed_secrets`, `controlplane_env` merge 등 로컬 커스터마이즈가 존재
- Postman collections도 backup과 fixed 문서가 같이 존재

즉 이 폴더에서 실패 원인을 볼 때는
`upstream MXD가 왜 실패했는가`
보다는
`이 로컬 포크에서 수동 transfer 검증 도구와 실제 배포 설정이 서로 얼마나 어긋났는가`
를 봐야 한다.

## 7. Most Likely Failure Story

현재 파일들을 종합하면, 가장 가능성 높은 실패 스토리는 이렇다.

1. 원래는 BDRS가 잘못된 DID를 보고 있어서 VP 검증이 실패했다.
2. 그 문제를 고치려는 과정에서 Postman seed와 일부 설정은 수정됐다.
3. 하지만 manual transfer collection은 끝까지 일관되게 정리되지 않았다.
4. 그 결과:
   - 일부 단계는 성공했을 수 있어도
   - negotiation payload / transfer payload / participant endpoint metadata가 어긋나서
   - transfer E2E는 계속 실패하거나 이상한 상태에 빠졌을 가능성이 높다.

## 8. What Was Already Fixed vs What Still Looked Wrong

### Already fixed in this snapshot

- BDRS BPN -> DID mapping
- Bob participant ProtocolEndpoint
- 일부 environment / fixed Postman files
- connector chart/provider pinning

### Still looked wrong in this snapshot

- Alice participant ProtocolEndpoint still stale
- negotiation raw JSON malformed
- transfer request points to Bob instead of Alice
- asset id uses `1` instead of `asset-1`
- job-based init resources make apply look failed before transfer validation

## Final Assessment

이 폴더의 transfer 실패 원인을 한 줄로 요약하면:

`처음에는 BDRS/DID/VP 인증 체인이 깨져 있었고, 그걸 고친 뒤에도 수동 Postman transfer 요청과 participant endpoint 정보가 일관되게 정리되지 않아 transfer 검증이 계속 실패한 상태`

즉:

- 과거의 주 원인: `BDRS / DID / STS / PQ`
- 현재 스냅샷에서 바로 보이는 원인: `stale endpoint + malformed/manual transfer payload`

둘 다 있었다고 보는 게 가장 정확하다.
