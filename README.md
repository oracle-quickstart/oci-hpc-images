# Stack to create an HPC cluster. 

Install Ansible & packer
```
sudo yum install -y yum-utils ansible
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install packer
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general

```

Create a new version of the file: `defaults.pkr.hcl` and fill in the variables from the console. 

In the image directory, choose the OS folder you would like to build for and edit the file with the image name and the specific modules to install. 

Run: 
```
packer build -var-file="defaults.pkr.hcl" images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
```
