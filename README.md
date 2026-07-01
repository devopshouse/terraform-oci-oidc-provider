# terraform-oci-oidc-federation

Terraform module that configures OIDC workload identity federation between GitHub Actions and/or GitLab CI and OCI Identity Domains (IDCS), enabling passwordless CI/CD pipelines against OCI APIs and OCIR (Oracle Cloud Infrastructure Registry).

## How it works

When a CI pipeline runs, the CI platform issues a short-lived OIDC JWT signed by the platform's private key. The pipeline exchanges this JWT with OCI IDCS using a Confidential Application — IDCS validates the JWT signature against the platform's published JWKS, checks that the `sub` claim matches registered values, and issues a User Principal Security Token (UPST) that impersonates a dedicated service user. The pipeline then uses the UPST to call OCI APIs without storing any long-lived OCI credentials.

```
CI runner
  │
  │ 1. Request OIDC JWT (platform-signed)
  ▼
GitHub / GitLab JWKS ──── publishes signing keys ────► OCI IDCS
  │                                                         │
  │ 2. POST JWT + client_id + client_secret                 │ 3. Validate signature + sub claim
  └─────────────────────────────────────────────────────────►
                                                            │ 4. Issue short-lived UPST
                                                            ▼
                                                     OCI APIs / OCIR
```

OCIR authentication uses a classic username/password auth token because OCIR does not support the UPST flow. A dedicated OCIR user, auth token, group, and policy are always created alongside the service user. By default the OCIR policy allows push/pull and repository creation in the target compartment; set `ocir_allowed_repositories` to restrict push/pull to existing repository names.

The generated `ocir_username` follows OCI's Docker login format. For the `Default` identity domain it is `<namespace>/<user>`. For non-default identity domains it is `<namespace>/<identity-domain>/<user>`.

## Resources created

| Resource | Conditional |
|---|---|
| IDCS service user (for UPST impersonation) | Always |
| IDCS OCIR user + auth token (for container registry) | Always |
| IDCS CI group (containing the UPST service user) | Always |
| IDCS OCIR group (containing the OCIR user) | Always |
| IDCS Confidential Application (`client_credentials`) | Always |
| IAM policy (manage all-resources in compartment + manage dynamic-groups in tenancy) | Always |
| IAM policy for OCIR push/pull access | Always |
| Identity Propagation Trust for GitHub Actions | Only when `"github" ∈ ci_platforms` |
| Identity Propagation Trust for GitLab CI | Only when `"gitlab" ∈ ci_platforms` |
| GitHub Actions secret (`OCI_OIDC_CONFIG`) per repo | Only when `create_github_secrets = true` |

## Prerequisites

- OCI tenancy with Identity Domains enabled
- Terraform >= 1.3.0 or OpenTofu >= 1.6.0 (required for `optional()` in object variables)
- OCI provider credentials (environment variables or `~/.oci/config`)
- GitHub personal access token or App token with `repo` scope — only if `github.create_secrets = true`

## Required OCI permissions

The identity running `terraform apply` needs:

```
allow <user-or-group> to manage identity-domains in tenancy
allow <user-or-group> to manage policies in tenancy
allow <user-or-group> to read objectstorage-namespaces in tenancy
```

> **What the module grants to CI pipelines:** The IAM policy created by this module grants the CI group `manage all-resources in compartment id <oci_compartment_id>` and `manage dynamic-groups in tenancy`. Review this privilege level before deploying to production.
>
> The dedicated OCIR user is not a member of the CI group and does not inherit `manage all-resources`. Its separate policy grants only OCIR repository permissions.

## Getting Started

Minimal GitHub Actions setup — secrets are written automatically into each listed repository:

```hcl
module "oci_oidc" {
  source = "github.com/devopshouse/terraform-oci-oidc-federation"

  oci_tenancy_id        = "ocid1.tenancy.oc1..aaaa..."
  oci_compartment_id    = "ocid1.compartment.oc1..aaaa..."
  oci_region            = "sa-saopaulo-1"
  oci_service_user_name = "svc-ci"
  git_actions_group_name = "grp-ci-actions"

  ci_platforms = ["github"]
  github = {
    repositories = ["my-org/my-repo"]
  }
}
```

After `terraform apply`, `OCI_OIDC_CONFIG` is written as an encrypted GitHub Actions secret in `my-org/my-repo`. See [`examples/github-only/`](examples/github-only/) for a full example including the workflow authentication snippet.

To restrict OCIR access to existing repositories, pass exact repository names as they appear in OCI:

```hcl
ocir_allowed_repositories = [
  "app-api",
  "base-image",
  "web-service",
]
```

Leaving `ocir_allowed_repositories = []` allows the OCIR user to push/pull broadly and create repositories in `oci_compartment_id`.

## Examples

| Example | Description |
|---|---|
| [`examples/github-only/`](examples/github-only/) | GitHub Actions OIDC — minimal setup, secrets written automatically |
| [`examples/gitlab-only/`](examples/gitlab-only/) | GitLab CI OIDC with gitlab.com, manual secret management |
| [`examples/github-and-gitlab/`](examples/github-and-gitlab/) | Both platforms simultaneously, shared service user and group |
| [`examples/private-gitlab/`](examples/private-gitlab/) | Self-hosted GitLab with JWKS endpoint override for private instances |

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `oci_tenancy_id` | `string` | OCID of the OCI tenancy |
| `oci_compartment_id` | `string` | OCID of the compartment where resources are created and where CI pipelines get access |
| `oci_region` | `string` | OCI region identifier (e.g. `sa-saopaulo-1`, `us-ashburn-1`) |
| `oci_service_user_name` | `string` | Username for the IDCS service user. A second user `{name}-ocir` is also created for OCIR auth. |
| `git_actions_group_name` | `string` | Display name for the IDCS group. Include environment tokens manually when deploying to multiple IDCS domains. |
| `ci_platforms` | `list(string)` | Platforms to enable. Valid values: `"github"`, `"gitlab"`. Must contain at least one. |

### GitHub (`github` object — required when `"github" ∈ ci_platforms`)

| Name | Type | Default | Description |
|---|---|---|---|
| `github.repositories` | `list(string)` | `[]` | Repositories in `org/repo` format. Required when GitHub is enabled (enforced by a `precondition` at plan time). |
| `github.branch` | `string` | `"main"` | Branch for sub claim scoping. Applied uniformly to all repositories — use multiple module calls for different branches per repo. |
| `github.create_secrets` | `bool` | `true` | When `true`, writes `OCI_OIDC_CONFIG` as a GitHub Actions secret into each listed repository. Set to `false` to manage secrets yourself using the module output. |

### GitLab (`gitlab` object — required when `"gitlab" ∈ ci_platforms`)

| Name | Type | Default | Description |
|---|---|---|---|
| `gitlab.issuer` | `string` | `""` | OIDC issuer URL. Required when GitLab is enabled. Use `https://gitlab.com` for SaaS or your self-hosted URL. |
| `gitlab.projects` | `list(string)` | `[]` | Projects in `group/project` format. |
| `gitlab.ref` | `string` | `"main"` | Branch or tag ref for sub claim scoping. |
| `gitlab.ref_type` | `string` | `"branch"` | Either `"branch"` or `"tag"`. |
| `gitlab.audience` | `string` | `"https://cloud.oracle.com"` | The `aud` claim expected in GitLab OIDC tokens. Must match the value set in `.gitlab-ci.yml` under `id_tokens.<TOKEN_NAME>.aud`. |
| `gitlab.public_key_endpoint` | `string` | `null` | Override for the JWKS URL. When omitted, defaults to `{issuer}/oauth/discovery/keys` — the standard GitLab OIDC discovery path, which works for public instances. Set this when OCI IDCS cannot reach your self-hosted GitLab's network (e.g., behind a firewall or on a private IP). In that case, host the JWKS JSON at a publicly accessible URL such as an OCI Object Storage pre-authenticated request and point this variable there. See [`examples/private-gitlab/`](examples/private-gitlab/). |

### Optional

| Name | Type | Default | Description |
|---|---|---|---|
| `oci_identity_domain_name` | `string` | `"Default"` | Display name of the OCI Identity Domain. |
| `app_active` | `bool` | `true` | Activates or deactivates the Confidential App and both trusts. Useful for temporarily disabling CI access without destroying resources. |
| `ocir_allowed_repositories` | `list(string)` | `[]` | Exact OCIR repository names allowed for push/pull by the dedicated OCIR user. Empty means broad OCIR push/pull plus repository creation in `oci_compartment_id`. When non-empty, the module grants `REPOSITORY_READ` and `REPOSITORY_UPDATE` for each listed `target.repo.name`; those repositories must already exist because repository creation cannot be scoped by name. |
| `oci_app_name` | `string` | `"CI-OIDC-Confidential-App"` | Display name for the IDCS Confidential Application. |
| `github_trust_name` | `string` | `"GitHub-Actions-Trust"` | Name for the GitHub Actions Identity Propagation Trust. |
| `gitlab_trust_name` | `string` | `"GitLab-CI-Trust"` | Name for the GitLab CI Identity Propagation Trust. |
| `iam_policy_name` | `string` | `"p-bootstrap-ci-oidc-manage-compartment"` | Name for the IAM policy. Override to customize or to avoid a destroy-recreate when migrating from an older deployment. |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `ci_oidc_config_json` | Yes | Unified JSON blob (OCI + OCIR fields) for the `OCI_OIDC_CONFIG` secret. Contains IDCS endpoint, client ID/secret, region, tenancy OCID, compartment OCID, `ocir_username`, `ocir_password`, and `ocir_url`. `ocir_username` is `<namespace>/<user>` for the `Default` domain and `<namespace>/<identity-domain>/<user>` for non-default domains. Written automatically as a GitHub secret when `create_github_secrets = true`. |
| `iam_group_ocid` | No | OCID of the created IDCS group. |
| `github_subject_claims` | No | Exact `sub` claim strings registered in the GitHub trust. Useful for debugging authentication failures. |
| `gitlab_subject_claims` | No | Exact `sub` claim strings registered in the GitLab trust. |
| `gitlab_oidc_audience` | No | The `aud` value to set in `.gitlab-ci.yml` under `id_tokens.<TOKEN_NAME>.aud`. |

## Known limitations

- **Single branch per module call:** `github.branch` applies to all repositories uniformly. Use multiple module calls for different branch scoping per repo.
- **Known OCI provider false-drift:** Both Identity Propagation Trusts suppress `impersonation_service_users` and `tags` via `lifecycle { ignore_changes = [...] }`. The OCI GET API omits these fields by default, causing phantom drift on every `terraform plan`. Running `terraform apply` is safe and idempotent.

  **Workaround** (if drift reappears after a `terraform state rm`):

  ```bash
  # Get the OCID of the affected trust
  terraform show -json | jq '.values.root_module.resources[] \
    | select(.type=="oci_identity_domains_identity_propagation_trust") \
    | .values.id'

  # Re-import and apply (idempotent)
  terraform import 'oci_identity_domains_identity_propagation_trust.github_actions_trust[0]' <ocid>
  terraform apply
  ```

## Compatibility

Compatible with **Terraform >= 1.3.0** and **OpenTofu >= 1.6.0**.
