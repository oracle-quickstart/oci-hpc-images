# OpenAI

Building from within an OCI VM 
- clickops create builder VCN
  - public subnet
- Make sure that the OCI VM instance OCID belongs to the packer dynamic group in the 
  - Needed for permissions for instance profile to launch other instances
- follow readme to setup
- cd /home/ubuntu/oci-hpc-images
- source packer_env/bin/activate 
- packer build -var-file="fish.pkr.hcl" images/fish/Canonical-Ubuntu-24.04-aarch64-DOCA-OFED-3.0.0.pkr.hcl 