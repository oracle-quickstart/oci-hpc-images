# oci-hpc-images: Templates for Oracle Cloud Infrastructure HPC images

## Provisioning a Builder Instance

While the packer workflow can be run from a local machine we highly advise running the image
building process from a cloud instance. This builder instance can be a small CPU VM instance. It
will only be used to launch packer, which will in turn provision a target instance where the
environment will be built from which the image is to be generated. Further, we recommend aligning
your builder image OS with the HPC image OS you are planning to build. This avoids version and
package mismatches.

## Builder Preparation

Once the builder is prepared, clone the oci-hpc-images repo (or copy an exproted zip) onto the
machine and unpack it (We assume the created directory is called `oci-hpc-images-main`). Then
run following commands:

### Oracle Linux 8

```sh
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

### Ubuntu 22.04

```sh
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer tmux
sudo apt install -y python3.10-venv
python3 -m venv packer_env
source packer_env/bin/activate 
python -m pip install --upgrade pip
pip install ansible-core==2.13.13
ansible-galaxy install -r oci-hpc-images-main/requirements.yml
```

### Ubuntu 24.04

```sh
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer tmux
sudo apt install -y python3-venv
python3 -m venv packer_env
source packer_env/bin/activate 
python -m pip install --upgrade pip
pip install ansible-core==2.16.14
ansible-galaxy install -r oci-hpc-images-main/requirements.yml
```

## Configure the Build Environment


Using defaults.pkr.hcl.example create a new version of the file: `defaults.pkr.hcl` and fill in the variables.
If your build node is Ubuntu 24.04 or later. Make sure to add set the line as 

```
OpenSSH9 = true
```

Give the target instance at least 16 ocpus and 64GB of memory since several packages will be
compiled there and will require ample HW resources. In the case of AMD GPU compatible images, you
may want to take a significatnly arger VM (64 ocpus, 256GB memory).

In the image directory, choose the OS folder you would like to build for and edit the file with the image name 
and the specific modules to install. 

The base image can be derived from the image file version, but only for the most recent versions of
the base image. For any other version you will need to edit the image OCID for your region. OCIDs can
be found here: https://docs.oracle.com/en-us/iaas/images/

Building a new image can take several hours, we recommend therefor running this in a tmux session: 

```sh
tmux new
```

Then run: 

```sh
packer init images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
packer build -var-file="defaults.pkr.hcl" images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
```
## Running the Ansible playbooks against an existing instance

As Packer is destroying the node when an error occurs, you can use below approach to run the ansible playbook against an existing instance.
This can be useful for troubleshooting and playbook development.

### 1. Create an instance

    Launch an instance using the image you want to test.

### 2. Create an inventory file

    Update the node IP address, the `options` vars and the `groups` in the template below. These align with the `build_options` and `build_groups` in the image files.

    ```
    # Update the `options` variables, depending on the roles you want to include.
    10.10.10.10 ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_user=ubuntu options="noselinux,nomitigations,openmpi,networkdevicenames,use_plugins,lustre_client,oke"

    # Modify this list based on the group_vars you want to include.
    [kernel_parameters]
    10.10.10.10

    [mofed_2410_1140]
    10.10.10.10
    
    [hpcx_223]
    10.10.10.10
    
    [openmpi_508]
    10.10.10.10
    
    [oca_152_ubuntu]
    10.10.10.10
    
    [lustre_client_217]
    10.10.10.10
    ```

### 3.  Run the ansible playbook

    Execute the playbook using your inventory file:
    
    ```
    ansible-playbook -i inventory hpc.yml
    ```

### Updating component versions

For updating package versions take a look at the `ansible/group_vers` directory. You can add new
versioned files there and refer to them in the image file. Be aware that for components, such as the
GPU drivers or open-mpi, it is often not sufficient to change a version and rebuild the image.
Various other changes in the build process are often necessary and the built image will have to be
throughly tested to ensure the version change did not introduce regressions.

### Dealing with build issues

To step through the generation process to debug issues you can add a `-debug` flag like this:

```sh
packer build -debug -var-file="defaults.pkr.hcl" images/Ubuntu-22/Canonical-Ubuntu-22.04-2024.10.04-0-OCA-OFED-23.10-2.1.3.1-GPU-550-CUDA-12.4-2025-01-31.01.pkr.hcl
```

Now, packer will prompt you to press enter at each provisioner (step). Once ansible fails, packer
stops and you are given the chance to ssh into the target machine. Use the provided ssh `.pem` file
in the working directory to log in:

```sh
ssh -i oci_oracle.pem ubuntu@[IP Address]
```

## Contributing

This project welcomes contributions from the community. Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md)

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process
