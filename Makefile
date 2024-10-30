SPANNER_INSTANCE := test-instance
SPANNER_DATABASE := game
SPANNER_STRING := projects/$(GOOGLE_CLOUD_PROJECT)/instances/$(SPANNER_INSTANCE)/databases/$(SPANNER_DATABASE)
REGION := asia-northeast1
ZONE := asia-northeast1-a
SA := game-api@$(GOOGLE_CLOUD_PROJECT).iam.gserviceaccount.com
VA := projects/$(GOOGLE_CLOUD_PROJECT)/locations/$(REGION)/connectors/game-api-vpc-access

.PHONY: all
all: infra schema repo
	( cd terraform/; terraform output )

.PHONY: infra
infra:
	@echo "Preparing Infrastructures by applying terraform"
	( cd terraform/; terraform apply -auto-approve )

.PHONY: schema
schema:
	@echo "Creating schemas to Cloud Spanner databse $(SPANNER_DATABASE) at $(SPANNER_DATABASE)"
	for schema in schemas/*ddl.sql schemas/*dml.sql ; do spanner-cli -i $(SPANNER_INSTANCE) -d $(SPANNER_DATABASE) -p $(GOOGLE_CLOUD_PROJECT) < $${schema} ; done

.PHONY: app
REDIS_HOST := $(shell ( cd terraform; terraform output -raw redis_private_ip_in_vpc ) )
app:
	@echo "Building and Deploying Cloud Run service"
	gcloud run deploy game-api --allow-unauthenticated --region=$(REGION) --set-env-vars=GOOGLE_CLOUD_PROJECT=$(GOOGLE_CLOUD_PROJECT),SPANNER_STRING=$(SPANNER_STRING),REDIS_HOST=$(REDIS_HOST) --vpc-connector=$(VA) --service-account=$(SA) --cpu-throttling --source=. --quiet

.PHONY: repo
repo:
	gcloud artifacts repositories create --repository-format=docker --location=$(REGION) my-app
	gcloud auth configure-docker $(REGION)-docker.pkg.dev

.PHONY: clean
clean:
	@echo "Cleanup states of terraform that were created previously"
	rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup

.PHONY: build-sa
CLOUDBUILD_SA:=$(shell gcloud builds get-default-service-account | grep gserviceaccount | cut -d / -f 4)
build-sa:
	@echo "Grant some authorizations to the service account for Cloud Build"

	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
	--member=serviceAccount:$(CLOUDBUILD_SA) \
	--role=roles/artifactregistry.repoAdmin

	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
	--member=serviceAccount:$(CLOUDBUILD_SA) \
	--role=roles/cloudbuild.builds.builder

	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
	--member=serviceAccount:$(CLOUDBUILD_SA) \
	--role=roles/run.admin

	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
	--member=serviceAccount:$(CLOUDBUILD_SA) \
	--role=roles/storage.admin
