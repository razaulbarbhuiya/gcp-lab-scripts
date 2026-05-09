#!/bin/bash

clear

echo "======================================"
echo "Use ML APIs on Google Cloud Challenge"
echo "======================================"

PROJECT_ID=$(gcloud config get-value project)

echo "Project ID: $PROJECT_ID"

LANGUAGE="French"
LOCALE="fr"

SA_NAME="ml-api-sa"

echo ""
echo "Enabling APIs..."

gcloud services enable vision.googleapis.com
gcloud services enable translate.googleapis.com
gcloud services enable bigquery.googleapis.com

echo ""
echo "Creating Service Account..."

gcloud iam service-accounts create $SA_NAME --quiet

SA_EMAIL=$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

echo ""
echo "Adding IAM Roles..."

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/bigquery.dataEditor" --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/storage.objectAdmin" --quiet

echo ""
echo "Creating key..."

gcloud iam service-accounts keys create key.json \
--iam-account=$SA_EMAIL --quiet

export GOOGLE_APPLICATION_CREDENTIALS=key.json

echo ""
echo "Downloading analyze-images-v2.py ..."

gsutil cp gs://$PROJECT_ID/analyze-images-v2.py .

echo ""
echo "Installing dependencies..."

pip3 install google-cloud-vision \
google-cloud-translate \
google-cloud-storage \
google-cloud-bigquery \
pandas pandas-gbq -q

echo ""
echo "Patching script..."

sed -i "/# TBD:/c\    response = vision_client.text_detection(image=image)\n    texts = response.text_annotations" analyze-images-v2.py

sed -i "/# TBD:/c\    text = texts[0].description" analyze-images-v2.py

sed -i "/# TBD:/c\        result = translate_client.translate(text, target_language='en')\n        translation = result['translatedText']" analyze-images-v2.py

sed -i "s/#df.to_gbq/df.to_gbq/g" analyze-images-v2.py

echo ""
echo "Running Python script..."

python3 analyze-images-v2.py $PROJECT_ID $PROJECT_ID

echo ""
echo "Running BigQuery validation..."

bq query --use_legacy_sql=false \
'SELECT locale,COUNT(locale) as lcount FROM image_classification_dataset.image_text_detail GROUP BY locale ORDER BY lcount DESC'

echo ""
echo "Challenge Lab Completed"
