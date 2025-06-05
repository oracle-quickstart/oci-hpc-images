/* variables */

packer {
    required_plugins {
      oracle = {
        source = "github.com/hashicorp/oracle"
        version = ">= 1.0.3"
      }
    ansible = {
      version = "~> 1"
      source = "github.com/hashicorp/ansible"
    }
    }
}
variable "base_image_name" {
  type    = string
  default = "Oracle-Linux-9.5-2025.05.19-0"
}

variable "operating_system" {
  type    = string
  default = "Oracle Linux"
}

variable "operating_system_version" {
  type    = string
  default = "9"
}

variable "ssh_username" {
  type    = string
  default = "opc"
}

variable "features" {
  type    = string
  default = "RHCK-OFED-24.10-1.1.4.0-AMD-ROCM-632"
}

variable "release" {
  type    = number
  default = 0
}

variable "build_options" {
  type    = string
  default = "noselinux,rhck,openmpi,benchmarks,amd,enroot,networkdevicenames,use_plugins"
}

variable "build_groups" {
  default = [ "kernel_parameters", "oci_hpc_packages", "mofed_2410_1140", "hpcx_2212", "openmpi_414", "amd_rocm_632", "ol9_rhck", "oca_152_OL"]
}

/* authentication variables, edit and use defaults.pkr.hcl instead */ 

variable "region" { type = string }
variable "ad" { type = string }
variable "compartment_ocid" { type = string }
variable "shape" { type = string }
variable "subnet_ocid" { type = string }
variable "use_instance_principals" { type = bool }
variable "access_cfg_file_account" { 
  type = string 
  default = "DEFAULT" 
}
variable "access_cfg_file" { 
  type = string
  default = "~/.oci/config"
}
variable OpenSSH9 {
  type = bool
  default = false
}
variable "shape_config" {
  type = object({
    ocpus         = number
    memory_in_gbs = number
  })
  default = {
    ocpus         = 8
    memory_in_gbs = 64
  }
}

variable "skip_create_image" {
  type    = bool
  default = false
}

/* changes should not be required below */

source "oracle-oci" "oracle" {
  availability_domain = var.ad
  base_image_filter { 
    display_name = var.base_image_name
  }
  compartment_ocid    = var.compartment_ocid
  image_name          = local.image_base_name
  shape               = var.shape
  shape_config {
    ocpus         = var.shape_config.ocpus
    memory_in_gbs = var.shape_config.memory_in_gbs
  }
  ssh_username        = var.ssh_username
  subnet_ocid         = var.subnet_ocid
  access_cfg_file     = var.use_instance_principals ? null : var.access_cfg_file
  access_cfg_file_account = var.use_instance_principals ? null : var.access_cfg_file_account
  region              = var.use_instance_principals ? null : var.region
  user_data_file      = "${path.root}/../files/user_data.txt"
  disk_size           = 100
  use_instance_principals = var.use_instance_principals
  ssh_timeout         = "90m"
  instance_name       = "HPC-ImageBuilder-${local.image_base_name}"
  skip_create_image   = var.skip_create_image
}

locals {
  ansible_args    = "options=[${var.build_options}]"
  ansible_groups  = "${var.build_groups}"
  timestamp       = "${formatdate("YYYY.MM.DD", timestamp())}"
  image_base_name = "${var.base_image_name}-${var.features}-${local.timestamp}-${var.release}"
}

build {
  name    = "buildname"
  sources = ["source.oracle-oci.oracle"]

  provisioner "ansible" {
    playbook_file   = "${path.root}/../../ansible/hpc.yml"
    extra_arguments = var.OpenSSH9 ? [ "-e", local.ansible_args, "--scp-extra-args", "'-O'"] : [ "-e", local.ansible_args]
    groups = local.ansible_groups
    user = var.ssh_username
  }

  provisioner "shell" {
    inline = ["rm -rf $HOME/~*", "sudo /usr/libexec/oci-image-cleanup --force"]
  }

  post-processor "manifest" {
    output = "${local.image_base_name}.manifest.json"
    custom_data = {
        image_name = local.image_base_name
        ssh_username = var.ssh_username
        display_name = var.base_image_name
        operating_system = var.operating_system
        operating_system_version = var.operating_system_version
    }
  }
}
