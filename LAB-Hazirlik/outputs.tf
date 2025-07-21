# Master'ın dış (public) IP adresi
output "master_public_ip" {
  value = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
}

# Worker'ların iç (private) IP adresleri
output "worker_internal_ips" {
  value = [for w in google_compute_instance.worker : w.network_interface[0].network_ip]
}
