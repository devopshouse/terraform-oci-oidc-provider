output "ci_oidc_config_json" {
  description = "Ready-to-use JSON value for the OCI_OIDC_CONFIG CI secret."
  sensitive   = true
  value       = local.ci_oidc_config_json
}

output "iam_group_ocid" {
  description = "OCID of the Identity Domains group shared by all CI platforms federated via OIDC."
  value       = oci_identity_domains_group.git_service_group.id
}

output "github_subject_claims" {
  description = "Subject claims registered in the GitHub Actions trust (empty when \"github\" ∉ ci_platforms)."
  value       = local.github_sub_claims
}

output "gitlab_subject_claims" {
  description = "Subject claims registered in the GitLab CI trust (empty when \"gitlab\" ∉ ci_platforms)."
  value       = local.gitlab_sub_claims
}

output "gitlab_oidc_audience" {
  description = "Audience to set in .gitlab-ci.yml: id_tokens.OCI_OIDC_TOKEN.aud (null when \"gitlab\" ∉ ci_platforms)."
  value       = local.gitlab_audience
}
