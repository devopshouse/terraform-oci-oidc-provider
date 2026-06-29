data "oci_identity_domains" "domain" {
  compartment_id = var.oci_tenancy_id
  display_name   = var.identity_domain_name
}

data "oci_objectstorage_namespace" "os" {
  compartment_id = var.oci_tenancy_id
}

locals {
  github_enabled = contains(var.ci_platforms, "github")
  gitlab_enabled = contains(var.ci_platforms, "gitlab")

  github_sub_claims = concat(
    [for repo in var.github.repositories : "repo:${repo}:ref:refs/heads/${var.github.branch}"],
    [for repo in var.github.repositories : "repo:${repo}:pull_request"]
  )

  gitlab_sub_claims = var.gitlab == null ? [] : [
    for project in var.gitlab.projects :
    "project_path:${project}:ref_type:${var.gitlab.ref_type}:ref:${var.gitlab.ref}"
  ]

  # The provider may return the domain URL with an explicit :443 suffix while
  # older state values were stored without it. These resources treat
  # idcs_endpoint as ForceNew, so normalize the endpoint to avoid false
  # replacement caused only by URL formatting.
  idcs_endpoint = trimsuffix(data.oci_identity_domains.domain.domains[0].url, ":443")

  # Nomes curtos dos repositórios GitHub (sem o owner) para uso nos secrets do GitHub Actions.
  github_repo_names = [for repo in var.github.repositories : split("/", repo)[1]]

  # JSON do secret OCI_CONFIG_JSON — reutilizado no output e no github_actions_secret.
  oci_integration_config_json = jsonencode({
    oci_idcs_endpoint  = local.idcs_endpoint
    oci_client_id      = oci_identity_domains_app.git_actions_app.name
    oci_client_secret  = oci_identity_domains_app.git_actions_app.client_secret
    oci_region         = var.oci_region
    oci_tenancy_id     = oci_identity_domains_app.git_actions_app.tenancy_ocid
    oci_compartment_id = var.oci_compartment_id
  })

  # JSON OCIR_CONFIG_JSON para autenticação de GitHub Actions no OCIR, usado em workflows que precisam puxar imagens do OCIR.
  ocir_config_json = jsonencode({
    ocir_username = "${data.oci_objectstorage_namespace.os.namespace}/${var.service_user_name}-ocir"
    ocir_password = oci_identity_domains_auth_token.ocir_token.token
    ocir_url      = "ocir.${var.oci_region}.oci.oraclecloud.com/${data.oci_objectstorage_namespace.os.namespace}"
  })
}

resource "oci_identity_domains_user" "git_service_user" {
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = var.service_user_name

  name {
    formatted = var.service_user_name
  }

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Usuário separado (não-service) necessário para auth token do OCIR.
# Usuários service não suportam auth tokens no OCI Identity Domains.
resource "oci_identity_domains_user" "ocir_user" {
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = "${var.service_user_name}-ocir"

  name {
    family_name = "OCIR"
    given_name  = "Service"
    formatted   = "${var.service_user_name}-ocir"
  }

  # OCI valida RFC 5322 — usar domínio reservado (RFC 2606) para usuários de serviço
  emails {
    value   = "${var.service_user_name}-ocir-noreply@readyti.com.br"
    type    = "work"
    primary = true
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

resource "oci_identity_domains_auth_token" "ocir_token" {
  idcs_endpoint = local.idcs_endpoint
  description   = "OCIR auth token"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:authToken"]

  user {
    value = oci_identity_domains_user.ocir_user.id
  }
}

resource "oci_identity_domains_group" "git_actions_group" {
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = var.git_actions_group_name

  members {
    type  = "User"
    value = oci_identity_domains_user.git_service_user.id
  }

  members {
    type  = "User"
    value = oci_identity_domains_user.ocir_user.id
  }

  lifecycle {
    ignore_changes = [schemas, members]
  }
}

resource "oci_identity_domains_app" "git_actions_app" {
  idcs_endpoint = local.idcs_endpoint
  display_name  = var.suffix != "" ? "Git-Actions-Confidential-App-${var.suffix}" : "Git-Actions-Confidential-App"
  description   = "Confidential Application used for Git Actions workload identity federation."

  based_on_template {
    value = var.confidential_app_template_id
  }

  active          = var.app_active
  client_type     = "confidential"
  is_oauth_client = true
  allowed_grants  = ["client_credentials"]

  schemas = [
    "urn:ietf:params:scim:schemas:oracle:idcs:App"
  ]

  lifecycle {
    ignore_changes = [schemas]
  }
}

resource "oci_identity_domains_identity_propagation_trust" "github_actions_trust" {
  count = local.github_enabled ? 1 : 0

  idcs_endpoint = local.idcs_endpoint
  issuer        = "https://token.actions.githubusercontent.com"
  name          = var.suffix != "" ? "GitHub-Actions-Trust-${var.suffix}" : "GitHub-Actions-Trust"
  description   = "Identity propagation trust for GitHub Actions OIDC."
  type          = "JWT"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]

  active              = var.app_active
  allow_impersonation = true
  public_key_endpoint = "https://token.actions.githubusercontent.com/.well-known/jwks"

  client_claim_name   = "sub"
  client_claim_values = local.github_sub_claims
  subject_claim_name  = "sub"
  subject_type        = "User"

  impersonation_service_users {
    rule  = "sub eq *"
    value = oci_identity_domains_user.git_service_user.id
  }

  oauth_clients = [oci_identity_domains_app.git_actions_app.name]

  tags {
    key   = "managed-by"
    value = "terraform"
  }

  lifecycle {
    # BUG: OCI provider — a API GET do Identity Domains não retorna impersonation_service_users
    # nem tags por padrão. O provider não faz as requests especiais no refresh, causando falso
    # drift em todo plan. Running apply é seguro: re-aplica idempotentemente sem efeito colateral.
    ignore_changes = [impersonation_service_users, tags]
    precondition {
      condition     = !local.github_enabled || length(var.github.repositories) > 0
      error_message = "github.repositories é obrigatório quando \"github\" ∈ ci_platforms."
    }
  }
}


resource "oci_identity_policy" "git_actions_policy" {
  compartment_id = var.oci_tenancy_id
  name           = var.suffix != "" ? "p-boostrap-github-actions-manage-compartment-${var.suffix}" : "p-boostrap-github-actions-manage-compartment"
  description    = "Allows ${oci_identity_domains_group.git_actions_group.display_name} to manage all resources in compartment ${var.oci_compartment_id}."

  statements = [
    "allow group ${oci_identity_domains_group.git_actions_group.display_name} to manage all-resources in compartment id ${var.oci_compartment_id}",
    "allow group ${oci_identity_domains_group.git_actions_group.display_name} to manage dynamic-groups in tenancy"
  ]
}

# ---------------------------------------------------------------------------
# IDCS — Identity Propagation Trust (GitLab CI OIDC → OCI UPST)
# ---------------------------------------------------------------------------
resource "oci_identity_domains_identity_propagation_trust" "gitlab_ci_trust" {
  count = local.gitlab_enabled ? 1 : 0

  idcs_endpoint = local.idcs_endpoint
  issuer        = var.gitlab.issuer
  name          = var.suffix != "" ? "GitLab-CI-Trust-${var.suffix}" : "GitLab-CI-Trust"
  description   = "Identity propagation trust for GitLab CI OIDC."
  type          = "JWT"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]

  active              = var.app_active
  allow_impersonation = true
  public_key_endpoint = "${var.gitlab.issuer}/oauth/discovery/keys"

  client_claim_name   = "sub"
  client_claim_values = local.gitlab_sub_claims
  subject_claim_name  = "sub"
  subject_type        = "User"

  impersonation_service_users {
    rule  = "sub eq *"
    value = oci_identity_domains_user.git_service_user.id
  }

  oauth_clients = [oci_identity_domains_app.git_actions_app.name]

  tags {
    key   = "managed-by"
    value = "terraform"
  }

  lifecycle {
    # Mesmo bug do trust GitHub: API GET não retorna impersonation_service_users/tags → falso drift.
    ignore_changes = [impersonation_service_users, tags]
    precondition {
      condition     = !local.gitlab_enabled || (var.gitlab != null && var.gitlab.issuer != "")
      error_message = "gitlab.issuer é obrigatório quando \"gitlab\" ∈ ci_platforms."
    }
  }
}

resource "github_actions_secret" "oci_config_json" {
  for_each = local.github_enabled ? toset(local.github_repo_names) : toset([])

  repository  = each.key
  secret_name = "OCI_CONFIG_JSON"
  value       = local.oci_integration_config_json
}

resource "github_actions_secret" "vault_cert_config" {
  for_each = local.github_enabled ? toset(local.github_repo_names) : toset([])

  repository  = each.key
  secret_name = "VAULT_CERT_CONFIG"
  value       = var.vault_certificate_config_json
}

resource "github_actions_secret" "ocir_config_json" {
  for_each = local.github_enabled ? toset(local.github_repo_names) : toset([])

  repository  = each.key
  secret_name = "OCIR_CONFIG_JSON"
  value       = local.ocir_config_json
}
