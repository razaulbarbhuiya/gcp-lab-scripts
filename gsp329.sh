#!/bin/bash

clear

echo "======================================"
echo "Use ML APIs on Google Cloud Challenge"
echo "======================================"

PROJECT_ID=$(gcloud config get-value project)

echo ""
echo "Project ID: $PROJECT_ID"

echo ""
echo "Enter TARGET LANGUAGE (example: en)"
read TARGET_LANG

echo ""
echo "Enter TARGET LOCALE (example: en_US or fr)"
read TARGET_LOCALE

SA_NAME=ml-api-sa

echo ""
echo "Enabling APIs..."

gcloud services enable vision.googleapis.com \
translate.googleapis.com \
bigquery.googleapis.com \
cloudtranslate.googleapis.com

echo ""
echo "Creating Service Account..."

gcloud iam service-accounts create $SA_NAME

SA_EMAIL=$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

echo ""
echo "Adding IAM roles..."

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/storage.objectAdmin"

echo ""
echo "Creating key..."

gcloud iam service-accounts keys create key.json \
--iam-account=$SA_EMAIL

export GOOGLE_APPLICATION_CREDENTIALS=key.json

echo ""
echo "Downloading starter script..."

gsutil cp gs://$PROJECT_ID/analyze-images-v2.py .

echo ""
echo "Installing dependencies..."

pip3 install google-cloud-vision \
google-cloud-translate \
google-cloud-storage \
google-cloud-bigquery \
pandas pandas-gbq -q

echo ""
echo "Patching Python script..."

sed -i "s/# TBD: CALL THE VISION API/response = vision_client.text_detection(image=image)\n    texts = response.text_annotations/g" analyze-images-v2.py

sed -i "s/# TBD: GET TEXT FROM IMAGE/text = texts\[0\].description/g" analyze-images-v2.py

sed -i "s/# TBD: TRANSLATE TEXT/result = translate_client.translate(text,target_language='$TARGET_LANG')\n        translation = result\['translatedText'\]/g" analyze-images-v2.py

sed -i "s/#df.to_gbq/df.to_gbq/g" analyze-images-v2.py

echo ""
echo "Running script..."

python3 analyze-images-v2.py

echo ""
echo "Running validation query..."

bq query --use_legacy_sql=false \
'SELECT locale,COUNT(locale) as lcount FROM image_classification_dataset.image_text_detail GROUP BY locale ORDER BY lcount DESC'

echo ""
echo "Lab completed."
