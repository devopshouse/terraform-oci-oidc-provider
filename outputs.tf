output "oci_config_json" {
  description = "Ready-to-use JSON value for the OCI_CONFIG_JSON GitHub Actions secret."
  sensitive   = true
  value       = local.oci_config_json
}

output "iam_group_ocid" {
  description = "OCID do grupo Identity Domains para GitHub Actions."
  value       = oci_identity_domains_group.git_actions_group.id
}

output "github_subject_claims" {
  description = "Sub claims registrados no trust GitHub Actions (vazio quando \"github\" ∉ ci_platforms)."
  value       = local.github_sub_claims
}

output "gitlab_subject_claims" {
  description = "Sub claims registrados no trust GitLab CI (vazio quando \"gitlab\" ∉ ci_platforms)."
  value       = local.gitlab_sub_claims
}

output "gitlab_oidc_audience" {
  description = "Audience to set in .gitlab-ci.yml: id_tokens.OCI_OIDC_TOKEN.aud (null when \"gitlab\" ∉ ci_platforms)."
  value       = local.gitlab_audience
}

output "ocir_config_json" {
  description = "Ready-to-use JSON value for the OCIR_CONFIG_JSON GitHub Actions secret."
  sensitive   = true
  value       = local.ocir_config_json
}
