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
  depends_on        = [module.azurite]
  source            = "./modules/connector"
  humanReadableName = var.bob-humanReadableName
  namespace         = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId     = var.bob-did
  database-host     = local.bob-postgres.database-host
  database-name     = local.databases.bob.database-name
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
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_ALIAS"     = "org.eclipse.tractusx.vc.type"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_TYPE"      = "MembershipCredential"
    "TX_EDC_IAM_IATP_DEFAULT_SCOPES_SCOPE1_OPERATION" = "read"
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
    "EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"              = "org.eclipse.tractusx.vc.type:MembershipCredential:read"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_URL"             = "http://bob-ih:7084/api/sts/token"
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_ID"             = var.bob-did
    "TX_EDC_IAM_IATP_STS_OAUTH_CLIENT_SECRET_ALIAS"   = "bob-sts-client-secret"
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_AUDIENCE"        = var.bob-did
    "TX_EDC_IAM_IATP_STS_OAUTH_TOKEN_SCOPE"           = "org.eclipse.tractusx.vc.type:MembershipCredential:read"
    "EDC_PARTICIPANT_ID"                              = var.bob-did
    "EDC_PARTICIPANT_CONTEXT_ID"                      = var.bob-did
    "TX_EDC_PARTICIPANT_CONTEXT_ID"                   = var.bob-did
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
