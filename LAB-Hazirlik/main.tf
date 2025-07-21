provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Özel VPC ağı (custom mode)
resource "google_compute_network" "vpc_network" {
  name                    = "spark-k8s-vpc"
  auto_create_subnetworks = false
}

# 128.10.0.0/16 CIDR'li özel subnet
resource "google_compute_subnetwork" "spark_subnet" {
  name          = "spark-k8s-subnet"
  ip_cidr_range = "10.128.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Internal IP'ler için tüm trafik (any-any)
resource "google_compute_firewall" "allow-internal-any-any" {
  name    = "allow-internal-any-any"
  network = google_compute_network.vpc_network.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
  }
}

# External IP'lerden gelen tüm trafik (any-any) → tag bazlı
resource "google_compute_firewall" "allow-external-any-any" {
  name    = "allow-external-any-any"
  network = google_compute_network.vpc_network.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["spark-node"]

  allow {
    protocol = "all"
  }
}

# SSH Key
locals {
  ssh_key = <<EOF
veyselforGCP:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDHcGn2QG4R1s73dLPOG4pW/qzu22He7M+UNA502F46eX8w3PTPcxhgjytb4WCa7bYhz+fhQq8oyZI58ZqSJlEvz9HGqmUqJR/JLIdktvLGwDOc6RRfJsUdUV9NOk3pL3Pw4Q59yGaNA/eUKeUWMltO+wwQOTvRFaVBFX/Kp0W6917pNxlDTT0PqPE7jq/kNJWO3HtzxcBmqM/lSAgMM+t35EaEznsXC+JRg/idtSYp6rhupxINI+kJQuoLociH7XvS0ku0nbxU/nl1Lw5aV+8yIvMeAk8v7HVefhcrH9PKY7JBiTe/SrrarZNMQNvCXNkdGs75Ek1PyN0knfcvLd1Fta6hesdwxga9SIRy/ugYpA1CGA0JZMthpqPG0c7OVaEXo0PdL5nIrd9BDqCMzeCgNuH+vtcFPRfUPQ/OiZnjlShrODGjvzFqWFdE25s51WsOcJ0lvskg9ugZg8EuU3y068AWAl1Q6VKuvXIbMN0C9O+MYrJMULzmF66rm5SN1ewwlqK+rB2llndmabtBER0L7PZBan/f0CLruTZ2osfqQsMA7iWmJAy5yjBsXTWEG/+/IOLdmfWb3gGWj7j3rlWTcCoxO47gr+ndWkP1ym6yX7HlKhO15BqWFXhJkubS6fnpjQCF7P+sSWuLWKZ0WK8u9UWpcSPHmF9KKGLQihDfWw==
EOF
}

# Master Node
resource "google_compute_instance" "master" {
  name         = "spark-master"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "rhel-cloud/rhel-8"
      size  = 50
    }
  }

  network_interface {
    subnetwork    = google_compute_subnetwork.spark_subnet.id
    access_config {}  # external IP
  }

  tags = ["spark-node", "spark-master"]

  metadata = {
    ssh-keys = local.ssh_key
  }
}

# Worker Node'lar
resource "google_compute_instance" "worker" {
  count        = 2
  name         = "spark-worker-${count.index}"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "rhel-cloud/rhel-8"
      size  = 50
    }
  }

  network_interface {
    subnetwork    = google_compute_subnetwork.spark_subnet.id
    access_config {}  # external IP
  }

  tags = ["spark-node", "spark-worker"]

  metadata = {
    ssh-keys = local.ssh_key
  }
}