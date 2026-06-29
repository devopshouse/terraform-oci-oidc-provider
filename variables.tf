variable "oci_tenancy_id" {
  type        = string
  description = "The OCID of the OCI tenancy."
}

variable "oci_compartment_id" {
  type        = string
  description = "The OCID of the compartment where resources will be created."
}

variable "oci_region" {
  type        = string
  description = "The OCI region identifier (e.g., sa-saopaulo-1) where resources will be provisioned."
}

variable "identity_domain_name" {
  type        = string
  description = "Display name of the Identity Domain (e.g., Default)."
  default     = "Default"
}

variable "service_user_name" {
  type        = string
  description = "Username for the OCI Identity Domain service user created for GitHub Actions impersonation."
}

variable "ci_platforms" {
  type        = list(string)
  description = "Plataformas de CI federadas via OIDC. Valores permitidos: github, gitlab."

  validation {
    condition     = length(var.ci_platforms) > 0
    error_message = "ci_platforms não pode ser vazio. Informe ao menos: github ou gitlab."
  }
  validation {
    condition     = alltrue([for p in var.ci_platforms : contains(["github", "gitlab"], p)])
    error_message = "ci_platforms aceita apenas: github, gitlab."
  }
}

variable "github" {
  type = object({
    branch       = optional(string, "main")
    repositories = optional(list(string), []) # formato: org/repo
  })
  description = "Config GitHub Actions OIDC. Obrigatório quando \"github\" ∈ ci_platforms."
  default     = {}
}

variable "gitlab" {
  type = object({
    issuer              = string # ex: https://gitlab.com ou self-hosted
    audience            = optional(string, "https://cloud.oracle.com")
    ref                 = optional(string, "main")
    ref_type            = optional(string, "branch") # branch | tag
    projects            = optional(list(string), []) # formato: group/project
    public_key_endpoint = optional(string, null)     # override para GitLab privado (IP não roteável pela OCI)
  })
  description = "Config GitLab CI OIDC. Obrigatório quando \"gitlab\" ∈ ci_platforms."
  default     = null
}

variable "confidential_app_template_id" {
  type        = string
  description = "Identity Domains template identifier for a Confidential Application."
}

variable "app_active" {
  type        = bool
  description = "Whether the Identity Domains application should remain active."
  default     = true
}

variable "git_actions_group_name" {
  type        = string
  description = "IAM group name used by GitHub Actions OIDC and by the Vault certificate-renewal policies."
}

variable "vault_backend_bucket_name" {
  type        = string
  description = "The name of the Object Storage bucket used for Vault tools and ACME state persistence."
}

variable "compartment_name" {
  type        = string
  description = "Name of the OCI compartment (resolved from data source)."
}

variable "vault_certificate_config_json" {
  type        = string
  sensitive   = true
  description = "JSON blob para o secret VAULT_CERT_CONFIG no GitHub Actions (gerado pelo módulo vault)."
}

variable "suffix" {
  type        = string
  description = "Suffix appended to resource names for uniqueness."
  default     = ""
}
