# Purpose 

ansible_hpc is a collection of ansible roles and playbook to build an HPC image.
- It installs HPC packages to ensure that our instances from the image can run in OCI RDMA network.
- It is supports HPC/GPU shapes, and we support OL7x/Ubuntu.

## Playbooks

| Component            | Description                                                                                                                                                                                                                                    |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| hpc.yml      | Entry point for the image build


# Code geography

## Roles



| Component            | Description                                                                                                                                                                                                                                    |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| amd_disclaimer       | adds AMD disclaimer in the cloud user home directory 
| amd_mpivars					 | creates AMD specific mpivars.sh in local OpenMPI installation 
| amd_perftest				 | AMD specific perftest installation
| amd_rccl_tests       | Download and build https://github.com/ROCm/rccl-tests
| amd_rocm						 | Install ROCm 
| amd_rvs							 | Install rocm-validation-suite
| cleanup 						 | on OL8+ perform DNF cache cleanup
| disable_selinux			 | Disable SELINUX on Enterprise Linux 
| dracut							 | Update dracut and reboot to apply udev rules
| gpu_tuning					 | GPU deployment specific sysctl settings
| hpc_benchmarks		   | Add various HPC benchmarks to the image
| kernel							 | Perform kernel installation tasks (RHCK on OL, Specific version on Ubuntu)
| limits      				 | Update default ulimit settings
| mellanox_hpcx				 | Install HPCX from Nvidia
| mellanox_ofed 	     | Install MOFED
| nccl_tuner					 | Download and install NCCL tuning plugin
| nozeroconf				   | Disable bonjour 
| nvidia_cuda					 | Install CUDA libraries
| nvidia_cudnn				 | Install cuDNN libraries
| nvidia_dcgm					 | Install DCGM
| nvidia_fabricmanager | (Unused) Install nvidia-fabricmanager
| nvidia_nccl					 | Install specific NCCL version
| nvidia-doca					 | Install DOCA-ofed instead of MOFED
| oci_hpc_packages		 | Add OCI specific hpc packages and utils
| oci_utils						 | Install image cleanup utilities 
| openmpi_gcc					 | Build and install OpenMPI 
| openscap_oval				 | Install Openscap and generate report
| oracle_cloud_agent_enable | re-enable oracle-cloud-agent 
| oracle_cloud_agent_update_disable | Update oracle-cloud-agent and pin version in the image
| packages             | Install necessary packages 
| rdma_configuration   | Add rdma_network.json configuration file for cloud agent
| resize_rootfs        | Resize root partition to match boot volume size 
| ssh                  | Modifies sshd_config in image       
| systemd							 | Set multi-user target on Ubuntu          
| tuned							   | Install and configure tuned 



# Group variables

group_vars/ folder specified variables used by the build job 

| Variable                              | Description                                                                 |
|---------------------------------------|-----------------------------------------------------------------------------|
| amd_rocm_repo                         | URL to download ROCM package                                                |
| amd_rocm_package_prefix               | ROCM download package prefix                                                |
| amd_rocm_package_version              | ROCM download package long version                                          |
| amd_rocm_version                      | ROCM version                                                                |
| benchmark_base_path                   | Base path for benchmark tools                                               |
| cuda_toolkit_version                  | Version of the CUDA toolkit                                                 |
| cuda_version                          | Version of CUDA                                                             |
| gcc_version                           | Version of GCC                                                              |
| gpuburn_repo                          | Repository for GPU burn tests                                               |
| gpu_sysctl                            | Sysctl settings for GPU                                                     |
| grub_cmdline                          | GRUB command line settings                                                  |
| grub_cmdline_disable_mitigations      | GRUB command line settings to disable mitigations                           |
| grub_cmdline_enroot                   | GRUB command line settings for Enroot                                       |
| grub_cmdline_network_device_names     | GRUB command line settings for network device names                         |
| hpc_artifacts_download                | URL to download HPC artifacts                                               |
| install_prefix                        | Prefix path for installation                                                |
| kernel_limits_amd                     | Kernel limits for AMD                                                       |
| kernel_limits_default                 | Default kernel limits                                                       |
| mellanox_hpcx_download_url            | URL to download Mellanox HPC-X                                              |
| mellanox_hpcx_version                 | Version of Mellanox HPC-X                                                   |
| mellanox_mft_download                 | URL to download Mellanox MFT                                                |
| mellanox_ofed_public_repo             | Public repository for Mellanox OFED                                         |
| mellanox_ofed_version                 | Version of Mellanox OFED                                                    |
| mft_version                           | Version of Mellanox Firmware Tools (MFT)                                     |
| mlx_ofed_download_link                | Download link for Mellanox OFED                                             |
| nccl_package_version                  | Version of NCCL package                                                     |
| nccltest_repo                         | Repository for NCCL tests                                                   |
| nccltests_version                     | Version of NCCL tests                                                       |
| nvidia_driver_branch                  | Branch of NVIDIA driver                                                     |
| nvidia_driver_package_version         | Version of NVIDIA driver package                                            |
| nvidia_driver_skip_reboot             | Flag to skip reboot after NVIDIA driver installation                        |
| nvidia_driver_version                 | Version of NVIDIA driver                                                    |
| nvidia_public_repo                    | Public repository for NVIDIA                                                |
| oca_download_url                      | URL to download Oracle Cloud Agent                                          |
| oci_cloud_agent_channel_ubuntu        | Channel for Oracle Cloud Agent on Ubuntu                                    |
| oci_cloud_agent_version               | Version of Oracle Cloud Agent                                               |
| oci_cn_auth_version                   | Version of OCI CN Auth                                                      |
| oci_hpc_dapl_configure_version        | Version of OCI HPC DAPL configuration                                        |
| oci_hpc_mlx_configure_version         | Version of OCI HPC Mellanox configuration                                    |
| oci_hpc_network_device_names_version  | Version of OCI HPC network device names configuration                        |
| oci_hpc_nvidia_gpu_configure_version  | Version of OCI HPC NVIDIA GPU configuration                                  |
| oci_hpc_rdma_configure_version        | Version of OCI HPC RDMA configuration                                        |
| openmpi_release                       | Release version of Open MPI                                                 |
| openmpi_version                       | Version of Open MPI                                                         |
| override_mellanox_os_version          | Override version for Mellanox OS                                            |
| perftest_repo                         | Repository for performance tests                                            |
| rhck_kernel_level                     | Kernel level for Red Hat Compatible Kernel (RHCK)                           |
| rhel7_mellanox_hpcx_package           | Mellanox HPC-X package for RHEL 7                                           |
| rhel8_mellanox_hpcx_package           | Mellanox HPC-X package for RHEL 8                                           |
| rhel9_mellanox_hpcx_package           | Mellanox HPC-X package for RHEL 9                                           |
| spack_base_path                       | Base path for Spack                                                         |
| spack_repo                            | Repository for Spack                                                        |
| stable_nvidia_dcgm_version            | Stable version of NVIDIA DCGM                                               |
| ubuntu20_mellanox_hpcx_package        | Mellanox HPC-X package for Ubuntu 20                                        |
| ubuntu_22_kernel_version              | Kernel version for Ubuntu 22                                                |
| ubuntu22_mellanox_hpcx_package        | Mellanox HPC-X package for Ubuntu 22                                        |
| use_hpc_artifact                      | Flag to use HPC object storage PAR to download packages                     |


# Development
1. Setup your environment
```
# Step 1: Launch ubuntu and Oracle VM
sudo yum install -y ansible # OL
sudo apt install -y ansible # Ubutun
 
# Step 2: configure ansible for local development
## Ensure you have id_rsa / id_rsa.pub / authoerized_keys
 
# Step 3: Modify /etc/ansible/hosts - add the hosts and ssh user
cat /etc/ansible/hosts
130.61.22.206 ansible_connection=ssh ansible ssh_user=ubuntu
 
# Step 4: Modify /etc/ansible/ansible.cfg to stop host checking
cat /etc/ansible/ansible.cfg
[defaults]
# uncomment this to disable SSH key host checking
host_key_checking = False

# Step 5: Run basic test to ensure you are able to run ansible
ansible localhost -m ping
ansible localhost -a "uptime"

## Step 6: Run a dummy playbook
> cat test.yml 
---
- hosts: all
  tasks:
    - name: Print message
      debug:
        msg: Hello Ansible World

    - name: Print hostname
      ansible.builtin.command: "hostname"

> ansible-playbook test.yml 
## At this point, we know ansible and a test playbook is ok we can move to the next step
```
2. Load minimal role to test
```
ansible-playbook dev.yml
```
3. Act and iterate
```
# Check syntax
ansible-playbook hpc.yml --syntax-check

# Dry and check diff 
ansible-playbook hpc.yml --check --diff
```
# FAQ
## How does ansible support both RHEL and Ubuntu?
We use when in roles where we need to have different code for different OS.
```
  when:
   - (ansible_os_family == 'RedHat' and (ansible_distribution_major_version == '7' or ansible_distribution_major_version == '8')) or (ansible_distribution == 'Ubuntu' and ansible_distribution_major_version == '20')
```

## How does the ansible and packer work together?
The packer file uses build_options and build_groups to pass the ansible variables to the ansible playbook.
- build_options - are the ansible variables to switch on / off features
- build_groups - are the ansible groups to run with parameters set in group_vars/

```
# from a packer file
variable "build_options" {
  type    = string
  default = "noselinux,nomitigations,rhck,upgrade,openmpi,nvidia,enroot,monitoring,benchmarks"
}

variable "build_groups" {
  default = [ "kernel_parameters", "oci_hpc_packages", "mofed_54_3681", "hpcx_2131", "openmpi_414", "nvidia_515", "nvidia_cuda_11_7", "ol7_rhck" ]
}
....
build {
  name    = "buildname"
  sources = ["source.oracle-oci.oracle"]

  provisioner "ansible" {
    playbook_file   = "/home/opc/ansible_hpc/hpc.yml"
    extra_arguments = [ "-e", local.ansible_args ]
    groups = local.ansible_groups
  }

```