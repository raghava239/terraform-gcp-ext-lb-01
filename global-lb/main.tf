provider "google" {
  project = var.project_name
  region  = "us-central1"
}

resource "google_compute_network" "vpc" {
  name                    = "l7-lb-network-01"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "l7-lb-subnet"
  network       = google_compute_network.vpc.self_link
  region        = "us-central1"
  ip_cidr_range = "10.0.0.0/24"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}


resource "google_compute_router" "router" {
  name    = "nat-router"
  region  = "us-central1"
  network = google_compute_network.vpc.self_link
}

resource "google_compute_router_nat" "cloud_nat" {
  name                               = "cloud-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance_template" "instance_template" {
  name         = "apache-instance-template"
  machine_type = "e2-micro"

  disk {
    boot         = true
    auto_delete  = true
    source_image = "debian-cloud/debian-11"
  }

  network_interface {
    network    = google_compute_network.vpc.self_link
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {} # Enables external IP
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt update -y
    apt install -y apache2
    echo "<h1>Welcome to GCP Load Balancer</h1>" > /var/www/html/index.html
    systemctl start apache2
    systemctl enable apache2
  EOF
}

resource "google_compute_instance_group_manager" "mig" {
  name               = "apache-mig"
  base_instance_name = "apache-instance"
  zone             = "us-central1-a"

  version {
    instance_template = google_compute_instance_template.instance_template.self_link
  }

  target_size = 1
}

resource "google_compute_backend_service" "backend_service" {
  name                  = "apache-backend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"
  health_checks         = [google_compute_health_check.http.self_link]
  
  log_config {
    enable = true
  }

  backend {
    group = google_compute_instance_group_manager.mig.instance_group
  }
}

resource "google_compute_health_check" "http" {
  name                = "http-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5

  http_health_check {
    port = 80
  }
}

resource "google_compute_url_map" "url_map" {
  name            = "url-map"
  default_service = google_compute_backend_service.backend_service.self_link
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-proxy"
  url_map = google_compute_url_map.url_map.self_link
}

resource "google_compute_global_forwarding_rule" "http_rule" {
  name       = "http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.self_link
  port_range = "80"
}


resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = [ "0.0.0.0/0" ]
}