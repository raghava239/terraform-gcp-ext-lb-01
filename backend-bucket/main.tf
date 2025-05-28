provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "default" {
  name                    = "public-content-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "default" {
  name          = "public-content-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.default.id
}

resource "google_storage_bucket" "media_bucket" {
  name     = "${var.project_id}-media-public-bucket"
  location = "US"
  force_destroy = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_storage_bucket_iam_member" "public_rule" {
  bucket = google_storage_bucket.media_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "sample_files" {
  for_each = fileset("${path.module}/media", "*")

  name   = each.value
  bucket = google_storage_bucket.media_bucket.name
  source = "${path.module}/media/${each.value}"
  content_type = lookup({
    "mp4" = "video/mp4"
    "jpg" = "image/jpeg"
    "png" = "image/png"
    "html" = "text/html"
  }, split(".", each.value)[1], "application/octet-stream")
}

resource "google_compute_backend_bucket" "media_backend" {
  name        = "media-backend"
  bucket_name = google_storage_bucket.media_bucket.name
  enable_cdn  = true
}

resource "google_compute_url_map" "url_map" {
  name            = "media-url-map"
  default_service = google_compute_backend_bucket.media_backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name   = "media-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name        = "media-http-forwarding-rule"
  target      = google_compute_target_http_proxy.http_proxy.id
  port_range  = "80"
  ip_protocol = "TCP"

  depends_on = [google_compute_target_http_proxy.http_proxy]
}
