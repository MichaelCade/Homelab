# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.6.6"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/vsphere
    # see https://github.com/hashicorp/terraform-provider-vsphere
    vsphere = {
      source = "hashicorp/vsphere"
      version = "2.2.0"
    }
  }
}

variable "vm_hostname_prefix" {
  default = ""
}

variable "vm_cpu" {
  description = "number of CPUs per VM"
  type = number
  default = 2
  validation {
    condition = var.vm_cpu >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_memory" {
  description = "amount of memory [GiB] per VM"
  type = number
  default = 4
  validation {
    condition = var.vm_memory >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_disk_os_size" {
  description = "minimum size of the OS disk [GiB]"
  type = number
  default = 60
  validation {
    condition = var.vm_disk_os_size >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_disk_data_size" {
  description = "size of the DATA disk [GiB]"
  type = number
  default = 1
  validation {
    condition = var.vm_disk_data_size >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vsphere_user" {
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  default = "password"
  sensitive = true
}

variable "vsphere_server" {
  default = "vsphere.local"
}

variable "vsphere_datacenter" {
  default = "Datacenter"
}

variable "vsphere_compute_cluster" {
  default = "Cluster"
}

variable "vsphere_network" {
  default = "VM Network"
}

variable "vsphere_datastore" {
  default = "Datastore"
}

variable "vsphere_folder" {
  default = "vZilla DC"
}

variable "vsphere_windows_template" {
  default = "vagrant-templates/windows-2022-amd64-vsphere"
}

variable "prefix" {
  default = "ONE"
}

provider "vsphere" {
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "compute_cluster" {
  name = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "windows_template" {
  name = var.vsphere_windows_template
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# see https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/resources/folder
resource "vsphere_folder" "folder" {
  path = var.vsphere_folder
  type = "vm"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# see https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/resources/virtual_machine
resource "vsphere_virtual_machine" "example" {
  folder = vsphere_folder.folder.path
  name = "${var.prefix}"
  guest_id = data.vsphere_virtual_machine.windows_template.guest_id
  firmware = data.vsphere_virtual_machine.windows_template.firmware
  num_cpus = var.vm_cpu
  num_cores_per_socket = var.vm_cpu
  memory = var.vm_memory*1024
  nested_hv_enabled = true
  vvtd_enabled = true
  enable_disk_uuid = true # NB the VM must have disk.EnableUUID=1 for, e.g., k8s persistent storage.
  resource_pool_id = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id = data.vsphere_datastore.datastore.id
  scsi_type = data.vsphere_virtual_machine.windows_template.scsi_type
  disk {
    unit_number = 0
    label = "os"
    size = max(data.vsphere_virtual_machine.windows_template.disks.0.size, var.vm_disk_os_size)
    eagerly_scrub = data.vsphere_virtual_machine.windows_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.windows_template.disks.0.thin_provisioned
  }
  disk {
    unit_number = 1
    label = "data"
    size = var.vm_disk_data_size # [GiB]
    eagerly_scrub = data.vsphere_virtual_machine.windows_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.windows_template.disks.0.thin_provisioned
  }
  network_interface {
    network_id = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.windows_template.network_interface_types.0
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.windows_template.id
  }
}  

output "ips" {
  value = vsphere_virtual_machine.example.*.default_ip_address
}