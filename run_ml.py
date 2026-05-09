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

# Create dataset
try:
    bqc.get_dataset(f"{PROJECT_ID}.{DATASET}")
    print(f"Dataset already exists")
except Exception:
    ds = bigquery.Dataset(f"{PROJECT_ID}.{DATASET}")
    ds.location = "US"
    bqc.create_dataset(ds)
    print(f"Dataset created")

# Create table
schema = [
    bigquery.SchemaField("file_name",       "STRING", mode="REQUIRED"),
    bigquery.SchemaField("recognized_text", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("locale",          "STRING", mode="REQUIRED"),
    bigquery.SchemaField("translated_text", "STRING", mode="REQUIRED"),
]
try:
    bqc.get_table(f"{PROJECT_ID}.{DATASET}.{TABLE}")
    print(f"Table already exists")
except Exception:
    t = bigquery.Table(f"{PROJECT_ID}.{DATASET}.{TABLE}", schema=schema)
    bqc.create_table(t)
    print(f"Table created")

# Process images
bucket = sc.get_bucket(BUCKET_NAME)
blobs  = list(bucket.list_blobs())
print(f"\nFound {len(blobs)} objects in bucket")

IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")

for blob in blobs:
    if not blob.name.lower().endswith(IMAGE_EXTS):
        continue

    print(f"\nProcessing: {blob.name}")

    img = vision.Image()
    img.source.image_uri = f"gs://{BUCKET_NAME}/{blob.name}"
    resp  = vc.document_text_detection(image=img)
    texts = resp.text_annotations

    if not texts:
        print("  No text found, skipping")
        continue

    text_data = texts[0].description
    print(f"  Extracted: {text_data[:60]}...")

    txt_blob = bucket.blob(os.path.splitext(blob.name)[0] + ".txt")
    txt_blob.upload_from_string(text_data)
    print(f"  Saved txt file to bucket")

    det    = tc.detect_language(text_data)
    locale = det["language"]
    print(f"  Language detected: {locale}")

    if locale != "fr":
        translated_text = tc.translate(text_data, target_language="fr")["translatedText"]
        print(f"  Translated to French: {translated_text[:60]}...")
    else:
        translated_text = text_data
        print("  Already French, no translation needed")

    errs = bqc.insert_rows_json(
        f"{PROJECT_ID}.{DATASET}.{TABLE}",
        [{"file_name": blob.name,
          "recognized_text": text_data,
          "locale": locale,
          "translated_text": translated_text}]
    )
    if errs:
        print(f"  BigQuery error: {errs}")
    else:
        print("  Saved to BigQuery")

print("\nAll images processed!")

# Task 5: language frequency
print("\nTask 5 - Language frequency report:")
print("-" * 40)
q = f"SELECT locale, COUNT(locale) AS n FROM `{PROJECT_ID}.{DATASET}.{TABLE}` GROUP BY locale ORDER BY n DESC"
for row in bqc.query(q).result():
    print(f"  Language: {row.locale}  |  Count: {row.n}")

print("\nAll tasks complete! Click Check my progress for each task.")
