```bash
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

## Required IAM Roles for GitHub Actions Deployment to Cloud Run

The GitHub Actions deployment service account requires the following IAM roles:

| IAM Role                                                                           | Purpose                                                                                                       |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `roles/run.admin`                                                                  | Create and update Cloud Run services.                                                                         |
| `roles/iam.serviceAccountUser`                                                     | Allow the deployment service account to impersonate the runtime service account used by Cloud Run.            |
| `roles/artifactregistry.writer`                                                    | Push Docker images to Artifact Registry (if GitHub builds and pushes the image).                              |
| `roles/artifactregistry.reader`                                                    | Allow Cloud Run to pull images if needed.                                                                     |
| `roles/storage.admin` _(Optional)_                                                 | Required only when using Cloud Build with Cloud Storage buckets directly.                                     |
| `roles/cloudbuild.builds.editor` or `roles/cloudbuild.builds.builder` _(Optional)_ | Required if GitHub Actions triggers Cloud Build instead of building and pushing the container image directly. |

> **Note:** If you are using **Workload Identity Federation (OIDC)** instead of a service account key, you must also grant the GitHub identity the `roles/iam.workloadIdentityUser` role on the deployment service account.
