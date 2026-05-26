# GCP Service Commands Reference

## Table of Contents

- [Compute Engine](#compute-engine)
- [Cloud Storage](#cloud-storage)
- [Cloud Run](#cloud-run)
- [Google Kubernetes Engine (GKE)](#google-kubernetes-engine-gke)
- [IAM & Service Accounts](#iam--service-accounts)
- [App Engine](#app-engine)
- [Cloud Functions](#cloud-functions)
- [Cloud SQL](#cloud-sql)
- [BigQuery](#bigquery)
- [Pub/Sub](#pubsub)
- [Artifact Registry / Container Registry](#artifact-registry--container-registry)
- [Secrets Manager](#secrets-manager)
- [Networking / VPC](#networking--vpc)

---

## Compute Engine

```bash
# Instances
gcloud compute instances list
gcloud compute instances create VM_NAME \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --zone=us-central1-a

gcloud compute instances start|stop|delete VM_NAME --zone=ZONE
gcloud compute instances describe VM_NAME --zone=ZONE

# SSH
gcloud compute ssh VM_NAME --zone=ZONE
gcloud compute ssh VM_NAME --zone=ZONE -- "command to run"

# Copy files
gcloud compute scp local_file VM_NAME:remote_path --zone=ZONE

# Instance groups / managed
gcloud compute instance-groups managed list
gcloud compute instance-groups managed resize GROUP --size=3 --zone=ZONE

# Disks
gcloud compute disks list
gcloud compute disks create DISK_NAME --size=100GB --zone=ZONE
```

---

## Cloud Storage

> Use `gcloud storage` (newer) or `gsutil` (classic) — both work.

```bash
# Buckets
gcloud storage buckets create gs://BUCKET_NAME --location=us-central1
gcloud storage buckets list
gcloud storage buckets delete gs://BUCKET_NAME

# Objects
gcloud storage cp LOCAL_FILE gs://BUCKET/path
gcloud storage cp gs://BUCKET/path LOCAL_FILE
gcloud storage ls gs://BUCKET/
gcloud storage rm gs://BUCKET/path
gcloud storage mv gs://BUCKET/old gs://BUCKET/new

# Recursive copy
gcloud storage cp -r ./local-dir gs://BUCKET/dest/
gcloud storage rsync -r gs://BUCKET/src gs://BUCKET/dest

# ACL / public access
gcloud storage objects update gs://BUCKET/file --add-acl-grant=entity=AllUsers,role=READER

# gsutil equivalents (still widely used)
gsutil cp LOCAL gs://BUCKET/
gsutil -m cp -r ./dir gs://BUCKET/
gsutil ls -la gs://BUCKET/
gsutil du -sh gs://BUCKET/
```

---

## Cloud Run

```bash
# Deploy from image
gcloud run deploy SERVICE_NAME \
  --image=IMAGE_URL \
  --region=us-central1 \
  --platform=managed \
  --allow-unauthenticated

# Deploy from source (buildpacks)
gcloud run deploy SERVICE_NAME \
  --source=. \
  --region=us-central1

# List / describe
gcloud run services list --region=us-central1
gcloud run services describe SERVICE_NAME --region=us-central1

# Get service URL
gcloud run services describe SERVICE_NAME --region=us-central1 --format="value(status.url)"

# Update environment variables
gcloud run services update SERVICE_NAME \
  --set-env-vars KEY=VALUE,KEY2=VALUE2 \
  --region=us-central1

# Set concurrency / memory / CPU
gcloud run services update SERVICE_NAME \
  --memory=512Mi \
  --cpu=1 \
  --concurrency=80 \
  --region=us-central1

# Traffic splitting
gcloud run services update-traffic SERVICE_NAME \
  --to-revisions=REVISION=50,REVISION2=50 \
  --region=us-central1

# View logs
gcloud run services logs read SERVICE_NAME --region=us-central1

# Delete
gcloud run services delete SERVICE_NAME --region=us-central1
```

---

## Google Kubernetes Engine (GKE)

```bash
# Clusters
gcloud container clusters list
gcloud container clusters create CLUSTER_NAME \
  --zone=us-central1-a \
  --num-nodes=3 \
  --machine-type=e2-standard-2

gcloud container clusters create-auto CLUSTER_NAME \
  --region=us-central1

# Get credentials (populates ~/.kube/config)
gcloud container clusters get-credentials CLUSTER_NAME --zone=us-central1-a

gcloud container clusters delete CLUSTER_NAME --zone=us-central1-a

# Node pools
gcloud container node-pools list --cluster=CLUSTER_NAME --zone=ZONE
gcloud container node-pools create POOL_NAME \
  --cluster=CLUSTER_NAME \
  --num-nodes=2 \
  --machine-type=n2-standard-4 \
  --zone=ZONE

# Upgrade
gcloud container clusters upgrade CLUSTER_NAME \
  --master \
  --cluster-version=1.29

# Images in registry
gcloud container images list --repository=gcr.io/PROJECT_ID
```

---

## IAM & Service Accounts

```bash
# List roles / permissions
gcloud iam roles list
gcloud iam roles describe roles/storage.admin

# Project-level IAM
gcloud projects get-iam-policy PROJECT_ID
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:user@example.com" \
  --role="roles/editor"
gcloud projects remove-iam-policy-binding PROJECT_ID \
  --member="user:user@example.com" \
  --role="roles/editor"

# Service accounts
gcloud iam service-accounts list
gcloud iam service-accounts create SA_NAME \
  --display-name="My SA" \
  --project=PROJECT_ID

gcloud iam service-accounts keys create key.json \
  --iam-account=SA_NAME@PROJECT.iam.gserviceaccount.com

gcloud iam service-accounts delete SA_EMAIL

# Grant SA access to a resource
gcloud storage buckets add-iam-policy-binding gs://BUCKET \
  --member="serviceAccount:SA_EMAIL" \
  --role="roles/storage.objectAdmin"

# Workload Identity (GKE pods)
gcloud iam service-accounts add-iam-policy-binding SA_EMAIL \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]"
```

---

## App Engine

```bash
# Deploy
gcloud app deploy [app.yaml]
gcloud app deploy --version=v2 --no-promote

# Traffic management
gcloud app services set-traffic default \
  --splits=v1=0.5,v2=0.5

# Browse
gcloud app browse

# Logs
gcloud app logs tail -s default

# Services / versions
gcloud app services list
gcloud app versions list --service=default
gcloud app versions delete VERSION --service=default
```

---

## Cloud Functions

```bash
# Deploy (gen2 recommended)
gcloud functions deploy FUNCTION_NAME \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=myFunction \
  --trigger-http \
  --allow-unauthenticated

# Trigger types
--trigger-http
--trigger-topic=PUBSUB_TOPIC
--trigger-bucket=BUCKET_NAME
--trigger-event-filters="type=google.cloud.storage.object.v1.finalized"

# Call a function
gcloud functions call FUNCTION_NAME --region=us-central1 --data='{"key":"value"}'

# List / describe
gcloud functions list --region=us-central1
gcloud functions describe FUNCTION_NAME --region=us-central1

# Logs
gcloud functions logs read FUNCTION_NAME --region=us-central1

# Delete
gcloud functions delete FUNCTION_NAME --region=us-central1
```

---

## Cloud SQL

```bash
# Instances
gcloud sql instances list
gcloud sql instances create INSTANCE_NAME \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=us-central1

gcloud sql instances describe INSTANCE_NAME
gcloud sql instances patch INSTANCE_NAME --activation-policy=ALWAYS

# Connect
gcloud sql connect INSTANCE_NAME --user=postgres --database=mydb

# Databases
gcloud sql databases list --instance=INSTANCE_NAME
gcloud sql databases create DB_NAME --instance=INSTANCE_NAME

# Users
gcloud sql users list --instance=INSTANCE_NAME
gcloud sql users set-password USER --instance=INSTANCE_NAME --password=NEW_PASS

# Import/Export
gcloud sql export sql INSTANCE_NAME gs://BUCKET/dump.sql --database=DB_NAME
gcloud sql import sql INSTANCE_NAME gs://BUCKET/dump.sql --database=DB_NAME

# Cloud SQL Proxy (local connection)
./cloud-sql-proxy PROJECT:REGION:INSTANCE
```

---

## BigQuery

> Use `bq` CLI (bundled with gcloud SDK) for BigQuery.

```bash
# Datasets
bq ls
bq mk DATASET_NAME
bq rm -r DATASET_NAME

# Tables
bq ls DATASET_NAME
bq show PROJECT:DATASET.TABLE
bq mk --table DATASET.TABLE schema.json

# Query
bq query --use_legacy_sql=false 'SELECT * FROM `project.dataset.table` LIMIT 10'
bq query --use_legacy_sql=false --format=prettyjson 'SELECT ...'

# Load data
bq load --source_format=CSV DATASET.TABLE gs://BUCKET/file.csv schema.json
bq load --autodetect --source_format=NEWLINE_DELIMITED_JSON DATASET.TABLE gs://BUCKET/*.json

# Extract
bq extract DATASET.TABLE gs://BUCKET/export-*.csv

# Jobs
bq ls -j -a   # list all jobs
bq show -j JOB_ID
```

---

## Pub/Sub

```bash
# Topics
gcloud pubsub topics list
gcloud pubsub topics create TOPIC_NAME
gcloud pubsub topics delete TOPIC_NAME

# Publish
gcloud pubsub topics publish TOPIC_NAME --message="hello world"
gcloud pubsub topics publish TOPIC_NAME --message='{"key":"val"}' \
  --attribute="origin=test,environment=dev"

# Subscriptions
gcloud pubsub subscriptions list
gcloud pubsub subscriptions create SUB_NAME --topic=TOPIC_NAME
gcloud pubsub subscriptions create SUB_NAME \
  --topic=TOPIC_NAME \
  --push-endpoint=https://my-app.example.com/push

# Pull messages
gcloud pubsub subscriptions pull SUB_NAME --auto-ack --limit=10

# Dead-letter
gcloud pubsub subscriptions modify-config SUB_NAME \
  --dead-letter-topic=DEAD_LETTER_TOPIC \
  --max-delivery-attempts=5
```

---

## Artifact Registry / Container Registry

```bash
# Create repo
gcloud artifacts repositories create REPO_NAME \
  --repository-format=docker \
  --location=us-central1

# List repos / images
gcloud artifacts repositories list --location=us-central1
gcloud artifacts docker images list us-central1-docker.pkg.dev/PROJECT/REPO

# Auth Docker to Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev

# Push image
docker tag my-image us-central1-docker.pkg.dev/PROJECT/REPO/my-image:tag
docker push us-central1-docker.pkg.dev/PROJECT/REPO/my-image:tag

# Delete image
gcloud artifacts docker images delete us-central1-docker.pkg.dev/PROJECT/REPO/IMAGE:TAG

# Container Registry (legacy gcr.io)
gcloud auth configure-docker
docker push gcr.io/PROJECT/image:tag
gcloud container images list --repository=gcr.io/PROJECT
gcloud container images delete gcr.io/PROJECT/IMAGE:TAG
```

---

## Secrets Manager

```bash
# Create secret
gcloud secrets create SECRET_NAME --replication-policy=automatic
echo -n "my-secret-value" | gcloud secrets versions add SECRET_NAME --data-file=-

# From file
gcloud secrets versions add SECRET_NAME --data-file=./secret.txt

# Access
gcloud secrets versions access latest --secret=SECRET_NAME

# List versions
gcloud secrets versions list SECRET_NAME

# Disable / destroy version
gcloud secrets versions disable VERSION_ID --secret=SECRET_NAME
gcloud secrets versions destroy VERSION_ID --secret=SECRET_NAME

# Grant access
gcloud secrets add-iam-policy-binding SECRET_NAME \
  --member="serviceAccount:SA_EMAIL" \
  --role="roles/secretmanager.secretAccessor"
```

---

## Networking / VPC

```bash
# VPC Networks
gcloud compute networks list
gcloud compute networks create VPC_NAME --subnet-mode=custom

# Subnets
gcloud compute networks subnets list --network=VPC_NAME
gcloud compute networks subnets create SUBNET_NAME \
  --network=VPC_NAME \
  --range=10.0.0.0/24 \
  --region=us-central1

# Firewall rules
gcloud compute firewall-rules list
gcloud compute firewall-rules create RULE_NAME \
  --network=VPC_NAME \
  --allow=tcp:80,tcp:443 \
  --source-ranges=0.0.0.0/0

gcloud compute firewall-rules delete RULE_NAME

# Cloud NAT
gcloud compute routers create ROUTER_NAME \
  --network=VPC_NAME \
  --region=us-central1
gcloud compute routers nats create NAT_NAME \
  --router=ROUTER_NAME \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --region=us-central1

# Static IPs
gcloud compute addresses create IP_NAME --region=us-central1
gcloud compute addresses list
```
