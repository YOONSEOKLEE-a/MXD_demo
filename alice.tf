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
#

# First connector
module "alice-connector" {
  depends_on           = [module.azurite]
  source               = "./modules/connector"
  humanReadableName    = var.alice-humanReadableName
  namespace            = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId        = var.alice-bpn
  participantContextId = var.alice-did
  database-host        = local.alice-postgres.database-host
  database-name        = local.databases.alice.database-name
  database-credentials = {
    user     = local.databases.alice.database-username
    password = local.databases.alice.database-password
  }
  dcp-config = {
    id                     = var.alice-did
    sts_token_url          = "http://alice-ih:7084/api/sts/token"
    sts_client_id          = var.alice-did
    sts_clientsecret_alias = "alice-sts-client-secret"
  }
  dataplane = {
    privatekey-alias = "${var.alice-did}#signing-key-1"
    publickey-alias  = "${var.alice-did}#signing-key-1"
  }

  azure-account-name    = var.alice-azure-account-name
  azure-account-key     = local.alice-azure-key-base64
  azure-account-key-sas = var.alice-azure-key-sas
  azure-url             = module.azurite.azurite-url

  ingress-host = var.alice-ingress-host

  minio-config = {
    username = module.alice-minio.minio-username
    password = module.alice-minio.minio-password
    url      = module.alice-minio.minio-url
  }
  controlplane_env = {
    "TRACTUSX_EDC_PARTICIPANT_BPN"                    = var.alice-bpn
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
    "EDC_IAM_IATP_CREDENTIALSERVICE_URL"              = "http://alice-ih:7082/api/credentials/v1/participants/ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U="
    "EDC_IAM_IATP_PRESENTATION_QUERY_URL"             = "http://alice-ih:7082/api/credentials/v1/participants/ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U=/presentations/query"
    "TX_EDC_IAM_IATP_CREDENTIALSERVICE_URL"           = "http://alice-ih:7082/api/credentials/v1/participants/ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U="
    "TX_EDC_IAM_IATP_PRESENTATION_QUERY_URL"          = "http://alice-ih:7082/api/credentials/v1/participants/ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U=/presentations/query"
    "EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER"      = "Authorization"
    "EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER"     = "Authorization"
    "TX_EDC_IAM_IATP_CREDENTIALSERVICE_AUTH_HEADER"   = "Authorization"
    "TX_EDC_IAM_IATP_PRESENTATION_QUERY_AUTH_HEADER"  = "Authorization"
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_URL"                = "http://alice-ih:7084/api/sts/token"
    "EDC_IAM_IATP_STS_OAUTH_CLIENT_ID"                = var.alice-did
    "EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS"      = "alice-sts-client-secret"
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE"           = var.alice-did
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"              = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL"             = "http://alice-ih:7084/api/sts/token"
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID"             = var.alice-did
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS"   = "alice-sts-client-secret"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE"        = var.alice-did
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"           = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "EDC_IAM_STS_OAUTH_TOKEN_SCOPE"                   = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "TX_EDC_IAM_STS_OAUTH_TOKEN_SCOPE"                = "org.eclipse.tractusx.vc.type:MembershipCredential:read org.eclipse.tractusx.vc.type:DataExchangeGovernanceCredential:read org.eclipse.tractusx.vc.type:FrameworkAgreementCredential:read org.eclipse.tractusx.vc.type:UsagePurposeCredential:read"
    "EDC_PARTICIPANT_ID"                              = var.alice-bpn
    "EDC_PARTICIPANT_CONTEXT_ID"                      = var.alice-did
    "TX_EDC_PARTICIPANT_CONTEXT_ID"                   = var.alice-did
    "TX_EDC_PARTICIPANT_ID"                           = var.alice-bpn
    "PARTICIPANT_CONTEXT_ID_BASE64"                   = "ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U="
    "PARTICIPANT_ID_BASE64"                           = "ZGlkOndlYjphbGljZS1paCUzQTcwODM6YWxpY2U="
    "JAVA_TOOL_OPTIONS"                               = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=1044 -Dtx.edc.iam.iatp.default-scopes.scope1.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope1.type=MembershipCredential -Dtx.edc.iam.iatp.default-scopes.scope1.operation=read -Dtx.edc.iam.iatp.default-scopes.scope2.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope2.type=DataExchangeGovernanceCredential -Dtx.edc.iam.iatp.default-scopes.scope2.operation=read -Dtx.edc.iam.iatp.default-scopes.scope3.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope3.type=FrameworkAgreementCredential -Dtx.edc.iam.iatp.default-scopes.scope3.operation=read -Dtx.edc.iam.iatp.default-scopes.scope4.alias=org.eclipse.tractusx.vc.type -Dtx.edc.iam.iatp.default-scopes.scope4.type=UsagePurposeCredential -Dtx.edc.iam.iatp.default-scopes.scope4.operation=read"
  }
  useSVE = var.useSVE
}

module "alice-identityhub" {
  depends_on = [module.alice-connector] // depends because of the vault
  source     = "./modules/identity-hub"
  database = {
    user     = local.databases.alice.database-username
    password = local.databases.alice.database-password
    url      = "jdbc:postgresql://${local.alice-postgres.database-host}/${local.databases.alice.database-name}"
  }
  humanReadableName = var.alice-identityhub-host
  namespace         = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId     = var.alice-did
  vault-url         = local.vault-url
  url-path          = var.alice-identityhub-host
  useSVE            = var.useSVE
}

# alice's catalog server
module "alice-catalog-server" {
  depends_on = [module.alice-connector]

  source                 = "./modules/catalog-server"
  humanReadableName      = "alice-catalogserver"
  serviceName            = var.alice-catalogserver-host
  namespace              = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId          = var.alice-did
  participant-context-id = var.alice-did
  identityhub-url        = "http://alice-ih:7082"
  vault-url              = local.vault-url
  bdrs-url               = "http://bdrs-server:8082/api/directory"
  database = {
    user     = local.databases.alice-catalogserver.database-username
    password = local.databases.alice-catalogserver.database-password
    url      = "jdbc:postgresql://${local.catalogserver-postgres.database-host}/${local.databases.alice-catalogserver.database-name}"
  }
  dcp-config = {
    id                     = var.alice-did
    sts_token_url          = "http://alice-ih:7084/api/sts/token"
    sts_client_id          = var.alice-did
    sts_clientsecret_alias = "alice-sts-client-secret"
  }
  useSVE = var.useSVE
}


module "alice-minio" {
  source            = "./modules/minio"
  humanReadableName = lower(var.alice-humanReadableName)
  minio-username    = "aliceawsclient"
  minio-password    = "aliceawssecret"
}

locals {
  alice-azure-key-base64 = base64encode(var.alice-azure-account-key)
  vault-url              = "http://alice-vault:8200"
}
