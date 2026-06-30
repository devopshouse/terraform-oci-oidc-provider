locals {
  github_enabled = contains(var.ci_platforms, "github")
  gitlab_enabled = contains(var.ci_platforms, "gitlab")

  idcs_endpoint = trimsuffix(data.oci_identity_domains.domain.domains[0].url, ":443")

  github_sub_claims = concat(
    [for repo in try(var.github.repositories, []) : "repo:${repo}:ref:refs/heads/${var.github.branch}"],
    [for repo in try(var.github.repositories, []) : "repo:${repo}:pull_request"]
  )

  github_repo_names = toset(local.github_enabled && var.github.create_secrets ? [for repo in try(var.github.repositories, []) : split("/", repo)[1]] : [])

  gitlab_sub_claims = try(var.gitlab.issuer, "") == "" ? [] : [
    for project in var.gitlab.projects :
    "project_path:${project}:ref_type:${var.gitlab.ref_type}:ref:${var.gitlab.ref}"
  ]

  gitlab_audience = try(var.gitlab.audience, null)

  ocir_group_name = "${var.git_actions_group_name}-ocir"

  ocir_broad_policy_statements = [
    "allow group ${var.oci_identity_domain_name}/${local.ocir_group_name} to manage repos in compartment id ${var.oci_compartment_id} where request.permission='REPOSITORY_READ'",
    "allow group ${var.oci_identity_domain_name}/${local.ocir_group_name} to manage repos in compartment id ${var.oci_compartment_id} where request.permission='REPOSITORY_UPDATE'",
    "allow group ${var.oci_identity_domain_name}/${local.ocir_group_name} to manage repos in compartment id ${var.oci_compartment_id} where request.permission='REPOSITORY_CREATE'",
  ]

  ocir_restricted_policy_statements = flatten([
    for repo in var.ocir_allowed_repositories :
    [
      "allow group ${var.oci_identity_domain_name}/${local.ocir_group_name} to manage repos in compartment id ${var.oci_compartment_id} where all {target.repo.name='${repo}', request.permission='REPOSITORY_READ'}",
      "allow group ${var.oci_identity_domain_name}/${local.ocir_group_name} to manage repos in compartment id ${var.oci_compartment_id} where all {target.repo.name='${repo}', request.permission='REPOSITORY_UPDATE'}",
    ]
  ])

  ocir_policy_statements = length(var.ocir_allowed_repositories) == 0 ? local.ocir_broad_policy_statements : local.ocir_restricted_policy_statements

  ci_oidc_config_json = jsonencode({
    oci_idcs_endpoint  = local.idcs_endpoint
    oci_client_id      = oci_identity_domains_app.git_actions_app.name
    oci_client_secret  = oci_identity_domains_app.git_actions_app.client_secret
    oci_region         = var.oci_region
    oci_tenancy_id     = oci_identity_domains_app.git_actions_app.tenancy_ocid
    oci_compartment_id = var.oci_compartment_id
    ocir_username      = "${data.oci_objectstorage_namespace.os.namespace}/${var.oci_service_user_name}-ocir"
    ocir_password      = try(oci_identity_domains_auth_token.ocir_token.token, "")
    ocir_url           = "ocir.${var.oci_region}.oci.oraclecloud.com/${data.oci_objectstorage_namespace.os.namespace}"
  })
}
