# oci-hpc-images
_Templates for Oracle Cloud Infrastructure HPC images_

<!-- headings -->
<a id="installation"></a>

## Installation

<details>
  <summary>Oracle Linux 8</summary>

```
sudo yum install -y yum-utils tmux
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install packer
sudo dnf install -y oracle-epel-release-el8
sudo dnf config-manager --set-enabled ol8_codeready_builder
sudo dnf install -y python3.8
sudo python3.8 -m pip install --upgrade pip setuptools
python3.8 -m venv packer_env
source packer_env/bin/activate 
python -m pip install --upgrade pip
pip install ansible-core==2.13.13
ansible-galaxy install -r oci-hpc-images-main/requirements.yml
```
</details>

<details>
  <summary>Ubuntu 22.04</summary>

```
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer tmux
sudo apt install python3.10-venv
python3 -m venv packer_env
source packer_env/bin/activate 
python -m pip install --upgrade pip
pip install ansible-core==2.13.13
ansible-galaxy install -r oci-hpc-images-main/requirements.yml
```
</details>

<details>
  <summary>Ubuntu 24.04</summary>

```
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer tmux
sudo apt install python3-venv
python3 -m venv packer_env
source packer_env/bin/activate 
python -m pip install --upgrade pip
pip install ansible-core==2.16.14
ansible-galaxy install -r oci-hpc-images-main/requirements.yml
```
</details>
## Configure Environment


Using defaults.pkr.hcl.example create a new version of the file: `defaults.pkr.hcl` and fill in the variables.
If your build node is Ubuntu 24.04 or later. Make sure to add set the line as 
```
OpenSSH9 = true
```

In the image file, you will need to edit the image OCID for your region. OCIDs can be found here: https://docs.oracle.com/en-us/iaas/images/

In the image directory, choose the OS folder you would like to build for and edit the file with the image name and the specific modules to install. 

Since this takes quite some time, we recommend running this in a tmux session: 
```
tmux new
```

Then run: 
```
packer init images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
packer build -var-file="defaults.pkr.hcl" images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
```

## Contributing

This project welcomes contributions from the community. Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md)

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process
