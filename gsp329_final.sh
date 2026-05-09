#!/bin/bash

echo "========================================"
echo "   GSP329 - Use ML APIs Challenge Lab   "
echo "========================================"

export PROJECT_ID=$(gcloud config get-value project)
export SA_NAME="ml-api-sa"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export KEY_FILE="key.json"

echo "Project: $PROJECT_ID"
echo "SA Email: $SA_EMAIL"
echo ""

# Read roles from lab panel - change these if your lab shows different values
export BQ_ROLE="roles/bigquery.dataEditor"
export STORAGE_ROLE="roles/storage.admin"

# TASK 1: Delete old SA if exists, then recreate fresh
echo ">>> TASK 1: Setting up service account..."

# Delete existing SA keys and SA to start clean
gcloud iam service-accounts delete $SA_EMAIL --quiet 2>/dev/null || true
sleep 3

# Create fresh
gcloud iam service-accounts create $SA_NAME \
  --display-name="ML API Service Account" \
  --project=$PROJECT_ID

echo "Waiting for SA to propagate..."
sleep 5

# Bind roles
echo "Binding $BQ_ROLE ..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="$BQ_ROLE"

echo "Binding $STORAGE_ROLE ..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="$STORAGE_ROLE"

echo "Task 1 done"; echo ""

# TASK 2: Generate key
echo ">>> TASK 2: Creating key.json..."
rm -f $KEY_FILE
gcloud iam service-accounts keys create $KEY_FILE --iam-account=$SA_EMAIL
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/$KEY_FILE
echo "Task 2 done"; echo ""

# Find bucket
echo ">>> Finding storage bucket..."
BUCKET=$(gcloud storage buckets list --format="value(name)" | grep "$PROJECT_ID" | head -1)
[ -z "$BUCKET" ] && BUCKET=$(gcloud storage buckets list --format="value(name)" | head -1)
echo "Bucket: gs://$BUCKET"
export BUCKET
echo ""

# Enable APIs
echo ">>> Enabling APIs..."
gcloud services enable vision.googleapis.com translate.googleapis.com bigquery.googleapis.com storage.googleapis.com --quiet
echo "APIs enabled"; echo ""

# Install packages
echo ">>> Installing Python packages..."
pip install -q google-cloud-vision google-cloud-translate google-cloud-bigquery google-cloud-storage
echo "Packages installed"; echo ""

# Download Python script
echo ">>> Downloading run_ml.py..."
curl -sL "https://raw.githubusercontent.com/razaulbarbhuiya/gcp-lab-scripts/main/run_ml.py" -o run_ml.py
if [ ! -s run_ml.py ]; then
  echo "Download failed - please upload run_ml.py manually to Cloud Shell"
  exit 1
fi
echo "run_ml.py ready"; echo ""

# Run pipeline
echo ">>> Running ML pipeline (Tasks 3, 4, 5)..."
echo ""
GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/$KEY_FILE \
BUCKET=$BUCKET \
python3 run_ml.py

echo ""
echo "========================================"
echo "  DONE - Click Check my progress now   "
echo "========================================"
