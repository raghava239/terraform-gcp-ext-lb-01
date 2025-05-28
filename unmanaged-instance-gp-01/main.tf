provider "google" {
  project = "raghupothula"
  region  = "us-central1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "custom-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "custom-subnet"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_firewall" "allow_all" {
  name    = "allow-all"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "vm_instance" {
  name         = "web-server"
  machine_type = "e2-medium"
  zone         = "us-central1-a"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {} # Assigns external IP
  }
  
  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt update
    sudo apt install -y apache2
    sudo systemctl enable apache2
    sudo systemctl start apache2
    echo "Web Server" | sudo tee /var/www/html/index.html
  EOT
}

resource "google_compute_instance_group" "unmanaged_group" {
  name        = "unmanaged-instance-group"
  zone        = "us-central1-a"
  instances   = [google_compute_instance.vm_instance.id]
}

resource "google_compute_health_check" "default" {
  name               = "http-health-check"
  timeout_sec        = 5
  check_interval_sec = 10

  http_health_check {
    port = 80
  }
}

resource "google_compute_backend_service" "backend" {
  name          = "backend-service"
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.default.id]

  backend {
    group = google_compute_instance_group.unmanaged_group.id
  }
}

resource "google_compute_url_map" "url_map" {
  name            = "http-url-map"
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name       = "http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}
