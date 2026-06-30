# Self-hosted GitLab on a private network that OCI IDCS cannot reach directly.
#
# OCI IDCS validates GitLab OIDC JWTs by fetching signing keys from
# {issuer}/oauth/discovery/keys. If your GitLab instance is on a private
# network (VPN, RFC 1918, or internal DNS), IDCS cannot reach that endpoint.
#
# Workaround: host the JWKS at a publicly accessible OCI Object Storage URL
# and point gitlab.public_key_endpoint at that URL.
#
# Setup steps for the JWKS mirror:
#   1. Fetch: curl https://<gitlab>/oauth/discovery/keys > jwks.json
#   2. Upload jwks.json to an OCI Object Storage bucket with public read access
#      or create a Pre-Authenticated Request (PAR) URL for the object.
#   3. Set gitlab_public_key_endpoint to that URL in terraform.tfvars.
#   4. When GitLab rotates its signing keys, repeat steps 1-2 manually.

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

variable "gitlab_issuer" {
  description = "Self-hosted GitLab OIDC issuer URL (e.g. https://gitlab.internal.example.com)."
}

variable "gitlab_public_key_endpoint" {
  description = "Public OCI Object Storage URL hosting the GitLab JWKS JSON."
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
    issuer              = var.gitlab_issuer
    projects            = ["my-group/my-project"]
    ref                 = "main"
    ref_type            = "branch"
    public_key_endpoint = var.gitlab_public_key_endpoint
  }

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
