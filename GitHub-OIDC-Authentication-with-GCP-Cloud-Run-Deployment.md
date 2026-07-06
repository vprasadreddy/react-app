# GitHub OIDC Authentication with GCP Cloud Run Deployment

This guide walks through the complete setup to deploy a React app from GitHub Actions to Google Cloud Run using Workload Identity Federation (OIDC) instead of service account keys.

## Prerequisites

1. Install and authenticate the Google Cloud CLI:

```bash
gcloud auth login
```

2. Set your target project and compute region:

```bash
gcloud config set project YOUR_GCP_PROJECT_ID
gcloud config set run/region YOUR_REGION
```

3. Enable required Google Cloud services:

```bash
gcloud services enable run.googleapis.com

gcloud services enable artifactregistry.googleapis.com

gcloud services enable iam.googleapis.com
```

### Step 1. OIDC Setup

Follow this article on how to setup [GitHub Actions with OIDC](https://medium.com/@prasad.reddy0708/authenticate-to-google-cloud-gcp-from-github-actions-using-oidc-and-workload-identity-federation-2a6c6b56c29f)

### Step 2. Grant required IAM permissions to Service Account that is created during OIDC setup

Grant Service Account used with OIDC setup the minimum runtime roles you need. At a minimum, Cloud Run services typically need pull access to Artifact Registry and any other resources your app uses.

```bash
gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:cloud-run-runtime-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

If your app needs access to additional GCP services, grant only the roles required for those services.

```bash
gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"
```

If your workflow uses Cloud Build instead of building in GitHub Actions, also add:

```bash
gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"
```

## Step 3: Create an Artifact Registry Docker repository

```bash
gcloud artifacts repositories create react-app-repo \
  --repository-format=docker \
  --location=YOUR_REGION \
  --description="Docker repo for React app images"
```

## Step 6: Configure GitHub repository secrets

Recommended secrets:

- `GCP_PROJECT_ID` = `YOUR_GCP_PROJECT_ID`
- `GCP_REGION` = `YOUR_REGION`
- `GCP_CLOUD_RUN_SERVICE_NAME` = `YOUR_CLOUD_RUN_SERVICE_NAME`
- `IMAGE_NAME` = `DOCKER_IMAGE_NAME`
- `IMAGE_TAG` = `DOCKER_IMAGE_TAG`
- `ARTIFACT_REPO_NAME` = `YOUR_DOCKER_ARTIFACT_REPOSITORY_NAME`
- `GCP_SERVICE_ACCOUNT` = `SERVICE_ACCOUNT_EMAIL_USED_WITH_OIDC`
- `GCP_WORKLOAD_IDENTITY_PROVIDER` = `GCP_WORKLOAD_IDENTITY_PROVIDER_VALUE`

Use below command to get GCP_WORKLOAD_IDENTITY_PROVIDER_VALUE

```bash
gcloud iam workload-identity-pools providers describe GITHUB_OIDC_PROVIDER_NAME \
    --workload-identity-pool=WORKLOAD_IDENTITY_POOL_NAME \
    --location=global \
    --project=GCP_PROJECT_ID \
    --format="value(name)"
```

## Step 8: Cloud Run service configuration

If your React app needs environment variables, add them to the deploy command.

```bash
  --set-env-vars "REACT_APP_API_URL=https://api.example.com"
```

For multiple variables, separate them with commas:

```bash
  --set-env-vars "REACT_APP_API_URL=https://api.example.com,REACT_APP_FEATURE_FLAG=true,REACT_APP_ANALYTICS_ID=UA-12345678"
```

To allow public access to the Cloud Run service:

```bash
gcloud run services add-iam-policy-binding ${{ secrets.CLOUD_RUN_SERVICE }} \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --region=${{ secrets.GCP_REGION }}
```

## Appendix: IAM role summary

### GitHub Actions deployment identity

- `roles/run.admin`
- `roles/iam.serviceAccountUser`
- `roles/artifactregistry.writer`
- `roles/cloudbuild.builds.builder` _(optional, only if using Cloud Build)_
- `roles/iam.workloadIdentityUser` on the deploy service account for the GitHub OIDC provider

## Troubleshooting

- Ensure `permissions.id-token: write` is enabled in your GitHub Actions workflow.
- Confirm the OIDC provider issuer URI is `https://token.actions.githubusercontent.com`.
- Verify the `principalSet://.../attribute.repository/OWNER/REPO` member matches your repository path exactly.
- If deployment fails with permission errors, confirm the Service Account IAM binding and Workload Identity permission.
- Use `gcloud auth print-identity-token` locally to inspect identity-token issuance.
