variable "location" {
  description = "Azure region"
  type        = string
  default     = "South Africa North"
}

variable "resource_group_name" {
  description = "Azure resource group"
  type        = string
  default     = "RG-PHOENIX-DEV"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "phoenix"
}

variable "admin_username" {
  description = "Linux administrator username"
  type        = string
  default     = "azureuser"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 2

}
variable "ssh_public_key" {
  description = "SSH public key used for worker VM access"
  type        = string
  sensitive   = true
}
