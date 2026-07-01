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
  # Credentials via environment variables (recommended):
  #   TF_VAR_tenancy_ocid, TF_VAR_user_ocid, TF_VAR_fingerprint,
  #   TF_VAR_private_key_path, TF_VAR_region
  # Or via ~/.oci/config with auth = "APIKey"
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
  oci_service_group_name = "grp-ci-actions"

  ci_platforms = ["github"]
  github = {
    repositories = [
      "${var.github_org}/app-repo",
      "${var.github_org}/infra-repo",
    ]
    branch = "main"
    # create_secrets defaults to true — OCI_OIDC_CONFIG is written as an
    # encrypted GitHub Actions secret in each repository above.
  }
}

output "iam_group_ocid" {
  description = "OCID of the IDCS group created for CI pipelines."
  value       = module.oci_oidc.iam_group_ocid
}

output "github_subject_claims" {
  description = "Registered sub claims — use these to verify the GitHub trust configuration."
  value       = module.oci_oidc.github_subject_claims
}
