#
#  Copyright (c) 2024 Bayerische Motoren Werke Aktiengesellschaft (BMW AG)
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  SPDX-License-Identifier: Apache-2.0
#
#  Contributors:
#      Bayerische Motoren Werke Aktiengesellschaft (BMW AG) - initial API and implementation
#

# Second connector
module "bob-connector" {
  depends_on           = [module.azurite]
  source               = "./modules/connector"
  humanReadableName    = var.bob-humanReadableName
  namespace            = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId        = var.bob-bpn
  participantContextId = var.bob-did
  database-host        = local.bob-postgres.database-host
  database-name        = local.databases.bob.database-name
  database-credentials = {
    user     = local.databases.bob.database-username
    password = local.databases.bob.database-password
  }
  dcp-config = {
    id                     = var.bob-did
    sts_token_url          = "http://bob-ih:7084/api/sts/token"
    sts_client_id          = var.bob-did
    sts_clientsecret_alias = "bob-sts-client-secret"
  }
  dataplane = {
    privatekey-alias = "${var.bob-did}#signing-key-1"
    publickey-alias  = "${var.bob-did}#signing-key-1"
  }

  azure-account-name    = var.bob-azure-account-name
  azure-account-key     = local.bob-azure-key-base64
  azure-account-key-sas = var.bob-azure-key-sas
  azure-url             = module.azurite.azurite-url
  ingress-host          = var.bob-ingress-host
  minio-config = {
    username = module.bob-minio.minio-username
    password = module.bob-minio.minio-password
    url      = module.bob-minio.minio-url
  }
  useSVE = var.useSVE
  controlplane_env = {
    "TRACTUSX_EDC_PARTICIPANT_BPN"                    = var.bob-bpn
    "TX_EDC_IAM_IATP_BDRS_SERVER_URL"                 = "http://bdrs-server:8082/api/directory"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_ALIAS"        = "org.eclipse.tractusx.vc.type"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_TYPE"         = "MembershipCredential"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_OPERATION"    = "read"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_ALIAS"        = "org.eclipse.tractusx.vc.type"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_TYPE"         = "DataExchangeGovernanceCredential"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_OPERATION"    = "read"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_ALIAS"        = "org.eclipse.tractusx.vc.type"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_TYPE"         = "FrameworkAgreementCredential"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_OPERATION"    = "read"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_ALIAS"        = "org.eclipse.tractusx.vc.type"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_TYPE"         = "UsagePurposeCredential"
    "EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_OPERATION"    = "read"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_ALIAS"     = "org.eclipse.tractusx.vc.type"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_TYPE"      = "MembershipCredential"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_OPERATION" = "read"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_ALIAS"     = "org.eclipse.tractusx.vc.type"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_TYPE"      = "DataExchangeGovernanceCredential"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE2_OPERATION" = "read"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_ALIAS"     = "org.eclipse.tractusx.vc.type"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_TYPE"      = "FrameworkAgreementCredential"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE3_OPERATION" = "read"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_ALIAS"     = "org.eclipse.tractusx.vc.type"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_TYPE"      = "UsagePurposeCredential"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE4_OPERATION" = "read"
    "EDC_IAM_IATP_CREDENTIALSERVICE_URL"              = "http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=="
    "EDC_IAM_IATP_PRESENTATION_QUERY_URL"             = "http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query"
    "TX_EDC_IAM_IATP_CREDENTIALSERVICE_URL"           = "http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=="
    "TX_EDC_IAM_IATP_PRESENTATION_QUERY_URL"          = "http://bob-ih:7082/api/credentials/v1/participants/ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg==/presentations/query"
    "EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER"      = "Authorization"
    "EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER"     = "Authorization"
    "TX_EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER"   = "Authorization"
    "TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER"  = "Authorization"
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_URL"                = "http://bob-ih:7084/api/sts/token"
    "EDC_IAM_IATP_STS_OAUTH_CLIENT_ID"                = var.bob-did
    "EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS"      = "bob-sts-client-secret"
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE"           = var.bob-did
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"              = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL"             = "http://bob-ih:7084/api/sts/token"
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID"             = var.bob-did
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS"   = "bob-sts-client-secret"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE"        = var.bob-did
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"           = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "EDC_IAM_STS_OAUTH_TOKEN_SCOPE"                   = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "TX_EDC_IAM_STS_OAUTH_TOKEN_SCOPE"                = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "EDC_PARTICIPANT_ID"                              = var.bob-bpn
    "EDC_PARTICIPANT_CONTEXT_ID"                      = var.bob-did
    "TX_EDC_PARTICIPANT_CONTEXT_ID"                   = var.bob-did
    "TX_EDC_PARTICIPANT_ID"                           = var.bob-bpn
    "PARTICIPANT_CONTEXT_ID_BASE64"                   = "ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=="
    "PARTICIPANT_ID_BASE64"                           = "ZGlkOndlYjpib2ItaWglM0E3MDgzOmJvYg=="
    "JAVA_TOOL_OPTIONS"                               = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=1044 -Dtx.edc.iam.iatp.default-scopes.scope1.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope1.type=MembershipCredential -Dtx.edc.iam.iatp.default-scopes.scope1.operation=read -Dtx.edc.iam.iatp.default-scopes.scope2.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope2.type=DataExchangeGovernanceCredential -Dtx.edc.iam.iatp.default-scopes.scope2.operation=read -Dtx.edc.iam.iatp.default-scopes.scope3.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope3.type=FrameworkAgreementCredential -Dtx.edc.iam.iatp.default-scopes.scope3.operation=read -Dtx.edc.iam.iatp.default-scopes.scope4.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope4.type=UsagePurposeCredential -Dtx.edc.iam.iatp.default-scopes.scope4.operation=read"
  }

  # Seed secrets for Bob vault
  vault_seed_secrets = {
    "key-1"                   = local.issuer_key_json
    "alice-sts-client-secret" = "password"
    "bob-sts-client-secret"   = "password"
    "password"                = "password"
    "api-key"                 = "password"
  }
}

module "bob-identityhub" {
  depends_on = [module.bob-connector] // depends because of the vault
  source     = "./modules/identity-hub"
  database = {
    user     = local.databases.bob.database-username
    password = local.databases.bob.database-password
    url      = "jdbc:postgresql://${local.bob-postgres.database-host}/${local.databases.bob.database-name}"
  }
  humanReadableName = var.bob-identityhub-host
  namespace         = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId     = var.bob-did
  vault-url         = "http://bob-vault:8200"
  url-path          = var.bob-identityhub-host
  useSVE            = var.useSVE
}

module "bob-minio" {
  source            = "./modules/minio"
  humanReadableName = lower(var.bob-humanReadableName)
  minio-username    = "bobawsclient"
  minio-password    = "bobawssecret"
}

locals {
  bob-azure-key-base64 = base64encode(var.bob-azure-account-key)
}
