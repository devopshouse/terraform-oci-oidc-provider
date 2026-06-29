output "oci_integration_config_json" {
  description = "Ready-to-use JSON value for the OCI_INTEGRATION_CONFIG_JSON GitHub Actions secret."
  sensitive   = true
  value       = local.oci_integration_config_json
}

output "iam_group_ocid" {
  description = "OCID do grupo Identity Domains para GitHub Actions."
  value       = oci_identity_domains_group.git_actions_group.id
}

output "ocir_auth_token" {
  description = "Token de autenticação para OCIR, emitido para o service user do GitHub Actions."
  sensitive   = true
  value       = oci_identity_domains_auth_token.ocir_token.token
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
