#!/bin/bash

echo "========================================"
echo "   GSP329 - Use ML APIs Challenge Lab   "
echo "========================================"

export PROJECT_ID=$(gcloud config get-value project)
export SERVICE_ACCOUNT_NAME="ml-api-sa"
export SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export KEY_FILE="key.json"

echo "Project: $PROJECT_ID"
echo ""

# ── TASK 1: Fix roles (assign correct ones) ───────────

echo ">>> TASK 1: Assigning correct IAM roles..."

# Remove wrong roles first, then add correct ones
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/bigquery.dataEditor" 2>/dev/null || true

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.objectAdmin" 2>/dev/null || true

# Add the CORRECT roles as specified in the lab
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/bigquery.dataOwner"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.admin"

echo "✓ Task 1 done - correct roles assigned"
echo ""

# ── TASK 2: Create key ────────────────────────────────

echo ">>> TASK 2: Generating credentials key..."
rm -f $KEY_FILE
gcloud iam service-accounts keys create $KEY_FILE \
  --iam-account=$SERVICE_ACCOUNT_EMAIL

export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/$KEY_FILE
export GOOGLE_CLOUD_PROJECT=$PROJECT_ID
echo "✓ Task 2 done - key.json created"
echo ""

# ── Find bucket ───────────────────────────────────────

echo ">>> Finding storage bucket..."
export BUCKET=$(gsutil ls | grep $PROJECT_ID | head -1 | sed 's|gs://||' | sed 's|/||')
if [ -z "$BUCKET" ]; then
  export BUCKET=$(gsutil ls | head -1 | sed 's|gs://||' | sed 's|/||')
fi
echo "Bucket: $BUCKET"
echo ""

# ── Enable APIs ───────────────────────────────────────

echo ">>> Enabling APIs..."
gcloud services enable vision.googleapis.com translate.googleapis.com --quiet
echo "✓ APIs enabled"
echo ""

# ── Install dependencies ──────────────────────────────

echo ">>> Installing Python packages..."
pip install -q google-cloud-vision google-cloud-translate google-cloud-bigquery google-cloud-storage
echo "✓ Packages installed"
echo ""

# ── TASK 3 & 4 & 5: Write the Python script ──────────

echo ">>> Writing Python script..."

cat > run_ml.py << PYEOF
import os
from google.cloud import storage, bigquery, vision
from google.cloud import translate_v2 as translate

PROJECT_ID = os.environ["GOOGLE_CLOUD_PROJECT"]
BUCKET_NAME = os.environ["BUCKET"]
DATASET = "image_classification_dataset"
TABLE = "image_text_detail"

print(f"Project: {PROJECT_ID}")
print(f"Bucket:  {BUCKET_NAME}")

# Clients
storage_client = storage.Client()
bq_client = bigquery.Client()
vision_client = vision.ImageAnnotatorClient()
translate_client = translate.Client()

# ── Create BigQuery dataset & table ──────────────────
try:
    bq_client.get_dataset(f"{PROJECT_ID}.{DATASET}")
    print(f"Dataset {DATASET} already exists")
except Exception:
    dataset = bigquery.Dataset(f"{PROJECT_ID}.{DATASET}")
    dataset.location = "US"
    bq_client.create_dataset(dataset)
    print(f"Dataset {DATASET} created")

schema = [
    bigquery.SchemaField("file_name",        "STRING", mode="REQUIRED"),
    bigquery.SchemaField("recognized_text",  "STRING", mode="REQUIRED"),
    bigquery.SchemaField("locale",           "STRING", mode="REQUIRED"),
    bigquery.SchemaField("translated_text",  "STRING", mode="REQUIRED"),
]

try:
    bq_client.get_table(f"{PROJECT_ID}.{DATASET}.{TABLE}")
    print(f"Table {TABLE} already exists")
except Exception:
    table = bigquery.Table(f"{PROJECT_ID}.{DATASET}.{TABLE}", schema=schema)
    bq_client.create_table(table)
    print(f"Table {TABLE} created")

# ── Process images ────────────────────────────────────
bucket = storage_client.get_bucket(BUCKET_NAME)
blobs = list(bucket.list_blobs())
print(f"\nFound {len(blobs)} objects in bucket")

IMAGE_EXTS = ('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')

for blob in blobs:
    if not blob.name.lower().endswith(IMAGE_EXTS):
        continue

    print(f"\n--- Processing: {blob.name} ---")

    # TASK 3: Vision API - extract text
    image = vision.Image()
    image.source.image_uri = f"gs://{BUCKET_NAME}/{blob.name}"
    response = vision_client.document_text_detection(image=image)
    texts = response.text_annotations

    if not texts:
        print(f"  No text found, skipping")
        continue

    text_data = texts[0].description
    print(f"  Extracted text: {text_data[:60]}...")

    # Save .txt file back to bucket
    txt_name = os.path.splitext(blob.name)[0] + ".txt"
    text_blob = bucket.blob(txt_name)
    text_blob.upload_from_string(text_data)
    print(f"  Saved: {txt_name}")

    # TASK 4: Translation API - detect + translate
    detection = translate_client.detect_language(text_data)
    locale = detection["language"]
    print(f"  Language detected: {locale}")

    if locale != "fr":
        result = translate_client.translate(text_data, target_language="fr")
        translated_text = result["translatedText"]
        print(f"  Translated to French: {translated_text[:60]}...")
    else:
        translated_text = text_data
        print(f"  Already French - no translation needed")

    # Insert into BigQuery
    errors = bq_client.insert_rows_json(
        f"{PROJECT_ID}.{DATASET}.{TABLE}",
        [{"file_name": blob.name,
          "recognized_text": text_data,
          "locale": locale,
          "translated_text": translated_text}]
    )
    if errors:
        print(f"  BigQuery error: {errors}")
    else:
        print(f"  ✓ Inserted into BigQuery")

print("\n\nAll images processed!")

# TASK 5: BigQuery query - language frequency
print("\n>>> TASK 5: Language frequency report:")
print("-" * 40)
query = f"""
SELECT locale, COUNT(locale) AS lcount
FROM \`{PROJECT_ID}.{DATASET}.{TABLE}\`
GROUP BY locale
ORDER BY lcount DESC
"""
for row in bq_client.query(query).result():
    print(f"  Language: {row.locale}  |  Count: {row.lcount}")

print("\n✓ All tasks complete! Click 'Check my progress' now.")
PYEOF

echo "✓ Python script written"
echo ""

# ── Run it ────────────────────────────────────────────

echo ">>> Running ML pipeline..."
echo ""
GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/$KEY_FILE \
BUCKET=$BUCKET \
python3 run_ml.py

echo ""
echo "========================================"
echo "   DONE! Check progress for all tasks  "
echo "========================================"
