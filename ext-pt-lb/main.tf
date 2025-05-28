provider "google" {
  project = "raghupothula"
  region  = "us-central1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "demo-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "demo-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_instance" "apache_vms" {
  count        = 2
  name         = "apache-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {} # This gives the VM a public IP
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    systemctl enable apache2
    systemctl start apache2
  EOF

  tags = ["web"]
}

resource "google_compute_instance_group" "web_group" {
  name        = "apache-instance-group"
  zone        = "us-central1-a"
  instances   = google_compute_instance.apache_vms[*].self_link
  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "http_health_check" {
  name               = "http-health-check"
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
    request_path = "/"
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "apache-backend-service"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.http_health_check.id]
  backend {
    group = google_compute_instance_group.web_group.self_link
  }
}

resource "google_compute_forwarding_rule" "default" {
  name                  = "apache-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_pool.target_pool.self_link
  ip_protocol           = "TCP"
  region                = "us-central1"
}

resource "google_compute_target_pool" "target_pool" {
  name = "apache-target-pool"
  region = "us-central1"
  instances = google_compute_instance.apache_vms[*].self_link

  health_checks = [google_compute_http_health_check.http_health_check.name]
}

resource "google_compute_http_health_check" "http_health_check" {
  name               = "apache-http-health-check"
  request_path       = "/"
  port               = 80
}

resource "google_compute_security_policy" "edge_policy" {
  name = "edge-security-policy"
  type = "CLOUD_ARMOR_EDGE"  # required for edge protection

  rule {
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["203.0.113.0/24"] # replace with the IPs to block
      }
    }
    action = "deny(403)"
    description = "Deny traffic from 203.0.113.0/24"
  }

  description = "Cloud Armor Edge policy with basic deny rule"
}

