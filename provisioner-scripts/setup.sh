#!/bin/bash

sudo apt update
sudo apt install jq git iputils-ping numactl vim host software-properties-common -y

install_oci_cli() {
    echo "Installing OCI CLI"
    bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/v3.2.1/scripts/install/install.sh)" -- --accept-all-defaults
}

install_oci_cli