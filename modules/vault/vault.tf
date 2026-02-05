#
#  Copyright (c) 2024 Metaform Systems, Inc.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  SPDX-License-Identifier: Apache-2.0
#
#  Contributors:
#       Metaform Systems, Inc. - initial API and implementation
#

locals {
  # Generate vault kv put commands for each seed secret
  seed_commands = [
    for name, content in var.seed_secrets :
    "/bin/vault kv put secret/${name} content='${replace(content, "'", "'\\''")}'"
  ]

  # Join all commands with && and add sleep at the beginning
  postStart_script = length(local.seed_commands) > 0 ? join(" && ", concat(["sleep 5"], local.seed_commands)) : ""
}

resource "helm_release" "vault" {
  name      = var.humanReadableName
  namespace = var.namespace

  force_update      = true
  dependency_update = true
  reuse_values      = true
  cleanup_on_fail   = true
  replace           = true

  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"

  set {
    name  = "server.dev.devRootToken"
    value = var.vault-token
  }
  set {
    name  = "server.dev.enabled"
    value = true
  }

  set {
    name  = "injector.enabled"
    value = false
  }

  set {
    name  = "hashicorp.token"
    value = var.vault-token
  }

  values = [
    yamlencode({
      "server" : {
        "postStart" : length(local.seed_commands) > 0 ? ["sh", "-c", local.postStart_script] : null
      },
      "hashicorp" : {
        "timeout" : 30,
        "healthCheck" : {
          "enabled" : true,
          "standbyOk" : true
        },
        "paths" : {
          "secret" : "/v1/secret/data"
        }
      }
    })
  ]
}
