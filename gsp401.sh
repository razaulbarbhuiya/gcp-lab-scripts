#!/bin/bash

REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$REGION" ]; then
REGION="us-central1"
fi

gcloud config set compute/region $REGION

gcloud services enable cloudscheduler.googleapis.com

gcloud pubsub topics create cron-topic

gcloud pubsub subscriptions create cron-sub \
--topic cron-topic

gcloud scheduler jobs create pubsub cron-job \
--schedule="* * * * *" \
--topic=cron-topic \
--message-body="hello cron!" \
--location=$REGION

sleep 90

gcloud pubsub subscriptions pull cron-sub \
--limit=5 \
--auto-ack

echo "Lab Completed"
