# Purpose 

ansible_hpc is a collection of ansible roles and playbook to build an HPC image.
- It installs HPC packages to ensure that our instances from the image can run in OCI RDMA network.
- It is supports HPC/GPU shapes, and we support OL7x/Ubuntu.

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

## Playbooks

| Component            | Description                                                                                                                                                                                                                                    |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| hpc.yml      | Entry point for the image build
                                                                                                                                                                                                        |


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