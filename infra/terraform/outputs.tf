output "control_plane_public_ip" {
  description = "Control-plane public IP"
  value       = "102.37.138.23"
}

output "control_plane_private_ip" {
  description = "Control-plane private IP"
  value       = "10.0.1.4"
}

output "worker_public_ips" {
  description = "Worker public IPs"
  value       = azurerm_public_ip.worker[*].ip_address
}

output "worker_private_ips" {
  description = "Worker private IPs"
  value       = azurerm_network_interface.worker[*].private_ip_address
}
