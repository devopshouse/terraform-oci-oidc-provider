data "oci_identity_domains" "domain" {
  compartment_id = var.oci_tenancy_id
  display_name   = var.oci_identity_domain_name
}

data "oci_objectstorage_namespace" "os" {
  compartment_id = var.oci_tenancy_id
}

resource "oci_identity_domains_user" "git_service_user" {
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = var.oci_service_user_name

  name {
    formatted = var.oci_service_user_name
  }

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}


resource "oci_identity_domains_group" "git_service_group" {
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = var.oci_service_group_name

  members {
    type  = "User"
    value = oci_identity_domains_user.git_service_user.id
  }

  lifecycle {
    ignore_changes = [schemas, members]
  }
}


resource "oci_identity_domains_app" "git_actions_app" {
  idcs_endpoint = local.idcs_endpoint
  display_name  = var.oci_app_name
  description   = "Confidential Application used for Git Actions workload identity federation."

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  active          = var.oci_app_active
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
  name          = var.github_trust_name
  description   = "Identity propagation trust for GitHub Actions OIDC."
  type          = "JWT"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]

  active              = var.oci_app_active
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
    # BUG: OCI provider — the Identity Domains GET API does not return impersonation_service_users
    # or tags by default. The provider does not issue the special refresh requests, causing false
    # drift on every plan. Running apply is safe: it re-applies idempotently with no side effects.
    ignore_changes = [impersonation_service_users, tags]
    precondition {
      condition     = !local.github_enabled || try(length(var.github.repositories) > 0, false)
      error_message = "github.repositories is required when \"github\" ∈ ci_platforms."
    }
  }
}


resource "oci_identity_policy" "git_actions_policy" {
  compartment_id = var.oci_tenancy_id
  name           = var.oci_policy_name
  description    = "Allows ${oci_identity_domains_group.git_service_group.display_name} to manage all resources in compartment ${var.oci_compartment_id}."

  statements = [
    "allow group ${var.oci_identity_domain_name}/${oci_identity_domains_group.git_service_group.display_name} to manage all-resources in compartment id ${var.oci_compartment_id}",
    "allow group ${var.oci_identity_domain_name}/${oci_identity_domains_group.git_service_group.display_name} to manage dynamic-groups in tenancy"
  ]
}


# ---------------------------------------------------------------------------
# IDCS — Identity Propagation Trust (GitLab CI OIDC → OCI UPST)
# ---------------------------------------------------------------------------
resource "oci_identity_domains_identity_propagation_trust" "gitlab_ci_trust" {
  count = local.gitlab_enabled ? 1 : 0

  idcs_endpoint = local.idcs_endpoint
  issuer        = var.gitlab.issuer
  name          = var.gitlab_trust_name
  description   = "Identity propagation trust for GitLab CI OIDC. Expected aud in id_tokens: ${local.gitlab_audience}"
  type          = "JWT"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]

  active              = var.oci_app_active
  allow_impersonation = true
  public_key_endpoint = coalesce(var.gitlab.public_key_endpoint, "${var.gitlab.issuer}/oauth/discovery/keys")

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
    # Same bug as the GitHub trust: GET API does not return impersonation_service_users/tags → false drift.
    ignore_changes = [impersonation_service_users, tags]
    precondition {
      condition     = !local.gitlab_enabled || try(var.gitlab.issuer, "") != ""
      error_message = "gitlab.issuer is required when \"gitlab\" ∈ ci_platforms."
    }
  }
}

resource "github_actions_secret" "ci_oidc_config" {
  for_each = local.github_repo_names

  repository  = each.key
  secret_name = var.github.secret_name
  value       = local.ci_oidc_config_json
}
