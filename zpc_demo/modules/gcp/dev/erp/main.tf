
provider "google" {
  project = "cwp-sales-c-proj-2"
  region  = "us-central1"
  zone    = "us-central1-c"
}

##### Variables for the entire project: 

variable "environment" {
  default = "dev"
}

variable "region" {
  default = "us-central1"
}

variable "project" {
  default = "cwp-sales-c-proj-2"
}


##### Cloud function specific resources:


resource "google_storage_bucket" "function_bucket" {
    name     = "cloudstor-erpfunc-${var.environment}-${var.region}"
    location = var.region
}

resource "google_storage_bucket" "input_bucket" {
    name     = "cloudstor-erpinput-${var.environment}-${var.region}"
    location = var.region
}


data "archive_file" "source" {
    type        = "zip"
    source_dir  = "./modules/gcp/dev/erp/src/"
    output_path = "/tmp/function.zip"
}

resource "google_storage_bucket_object" "zip" {
    source       = data.archive_file.source.output_path
    content_type = "application/zip"

    # Append to the MD5 checksum of the files's content
    # to force the zip to be updated as soon as a change occurs
    name         = "src-${data.archive_file.source.output_md5}.zip"
    bucket       = google_storage_bucket.function_bucket.name

    # Dependencies are automatically inferred so these lines can be deleted if desired.
    depends_on   = [
        google_storage_bucket.function_bucket, 
        data.archive_file.source
    ]
}


resource "google_cloudfunctions_function" "function" {
    name                  = "function-trigger-on-gcs"
    runtime               = "python37" 

    # Get the source code of the cloud function as a Zip compression
    source_archive_bucket = google_storage_bucket.function_bucket.name
    source_archive_object = google_storage_bucket_object.zip.name

    # Must match the function name in the cloud function `main.py` source code
    entry_point           = "hello_gcs"
    
    # 
    event_trigger {
        event_type = "google.storage.object.finalize"
        resource   = google_storage_bucket.input_bucket.name
    }

    /*
    # Dependencies are automatically inferred so these lines can be deleted if desired.
    depends_on            = [
        google_storage_bucket.function_bucket,  
        google_storage_bucket_object.zip
    ]

    */
}


resource "google_compute_instance" "gce-erp" {
  count = 5
  name         = "vm-erp-${var.environment}-${var.region}-${count.index}"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }

  network_interface {
    # A default network is created for all GCP projects
    network = "default"
    access_config {
    }
  }
}


resource "google_bigquery_dataset" "bigq-erp-public" {

  dataset_id                  = "public"
  friendly_name               = "bigq-erp-${var.environment}-${var.region}-public"
  description                 = "ERP DB Public"
  location                    = "EU"
  default_table_expiration_ms = 3600000

  labels = {
    env = "default"
  }

  access {
    role          = "OWNER"
    user_by_email = google_service_account.bigqowner.email
  }

  access {
    role   = "READER"
    domain = "safemarch.com"
  }
}

resource "google_bigquery_dataset" "bigq-erp-private" {
  count = 1
  dataset_id                  = "private"
  friendly_name               = "bigq-erp-${var.environment}-${var.region}-${count.index}-private"
  description                 = "ERP DB Private"
  location                    = "EU"
  default_table_expiration_ms = 3600000

  labels = {
    env = "default"
  }

  access {
    role          = "OWNER"
    user_by_email = google_service_account.bigqowner.email
  }

  access {
    role   = "READER"
    domain = "safemarch.com"
  }

  access {
    dataset {
      dataset {
        project_id = google_bigquery_dataset.bigq-erp-public.project
        dataset_id = google_bigquery_dataset.bigq-erp-public.dataset_id
      }
      target_types = ["VIEWS"]
    }
  }
}

resource "google_service_account" "bigqowner" {
  account_id = "bigqowner"
}


resource "google_service_account" "k8sadmin" {
  account_id   = "k8sadmin"
  display_name = "Kubernetes Admin Service Account"
}

resource "google_container_cluster" "primary" {
  count = 2
  name               = "gke-erp-${var.environment}-${var.region}-${count.index}"
  location           = "${var.region}"
  initial_node_count = 1
  node_config {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.k8sadmin.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    labels = {
      env = "${var.environment}"
    }
    tags = ["environment", "${var.environment}"]
  }
  timeouts {
    create = "30m"
    update = "40m"
  }
}




locals {
  onprem = ["192.168.1.0/24", "192.168.2.0/24"]
}

resource "google_sql_database_instance" "postgres" {
  count = 2
  name             = "pgsql-erp-${var.environment}-${var.region}-${count.index}"
  database_version = "POSTGRES_11"

  settings {
    tier = "db-f1-micro"

    ip_configuration {

      dynamic "authorized_networks" {
        for_each = google_compute_instance.gce-erp
        iterator = gce-erp

        content {
          name  = gce-erp.value.name
          value = gce-erp.value.network_interface.0.access_config.0.nat_ip
        }
      }


    
    }
  }
}


resource "google_storage_bucket" "cloudstor-erp" {
  count = 5
  name          = "cloudstor-erp-${var.environment}-${var.region}-${count.index}"
  location      = "US"
  force_destroy = true

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  cors {
    origin          = ["http://safemarch.com"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}


##### Container registry resources:

resource "google_container_registry" "registry" {
  location = "EU"
}

