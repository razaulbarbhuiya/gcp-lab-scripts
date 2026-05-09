#!/bin/bash

echo "========================================"
echo "   GSP329 - Use ML APIs Challenge Lab   "
echo "========================================"

export PROJECT_ID=$(gcloud config get-value project)
export SA_NAME="ml-api-sa"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export KEY_FILE="key.json"
echo "Project: $PROJECT_ID"
echo ""

# TASK 1: Fix IAM roles
echo ">>> TASK 1: Fixing IAM roles..."
gcloud projects remove-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/bigquery.dataEditor" 2>/dev/null || true
gcloud projects remove-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.objectAdmin" 2>/dev/null || true
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/bigquery.dataOwner"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.admin"
echo "Task 1 done"; echo ""

# TASK 2: Generate key
echo ">>> TASK 2: Creating key.json..."
rm -f $KEY_FILE
gcloud iam service-accounts keys create $KEY_FILE --iam-account=$SA_EMAIL
echo "Task 2 done"; echo ""

# Find bucket
echo ">>> Finding storage bucket..."
BUCKET=$(gcloud storage buckets list --format="value(name)" | grep "$PROJECT_ID" | head -1)
[ -z "$BUCKET" ] && BUCKET=$(gcloud storage buckets list --format="value(name)" | head -1)
echo "Bucket: $BUCKET"; echo ""

# Enable APIs
echo ">>> Enabling APIs..."
gcloud services enable vision.googleapis.com translate.googleapis.com --quiet
echo ""

# Install packages
echo ">>> Installing packages..."
pip install -q google-cloud-vision google-cloud-translate google-cloud-bigquery google-cloud-storage
echo ""

# Download the Python helper from GitHub
echo ">>> Downloading Python pipeline script..."
curl -sL "https://raw.githubusercontent.com/razaulbarbhuiya/gcp-lab-scripts/main/run_ml.py" -o run_ml.py

# If download fails, generate it locally
if [ ! -s run_ml.py ]; then
  echo "Download failed, generating locally..."
  python3 /dev/stdin << 'PYEOF'
code = """
import os
from google.cloud import storage, bigquery, vision
from google.cloud import translate_v2 as translate

PROJECT_ID  = os.environ["GOOGLE_CLOUD_PROJECT"]
BUCKET_NAME = os.environ["BUCKET"]
DATASET     = "image_classification_dataset"
TABLE       = "image_text_detail"

print(f"Project: {PROJECT_ID}")
print(f"Bucket:  {BUCKET_NAME}")

sc  = storage.Client()
bqc = bigquery.Client()
vc  = vision.ImageAnnotatorClient()
tc  = translate.Client()

try:
    bqc.get_dataset(f"{PROJECT_ID}.{DATASET}")
except Exception:
    ds = bigquery.Dataset(f"{PROJECT_ID}.{DATASET}")
    ds.location = "US"
    bqc.create_dataset(ds)
    print("Dataset created")

schema = [
    bigquery.SchemaField("file_name",       "STRING", mode="REQUIRED"),
    bigquery.SchemaField("recognized_text", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("locale",          "STRING", mode="REQUIRED"),
    bigquery.SchemaField("translated_text", "STRING", mode="REQUIRED"),
]
try:
    bqc.get_table(f"{PROJECT_ID}.{DATASET}.{TABLE}")
except Exception:
    t = bigquery.Table(f"{PROJECT_ID}.{DATASET}.{TABLE}", schema=schema)
    bqc.create_table(t)
    print("Table created")

bucket = sc.get_bucket(BUCKET_NAME)
blobs  = list(bucket.list_blobs())
print(f"Found {len(blobs)} objects")
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")

for blob in blobs:
    if not blob.name.lower().endswith(IMAGE_EXTS):
        continue
    print(f"\\nProcessing: {blob.name}")
    img = vision.Image()
    img.source.image_uri = f"gs://{BUCKET_NAME}/{blob.name}"
    resp  = vc.document_text_detection(image=img)
    texts = resp.text_annotations
    if not texts:
        print("  No text")
        continue
    text_data = texts[0].description
    print(f"  Text: {text_data[:60]}")
    txt_blob = bucket.blob(os.path.splitext(blob.name)[0] + ".txt")
    txt_blob.upload_from_string(text_data)
    det    = tc.detect_language(text_data)
    locale = det["language"]
    print(f"  Language: {locale}")
    if locale != "fr":
        translated_text = tc.translate(text_data, target_language="fr")["translatedText"]
    else:
        translated_text = text_data
    errs = bqc.insert_rows_json(
        f"{PROJECT_ID}.{DATASET}.{TABLE}",
        [{"file_name": blob.name, "recognized_text": text_data,
          "locale": locale, "translated_text": translated_text}]
    )
    print("  Saved to BigQuery" if not errs else f"  Error: {errs}")

print("\\nAll images done!")
q = f\'\'\'SELECT locale, COUNT(locale) AS n FROM `{PROJECT_ID}.{DATASET}.{TABLE}` GROUP BY locale ORDER BY n DESC\'\'\'
print("\\nLanguage counts:")
for row in bqc.query(q).result():
    print(f"  {row.locale}: {row.n}")
print("\\nDone! Check your progress.")
"""
with open("run_ml.py", "w") as f:
    f.write(code)
print("run_ml.py written")
PYEOF
fi

echo ""; echo ">>> Running pipeline..."
GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/$KEY_FILE \
BUCKET=$BUCKET \
python3 run_ml.py

echo ""
echo "========================================"
echo "  DONE - Click Check my progress now   "
echo "========================================"
