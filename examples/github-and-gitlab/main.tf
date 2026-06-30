terraform {
  required_version = ">= 1.3"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  region = var.oci_region
}

provider "github" {
  # Set GITHUB_TOKEN env var with a token that has the repo scope.
  owner = var.github_org
}

variable "github_org" {
  description = "GitHub organisation name (owner of the repositories)."
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

  # Both platforms share the same service user, group, and Confidential App.
  # Two separate Identity Propagation Trusts are created — one per platform.
  ci_platforms = ["github", "gitlab"]

  github = {
    repositories   = ["${var.github_org}/app-repo"]
    branch         = "main"
    create_secrets = true # writes OCI_OIDC_CONFIG as a GitHub Actions secret in each repository
  }

  gitlab = {
    issuer   = "https://gitlab.com"
    projects = ["my-group/my-project"]
    ref      = "main"
    ref_type = "branch"
  }
  # GitLab secrets must be stored manually from the outputs below.
}

output "gitlab_oidc_audience" {
  description = "Set this as id_tokens.OCI_TOKEN.aud in .gitlab-ci.yml."
  value       = module.oci_oidc.gitlab_oidc_audience
}

output "ci_oidc_config_json" {
  description = "Store this as OCI_OIDC_CONFIG in GitLab CI/CD variables (masked). Contains OCI + OCIR fields unified."
  sensitive   = true
  value       = module.oci_oidc.ci_oidc_config_json
}
