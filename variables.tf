variable "app_active" {
  type        = bool
  description = "Whether the Identity Domains application should remain active."
  default     = true
}

variable "ci_platforms" {
  type        = list(string)
  description = "CI platforms federated via OIDC. Allowed values: github, gitlab."

  validation {
    condition     = length(var.ci_platforms) > 0
    error_message = "ci_platforms must not be empty. Provide at least one of: github, gitlab."
  }
  validation {
    condition     = alltrue([for p in var.ci_platforms : contains(["github", "gitlab"], p)])
    error_message = "ci_platforms only accepts: github, gitlab."
  }
}


variable "github" {
  type = object({
    branch         = optional(string, "main")
    repositories   = optional(list(string), []) # format: org/repo
    create_secrets = optional(bool, true)
  })
  description = "GitHub Actions OIDC configuration. Required when \"github\" ∈ ci_platforms."
  default     = {}
}

variable "git_actions_group_name" {
  type        = string
  description = "IAM group name shared by all CI platforms federated via OIDC."
}

variable "gitlab" {
  type = object({
    issuer              = optional(string, "") # e.g.: https://gitlab.com or self-hosted
    audience            = optional(string, "https://cloud.oracle.com")
    ref                 = optional(string, "main")
    ref_type            = optional(string, "branch") # branch | tag
    projects            = optional(list(string), []) # format: group/project
    public_key_endpoint = optional(string, null)     # override for private GitLab (IP not routable by OCI)
  })
  description = "GitLab CI OIDC configuration. Required when \"gitlab\" ∈ ci_platforms."
  default     = {}
}

variable "oci_identity_domain_name" {
  type        = string
  description = "Display name of the Identity Domain (e.g., Default)."
  default     = "Default"
}

variable "oci_compartment_id" {
  type        = string
  description = "The OCID of the compartment where resources will be created."
}

variable "oci_region" {
  type        = string
  description = "The OCI region identifier (e.g., sa-saopaulo-1) where resources will be provisioned."
}

variable "oci_tenancy_id" {
  type        = string
  description = "The OCID of the OCI tenancy."
}

variable "oci_service_user_name" {
  type        = string
  description = "Username for the OCI Identity Domain service user created for CI workload identity impersonation via OIDC."
}

variable "github_trust_name" {
  type        = string
  description = "Nome do Identity Propagation Trust para GitHub Actions."
  default     = "GitHub-Actions-Trust"
}

variable "gitlab_trust_name" {
  type        = string
  description = "Nome do Identity Propagation Trust para GitLab CI."
  default     = "GitLab-CI-Trust"
}

variable "iam_policy_name" {
  type        = string
  description = "Nome da IAM policy que concede ao grupo CI acesso ao compartment."
  default     = "p-bootstrap-ci-oidc-manage-compartment"
}

variable "ocir_allowed_repositories" {
  type        = list(string)
  description = "OCIR repository names that the dedicated OCIR user may push/pull. Empty allows broad push/pull and repository creation in the compartment."
  default     = []

  validation {
    condition     = alltrue([for repo in var.ocir_allowed_repositories : trimspace(repo) != ""])
    error_message = "ocir_allowed_repositories must not contain empty repository names."
  }
}

variable "oci_app_name" {
  type        = string
  description = "Nome da Confidential Application no IDCS."
  default     = "CI-OIDC-Confidential-App"
}
