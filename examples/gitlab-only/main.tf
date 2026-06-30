terraform {
  required_version = ">= 1.3"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  region = var.oci_region
}

variable "oci_tenancy_id" {
  description = "OCID of the OCI tenancy."
}

variable "oci_compartment_id" {
  description = "OCID of the compartment where CI pipelines will manage resources."
}

variable "oci_region" {
  description = "OCI region identifier (e.g. sa-saopaulo-1)."
}

module "oci_oidc" {
  source = "../.."

  oci_tenancy_id         = var.oci_tenancy_id
  oci_compartment_id     = var.oci_compartment_id
  oci_region             = var.oci_region
  oci_service_user_name  = "svc-ci"
  git_actions_group_name = "grp-ci-actions"

  # Empty default allows broad OCIR push/pull and repository creation.
  # Restrict to existing repositories with:
  # ocir_allowed_repositories = ["app-api"]

  ci_platforms = ["gitlab"]
  gitlab = {
    issuer   = "https://gitlab.com"
    projects = ["my-group/my-project"]
    ref      = "main"
    ref_type = "branch"
    # audience defaults to "https://cloud.oracle.com" — use the same value
    # in .gitlab-ci.yml under id_tokens.OCI_TOKEN.aud (see gitlab-ci.yml)
  }

}

output "gitlab_oidc_audience" {
  description = "Set this as id_tokens.OCI_TOKEN.aud in .gitlab-ci.yml."
  value       = module.oci_oidc.gitlab_oidc_audience
}

output "gitlab_subject_claims" {
  description = "Registered sub claims — use these to verify the GitLab trust configuration."
  value       = module.oci_oidc.gitlab_subject_claims
}

output "ci_oidc_config_json" {
  description = "Store this as the OCI_OIDC_CONFIG CI/CD variable in GitLab (masked). Contains OCI + OCIR fields unified."
  sensitive   = true
  value       = module.oci_oidc.ci_oidc_config_json
}
