# Purpose 

ansible_hpc is a collection of ansible roles and playbook to build an HPC image.
- It installs HPC packages to ensure that our instances from the image can run in OCI RDMA network.
- It is supports HPC/GPU shapes, and we support OL7x/Ubuntu.
# Code geography

| Component            | Description                                                                                                                                                                                                                                    |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| hpc.yml              | This is Entry point for packer files                                                                                                                                                                                                           |
| ssh                  | Modifies sshd_config in image                                                                                                                                                                                                                  |
| kernel-parameters    | Sets grub config changes                                                                                                                                                                                                                       |
| kernel-limits        | Sets kernel limits changes - specifications -http://openhpc.community/wp-content/uploads/Install_guide-CentOS7.1-1.0.pdf                                                                                                                       |
| packages             | Installs/Disables Packages from the OS vendor repos                                                                                                                                                                                            |
| kernel-rhck          | Modifies Redhat kernel params                                                                                                                                                                                                                  |
| oci-utils            | Clean utils we wrote                                                                                                                                                                                                                           |
| oracle-cloud-agent   | Configures OCA and OSMS                                                                                                                                                                                                                        |
| nozeroconf           | Configures NOZERCONFIG settings for Redhat - https://www.brennan.id.au/04-Network_Configuration.html                                                                                                                                           |
| mellanox-ofed        | Installs Mellanox OFED                                                                                                                                                                                                                         |
| oci-hpc-packages     | Installs packages from Compute-HPC team                                                                                                                                                                                                        |
| tuned                | Installs serviced tuned - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/monitoring_and_managing_system_status_and_performance/getting-started-with-tuned_monitoring-and-managing-system-status-and-performance |
| disable-selinux      | Disables SELINUX for performances                                                                                                                                                                                                              |
| mellanox-hpcx        | Installs MLX HPCX - https://developer.nvidia.com/networking/hpc-x                                                                                                                                                                              |
| intel-openapi        | Installs Intel Open MPI -https://www.intel.com/content/www/us/en/developer/tools/oneapi/mpi-library.html                                                                                                                                       |
| openmpi-gcc          | Installs Open MPI                                                                                                                                                                                                                              |
| nvidia-driver        | Installs nvidia-driver - https://galaxy.ansible.com/nvidia/nvidia_driver                                                                                                                                                                       |
| nvidia-cuda          | Installs cuda                                                                                                                                                                                                                                  |
| nvidia-cudnn         | Installs cuda libraries for neural networks - https://developer.nvidia.com/cudnn****                                                                                                                                                           |
| nvidia-fabricmanager | installs fabricmanager for nvidia                                                                                                                                                                                                              |
| nvidia-nccl          | Installs NCCL libs                                                                                                                                                                                                                             |
| nvidia-dcgm          | Installs dcgm                                                                                                                                                                                                                                  |
| hpc-benchmarks       | Installs benchmark utils - gpuburn,nccl-test,stream                                                                                                                                                                                            |
| systemd              | Configures systemd                                                                                                                                                                                                                             |


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

## How does the ansible and packer gel together?
It is a marriage from hell - 
The packer file uses build_options and build_groups to pass the ansible variables to the ansible playbook.
- build_options - are the ansible variables to switch on / off packages
- build_groups - are the ansible groups to run aka hpc v/s gpu

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