````bash
# GitHub OIDC Authentication with GCP Cloud Run Deployment

This guide walks through the complete setup to deploy a React app from GitHub Actions to Google Cloud Run using Workload Identity Federation (OIDC) instead of service account keys.

## Prerequisites

1. Install and authenticate the Google Cloud CLI:

```bash
gcloud auth login
````

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

## Step 1: Create or choose a Cloud Run runtime service account

Create a dedicated service account for Cloud Run runtime access. This account is used by Cloud Run when your service executes.

```bash
gcloud iam service-accounts create cloud-run-runtime-sa \
  --display-name="Cloud Run runtime service account"
```

Grant it the minimum runtime roles you need. At a minimum, Cloud Run services typically need pull access to Artifact Registry and any other resources your app uses.

```bash
gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:cloud-run-runtime-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

If your app needs access to additional GCP services, grant only the roles required for those services.

## Step 2: Create the deployment service account for GitHub Actions

This service account is the identity GitHub Actions will impersonate via OIDC when deploying to Cloud Run.

```bash
gcloud iam service-accounts create github-actions-deploy-sa \
  --display-name="GitHub Actions deploy service account"
```

Grant the deploy service account the following roles:

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

## Step 4: Create a Workload Identity Pool and provider

A Workload Identity Pool lets GitHub authenticate to GCP using OIDC.

```bash
gcloud iam workload-identity-pools create github-pool \
  --project=YOUR_GCP_PROJECT_ID \
  --location="global" \
  --display-name="GitHub Actions pool"
```

Save the pool resource name from the output or build it manually:

```bash
POOL_ID=github-pool
POOL_RESOURCE="projects/YOUR_GCP_PROJECT_ID/locations/global/workloadIdentityPools/$POOL_ID"
```

Create the OIDC provider for GitHub Actions:

```bash
PROVIDER_ID=github-provider
gcloud iam workload-identity-pools providers create-oidc $PROVIDER_ID \
  --project=YOUR_GCP_PROJECT_ID \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --display-name="GitHub Actions OIDC provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --allowed-audiences="https://cloud.google.com/iam" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.workflow=assertion.workflow,attribute.ref=assertion.ref"
```

## Step 5: Allow GitHub to impersonate the deploy service account

Grant the GitHub OIDC identity the `roles/iam.workloadIdentityUser` role on the deployment service account.

```bash
SA_EMAIL=github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com
POOL_RESOURCE="projects/YOUR_GCP_PROJECT_ID/locations/global/workloadIdentityPools/$POOL_ID"
PROVIDER_RESOURCE="$POOL_RESOURCE/providers/$PROVIDER_ID"

cat > iam-policy.json <<'EOF'
{
  "bindings": [
    {
      "role": "roles/iam.workloadIdentityUser",
      "members": [
        "principalSet://$PROVIDER_RESOURCE/attribute.repository/OWNER/REPO"
      ]
    }
  ]
}
EOF

gcloud iam service-accounts set-iam-policy "$SA_EMAIL" iam-policy.json
rm iam-policy.json
```

Replace `OWNER/REPO` with your GitHub repository path, for example `vprasadreddy/react-app`.

> Tip: To restrict the binding to a specific branch, use `principalSet://$PROVIDER_RESOURCE/attribute.repository/OWNER/REPO/attribute.ref/ref:refs/heads/main`.

## Step 6: Configure GitHub repository secrets

You do not need a service account key when using OIDC. Recommended secrets:

- `GCP_PROJECT` = `YOUR_GCP_PROJECT_ID`
- `GCP_REGION` = `YOUR_REGION`
- `ARTIFACT_REGISTRY_REPO` = `YOUR_REGION-docker.pkg.dev/YOUR_GCP_PROJECT_ID/react-app-repo`
- `CLOUD_RUN_SERVICE` = `react-app-service`
- `GCP_SA_EMAIL` = `github-actions-deploy-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com`

## Step 7: GitHub Actions workflow

Create `.github/workflows/deploy-cloud-run.yml`:

```yaml
name: Deploy to Cloud Run

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    env:
      IMAGE_URI: ${{ secrets.ARTIFACT_REGISTRY_REPO }}/react-app:${{ github.sha }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: ${{ secrets.GCP_PROJECT }}
          service_account_email: ${{ secrets.GCP_SA_EMAIL }}
          workload_identity_provider: "projects/${{ secrets.GCP_PROJECT }}/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID"
          export_default_credentials: true

      - name: Configure Docker for Artifact Registry
        run: |
          gcloud auth configure-docker ${{ secrets.ARTIFACT_REGISTRY_REPO }} --quiet

      - name: Build container image
        run: |
          docker build -t "$IMAGE_URI" .

      - name: Push image to Artifact Registry
        run: |
          docker push "$IMAGE_URI"

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy ${{ secrets.CLOUD_RUN_SERVICE }} \
            --image "$IMAGE_URI" \
            --region ${{ secrets.GCP_REGION }} \
            --platform managed \
            --allow-unauthenticated \
            --service-account "cloud-run-runtime-sa@${{ secrets.GCP_PROJECT }}.iam.gserviceaccount.com"
```

If you instead prefer Cloud Build, replace the build and push steps with `gcloud builds submit`.

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

### Cloud Run runtime service account

- `roles/artifactregistry.reader`

## Troubleshooting

- Ensure `permissions.id-token: write` is enabled in your GitHub Actions workflow.
- Confirm the OIDC provider issuer URI is `https://token.actions.githubusercontent.com`.
- Verify the `principalSet://.../attribute.repository/OWNER/REPO` member matches your repository path exactly.
- If deployment fails with permission errors, confirm the Service Account IAM binding and Workload Identity permission.
- Use `gcloud auth print-identity-token` locally to inspect identity-token issuance.
