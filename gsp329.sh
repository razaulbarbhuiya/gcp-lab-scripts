#!/bin/bash

PROJECT_ID=$(gcloud config get-value project)

gcloud services enable vision.googleapis.com
gcloud services enable translate.googleapis.com
gcloud services enable bigquery.googleapis.com

SA_NAME=ml-api-sa

gcloud iam service-accounts create $SA_NAME

SA_EMAIL=$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/bigquery.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/storage.admin"

gcloud iam service-accounts keys create key.json \
--iam-account=$SA_EMAIL

export GOOGLE_APPLICATION_CREDENTIALS=key.json

gsutil cp gs://$PROJECT_ID/analyze-images-v2.py .

cat > analyze-images-v2.py <<'EOF'
from google.cloud import vision
from google.cloud import translate_v2 as translate
from google.cloud import storage
from google.cloud import bigquery
import os

project_id = os.environ["GOOGLE_CLOUD_PROJECT"]
bucket_name = project_id

vision_client = vision.ImageAnnotatorClient()
translate_client = translate.Client()
storage_client = storage.Client()
bq_client = bigquery.Client()

bucket = storage_client.bucket(bucket_name)

rows_to_insert = []

blobs = bucket.list_blobs()

for blob in blobs:
    if blob.name.endswith(('.png', '.jpg', '.jpeg')):

        image = vision.Image()

        image.source.image_uri = f"gs://{bucket_name}/{blob.name}"

        response = vision_client.document_text_detection(image=image)

        texts = response.full_text_annotation

        extracted_text = texts.text.strip()

        locale = texts.pages[0].property.detected_languages[0].language_code if texts.pages else "unknown"

        translated_text = extracted_text

        if locale != "en":
            result = translate_client.translate(
                extracted_text,
                target_language="en"
            )
            translated_text = result["translatedText"]

        output_blob = bucket.blob(blob.name + ".txt")

        output_blob.upload_from_string(extracted_text)

        rows_to_insert.append({
            "source_file": blob.name,
            "locale": locale,
            "original_text": extracted_text,
            "translated_text": translated_text
        })

table_id = f"{project_id}.image_classification_dataset.image_text_detail"

errors = bq_client.insert_rows_json(table_id, rows_to_insert)

print("Completed")
print(errors)
EOF

pip3 install google-cloud-vision google-cloud-translate google-cloud-storage google-cloud-bigquery

python3 analyze-images-v2.py

bq query --use_legacy_sql=false \
'SELECT locale,COUNT(locale) as lcount FROM image_classification_dataset.image_text_detail GROUP BY locale ORDER BY lcount DESC'
