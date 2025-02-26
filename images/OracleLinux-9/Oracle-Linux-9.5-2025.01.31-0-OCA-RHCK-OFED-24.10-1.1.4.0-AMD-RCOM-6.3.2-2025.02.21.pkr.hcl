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

variable "image_base_name" {
  type    = string
  default = "Oracle-Linux-9.5-2025.01.31-0-OCA-RHCK-OFED-24.10-1.1.4.0-AMD-RCOM-6.3.2-2025.02.24-0"
}

variable "image_id" {
  type    = string
  default = "ocid1.image.oc1.us-chicago-1.aaaaaaaagka3js5zwi2mppzh33rvdpv4kjgwijn3dy2vxcy4oqdvzvlat52q"
}

variable "ssh_username" {
  type    = string
  default = "opc"
}

variable "build_options" {
  type    = string
  default = "noselinux,rhck,openmpi,benchmarks,amd,monitoring,enroot,networkdevicenames,use_plugins"
}

variable "build_groups" {
  default = [ "kernel_parameters", "oci_hpc_packages", "mofed_2410_1140", "hpcx_2180", "openmpi_414", "amd_rocm_632", "ol9_rhck" , "use_plugins", "oca_beta_149"]
}

/* authentication variables, edit and use defaults.pkr.hcl instead */ 

variable "region" {
  type    = string
  default = "us-chicago-1"
}

variable "ad" {
  type    = string
  default = "VXpT:US-CHICAGO-1-AD-3"
}

variable "compartment_ocid" {
  type    = string
  default = "ocid1.compartment.oc1..aaaaaaaafwdkyhfy2qltzk2fa63gtz4jtjiiverfwkxaymdxvbwpseiurh7q"
}

variable "shape" {
  type    = string
  default = "VM.Standard.E5.Flex"
}

variable "subnet_ocid" {
  type    = string
  default = "ocid1.subnet.oc1.us-chicago-1.aaaaaaaaz4csumrrvqvcjumngboc6odyajkwa4mdiiez6337kw7p5vm4zhpq"
}

variable "use_instance_principals" { 
  type = bool 
  default = "false"
}

variable "access_cfg_file_account" { 
  type = string 
  default = "DEFAULT" 
}

variable "access_cfg_file" { 
  type = string
  default = "~/.oci/config"
}

/* changes should not be required below */

source "oracle-oci" "oracle" {
  availability_domain = var.ad
  base_image_ocid     = var.image_id
  compartment_ocid    = var.compartment_ocid
  image_name          = local.build_name
  shape               = var.shape
  shape_config        { ocpus = "16" }
  ssh_username        = var.ssh_username
  subnet_ocid         = var.subnet_ocid
  access_cfg_file     = var.use_instance_principals ? null : var.access_cfg_file
  access_cfg_file_account = var.use_instance_principals ? null : var.access_cfg_file_account
  region              = var.use_instance_principals ? null : var.region
  user_data_file      = "${path.root}/../files/user_data.txt"
  disk_size           = 100
  use_instance_principals = var.use_instance_principals
  ssh_timeout         = "90m"
  instance_name       = "HPC-ImageBuilder-${local.build_name}"
}

locals {
  ansible_args        = "options=[${var.build_options}]"
  ansible_groups      = "${var.build_groups}"
  build_name          = "${var.image_base_name}"
}

build {
  name    = "buildname"
  sources = ["source.oracle-oci.oracle"]

  provisioner "shell" {
    inline = ["sudo /usr/libexec/oci-growfs -y"]
  }

  provisioner "ansible" {
    playbook_file   = "${path.root}/../../ansible/hpc.yml"
    extra_arguments = [ "-e", local.ansible_args] // "--scp-extra-args", "'-O'" workaround for OpenSSH > 9
    groups = local.ansible_groups
    user = var.ssh_username
  }

  provisioner "shell" {
    inline = ["rm -rf $HOME/~*", "sudo /usr/libexec/oci-image-cleanup --force"]
  }

  post-processor "manifest" {
    output = "${var.image_base_name}.manifest.json"
    custom_data = {
        image_name    = var.image_base_name
        ssh_username  = var.ssh_username
    }
  }
}
