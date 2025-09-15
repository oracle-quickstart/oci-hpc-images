#!/bin/bash
# lots of notes here: https://openai.slack.com/archives/C1UA8LT0T/p1617386410192500?thread_ts=1617340349.187600&cid=C1UA8LT0T

set -eu -o pipefail
set -x  # echo on, when extensive debugging is needed

KUBERNETES_MAJOR_RELEASE="1.33"
KUBERNETES_PACKAGE_VERSION="${KUBERNETES_MAJOR_RELEASE}.2-1.1"

# Find the version here: https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/
MELLANOX_DRIVER_VERSION="24.10-1.1.4.0"
MELLANOX_DKMS_DRIVER_VERSION="24.10.1.1.4.1"

# nvidia container toolkits are here: https://github.com/NVIDIA/nvidia-container-toolkit/releases
NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"

# 570.158.01-open
NVIDIA_DRIVER_MAJOR_VERSION="580"
NVIDIA_DRIVER_SEMANTIC_VERSION="580.65.06-0"
NVIDIA_FABRICMANAGER_VERSION="580.65.06-1"
DCGM_VERSION="1:4.2.2"

KUBELOGIN_SHA="c22fb2bf48f894b2fa83226e25c4fba1a7945c6b"    # Current as of 05-14-2025
CONTAINERD_VERSION="1.7.27-0ubuntu1~24.04.1"

AZ_CLI_VER="2.64.0"

disable_cloud_init_networking() {
    ### Disable network for cloud init, otherwise this machine does not seem to be able to come back from reboot
    echo "network: {config: disabled}" | tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    bash -c "cat > /etc/netplan/50-cloud-init.yaml" <<'EOF'
network:
    ethernets:
        eth0:
            dhcp4: true
    version: 2
    renderer: networkd
EOF
}


configure_rdma_presistent_naming() {
    # some sort of rdma thing thats cribbed from https://github.com/JonShelley/azure/blob/master/image/ubuntu_18.04_ai/setup_00.sh
    # should run pretty early on
    bash -c "cat > /etc/udev/rules.d/60-rdma-persistent-naming.rules" <<'EOF'
# SPDX-License-Identifier: (GPL-2.0 OR Linux-OpenIB)
# Copyright (c) 2019, Mellanox Technologies. All rights reserved. See COPYING file
#
# Rename modes:
# NAME_FALLBACK - Try to name devices in the following order:
#                 by-pci -> by-guid -> kernel
# NAME_KERNEL - leave name as kernel provided
# NAME_PCI - based on PCI/slot/function location
# NAME_GUID - based on system image GUID
#
# The stable names are combination of device type technology and rename mode.
# Infiniband - ib*
# RoCE - roce*
# iWARP - iw*
# OPA - opa*
# Default (unknown protocol) - rdma*
#
# * NAME_PCI
#   pci = 0000:00:0c.4
#   Device type = IB
#   mlx5_0 -> ibp0s12f4
# * NAME_GUID
#   GUID = 5254:00c0:fe12:3455
#   Device type = RoCE
#   mlx5_0 -> rocex525400c0fe123455
#
ACTION=="add", SUBSYSTEM=="infiniband", PROGRAM="rdma_rename %k NAME_PCI"
EOF
}


install_infiniband_drivers () {
    mkdir -p /mnt/setup
    cd /mnt/setup

    mellanox_file="MLNX_OFED_LINUX-${MELLANOX_DRIVER_VERSION}-ubuntu24.04-aarch64"
    mellanox_file_url="https://content.mellanox.com/ofed/MLNX_OFED-${MELLANOX_DRIVER_VERSION}/${mellanox_file}.tgz"
    echo "Downloading Mellanox OFED: ${mellanox_file_url}"
    curl --http1.1 -fLSs -o "${mellanox_file}.tgz" "${mellanox_file_url}"
    tar xzf "${mellanox_file}.tgz"
    pushd "${mellanox_file}/DEBS"

    apt install -y \
      ./ibacm_2410mlnx54-1.2410068_arm64.deb \
      ./ibverbs-providers_2410mlnx54-1.2410068_arm64.deb \
      ./ibverbs-utils_2410mlnx54-1.2410068_arm64.deb \
      ./infiniband-diags_2410mlnx54-1.2410068_arm64.deb \
      ./kernel-mft-dkms_4.30.1.8-1_all.deb \
      ./libibmad5_2410mlnx54-1.2410068_arm64.deb \
      ./libibmad-dev_2410mlnx54-1.2410068_arm64.deb \
      ./libibnetdisc5_2410mlnx54-1.2410068_arm64.deb \
      ./libibumad3_2410mlnx54-1.2410068_arm64.deb \
      ./libibumad-dev_2410mlnx54-1.2410068_arm64.deb \
      ./libibverbs1_2410mlnx54-1.2410068_arm64.deb \
      ./libibverbs-dev_2410mlnx54-1.2410068_arm64.deb \
      ./librdmacm1_2410mlnx54-1.2410068_arm64.deb \
      ./librdmacm-dev_2410mlnx54-1.2410068_arm64.deb \
      ./mft_4.30.1-8_arm64.deb \
      ./mlnx-ethtool_6.9-1.2410068_arm64.deb \
      ./mlnx-iproute2_6.10.0-1.2410114_arm64.deb \
      ./mlnx-ofed-kernel-utils_24.10.OFED.24.10.1.1.4.1-1_arm64.deb \
      ./mlnx-ofed-kernel-dkms_24.10.OFED.24.10.1.1.4.1-1_all.deb \
      ./mlnx-tools_24.10-0.2410068_arm64.deb \
      ./ofed-scripts_24.10.OFED.24.10.1.1.4-1_arm64.deb \
      ./rdmacm-utils_2410mlnx54-1.2410068_arm64.deb \
      ./rdma-core_2410mlnx54-1.2410068_arm64.deb


    # 4. Force a DKMS build/install for your running kernel
    dkms build   -m mlnx-ofed-kernel -v 24.10.OFED.${MELLANOX_DKMS_DRIVER_VERSION} -k $(uname -r)
    dkms install -m mlnx-ofed-kernel -v 24.10.OFED.${MELLANOX_DKMS_DRIVER_VERSION} -k $(uname -r)

    popd

    /etc/init.d/openibd restart

}

configure_waagent () {
    # Enable RDMA/Infiniband in waagent, should run after install_infiniband_drivers
    sed -i -e 's/# OS.EnableRDMA=y/OS.EnableRDMA=y/g' /etc/waagent.conf
    echo "Extensions.GoalStatePeriod=300" | tee -a /etc/waagent.conf
    echo "OS.EnableFirewallPeriod=300" | tee -a /etc/waagent.conf
    echo "OS.RemovePersistentNetRulesPeriod=300" | tee -a /etc/waagent.conf
    echo "OS.RootDeviceScsiTimeoutPeriod=300" | tee -a /etc/waagent.conf
    echo "OS.MonitorDhcpClientRestartPeriod=60" | tee -a /etc/waagent.conf
    echo "Provisioning.MonitorHostNamePeriod=60" | tee -a /etc/waagent.conf
    systemctl restart walinuxagent
}


install_nvidia_drivers () {
    # See https://github.com/NVIDIA/nvidia-docker/issues/1631#issuecomment-1112828208
    # and https://jdhao.github.io/2022/05/05/nvidia-apt-repo-public-key-error-fix/
    rm -f /etc/apt/sources.list.d/cuda.list
    rm -f /etc/apt/sources.list.d/nvidia-ml.list
    apt-key del 7fa2af80 || true
    # See also
    # https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/index.html
    # and the api/containers/base2/Dockerfile conda-cuda-builder target, which
    # must match the version here. We have to pin to the nvidia repo because if
    # you install nvidia-driver-${NVIDIA_DRIVER_MAJOR_VERSION} from the Ubuntu repo it will automatically
    # upgrade you to nvidia-driver-460 which is not what you want.
    # curl -sSfL -o /etc/apt/preferences.d/cuda-repository-pin-600 \
    #     https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
    # apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub
    # add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /"
    # apt-get update

    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    apt-get update

    apt-get install -y  libnvidia-cfg1-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-common-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-compute-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-decode-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-encode-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-extra-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-fbc1-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-firmware-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-gl-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        libnvidia-nscq=${NVIDIA_FABRICMANAGER_VERSION} \
                        nvidia-compute-utils-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-dkms-${NVIDIA_DRIVER_MAJOR_VERSION}-open=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-driver-${NVIDIA_DRIVER_MAJOR_VERSION}-open=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-kernel-common-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-kernel-source-${NVIDIA_DRIVER_MAJOR_VERSION}-open=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-modprobe=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-settings=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-utils-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        nvidia-imex=${NVIDIA_FABRICMANAGER_VERSION} \
                        libnvidia-gpucomp-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1 \
                        xserver-xorg-video-nvidia-${NVIDIA_DRIVER_MAJOR_VERSION}=${NVIDIA_DRIVER_SEMANTIC_VERSION}ubuntu1

    apt-mark hold libnvidia-cfg1-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-common-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-compute-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-decode-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-encode-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-extra-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-fbc1-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    nvidia-firmware-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-gl-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    nvidia-compute-utils-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    nvidia-dkms-${NVIDIA_DRIVER_MAJOR_VERSION}-open \
                    nvidia-driver-${NVIDIA_DRIVER_MAJOR_VERSION}-open \
                    nvidia-kernel-common-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    nvidia-kernel-source-${NVIDIA_DRIVER_MAJOR_VERSION}-open \
                    nvidia-modprobe \
                    nvidia-settings \
                    nvidia-imex \
                    libnvidia-gpucomp-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    libnvidia-nscq \
                    nvidia-utils-${NVIDIA_DRIVER_MAJOR_VERSION} \
                    xserver-xorg-video-nvidia-${NVIDIA_DRIVER_MAJOR_VERSION}

    # TODO: this fails on non-gpu machines like we use for builds.  should i rm?
    nvidia-smi -mig 0  || true # this messes with nvlink if already enabled on the gpu
    install_nvidia_dcgm_manager

    apt-get install -y nvidia-fabricmanager=${NVIDIA_FABRICMANAGER_VERSION}
    apt-mark hold nvidia-fabricmanager
    systemctl enable nvidia-fabricmanager

    install_cuda_gds_nvidiafs

    # Enable IMEX channel 0 autocreation.
    echo "options nvidia NVreg_CreateImexChannel0=1" | sudo tee /etc/modprobe.d/nvidia-imex.conf
    # Enable CDMM https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-82-07/index.html
    echo "options nvidia NVreg_CoherentGPUMemoryMode=driver" | sudo tee /etc/modprobe.d/nvidia-openrm.conf

    # start services and trigger nvidia driver loading of all kinds
    systemctl start dcgm
    systemctl start nvidia-fabricmanager || true  # will fail to start on v100s
    nvidia-smi || true
}

# Note that this is currently not enough to enable GDS, we are waiting for Azure's patches on kernel
# to enable GDS.
install_cuda_gds_nvidiafs() {
    # Install CUDA keyring and toolkit
    wget -O /tmp/cuda-keyring_1.1-1_all.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/arm64/cuda-keyring_1.1-1_all.deb
    dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
    apt-get update

    apt-get install -y nvidia-gds-12-8 gds-tools-12-8 || true
    apt-get install -y hwloc || true
}

install_nvidia_dcgm_manager() {
    apt-get install -y datacenter-gpu-manager-4-core=${DCGM_VERSION} \
                       datacenter-gpu-manager-4-cuda11=${DCGM_VERSION} \
                       datacenter-gpu-manager-4-cuda12=${DCGM_VERSION} \
                       datacenter-gpu-manager-4-cuda-all=${DCGM_VERSION}
    apt-mark hold datacenter-gpu-manager
    # Create service for dcgm to launch on bootup
    bash -c "cat > /etc/systemd/system/dcgm.service" <<'EOF'
[Unit]
Description=DCGM service
[Service]
User=root
PrivateTmp=false
ExecStart=/usr/bin/nv-hostengine -n
Restart=on-abort
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable dcgm
}

# https://download.nvidia.com/XFree86/Linux-x86_64/470.42.01/README/nvidia-peermem.html
setup_peer_memory() {
    # This failed in build.  TODO: check if exists in image.
    modprobe nvidia-peermem || true
    echo nvidia-peermem >> /etc/modules
}

# Nvidia MIG is disabled by default, so this is not used for now. Leaving it here for future reference.
# CAN BE REMOVED?
disable_nvidia_mig() {
    # not clear if we need this type of gpu sharing yet
    # https://www.nvidia.com/en-us/technologies/multi-instance-gpu/
    # do not run this today, seems like the machine has a lot of trouble
    # rebooting after this step

    systemctl stop dcgm
    systemctl stop nvidia-persistenced

    # to figure out why gpu reset is failing, you can use this to find pids:
    # ls /proc/*/fd/* -l | grep /dev/nvidi
    nvidia-smi -mig 0 || true
    nvidia-smi --gpu-reset || true

    systemctl start dcgm
    systemctl start nvidia-persistenced

    systemctl restart nvidia-fabricmanager
}

# Nvidia MIG is disabled by default, and we don't need the feature for now. Leaving it here for future reference.
# CAN BE REMOVED?
enable_nvidia_mig() {
    # not clear if we need this type of gpu sharing yet
    # https://www.nvidia.com/en-us/technologies/multi-instance-gpu/
    # do not run this today, seems like the machine has a lot of trouble
    # rebooting after this step

    systemctl stop dcgm
    systemctl stop nvidia-persistenced

    # to figure out why gpu reset is failing, you can use this to find pids:
    # ls /proc/*/fd/* -l | grep /dev/nvidi
    nvidia-smi -mig 1 || true
    nvidia-smi --gpu-reset || true

    systemctl start dcgm
    systemctl start nvidia-persistenced
}


install_kubelogin() {
    add-apt-repository -y ppa:longsleep/golang-backports
    apt-get update
    apt-get install -y golang-go

    rm -rf /mnt/setup/kubelogin
    git clone https://github.com/Azure/kubelogin.git /mnt/setup/kubelogin
    cd /mnt/setup/kubelogin
    git checkout "${KUBELOGIN_SHA}"
    make
    cp bin/linux_arm64/kubelogin /usr/local/bin/kubelogin
}


install_kubelet() {
    echo "Installing kubelet"

    # Source: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MAJOR_RELEASE}/deb/Release.key" | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MAJOR_RELEASE}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    apt-get update && apt-get install -y kubectl=${KUBERNETES_PACKAGE_VERSION} kubelet=${KUBERNETES_PACKAGE_VERSION} cri-tools

    systemctl disable kubelet  # needs to be explicitly re-enabled after boot
    systemctl stop kubelet
}

install_containerd() {
    apt install -y containerd=${CONTAINERD_VERSION}
    apt-mark hold containerd
}

# install_nvidia_containerd_runtime () {
#   # based on https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#docker
#   apt-key adv --fetch-keys https://nvidia.github.io/nvidia-docker/gpgkey
#   # No 2404 version, and it is actually include all deb from 1804
#   curl -sfL -o /etc/apt/sources.list.d/nvidia-docker.list https://nvidia.github.io/nvidia-docker/ubuntu22.04/nvidia-docker.list
#   apt-get update
#   apt-get install -y nvidia-container-runtime="${NVIDIA_CONTAINER_RUNTIME_VERSION}"
#   apt-mark hold nvidia-container-runtime
# }

install_nvidia_container_toolkit() {
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  sudo apt-get update
  sudo apt-get install -y \
      nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
}


configure_nvidia_containerd_runtime() {
    # This setup was taken from native AKS gpu nodes by jumping into them with nsenter
    # and reverse engineering the setup.
    # The goal here is to enable the nvidia container runtime within containerd
    # so gpus are visible when a container asks for them.
    # Some relevant docs for what is happening:
    # https://github.com/containerd/containerd/blob/main/docs/cri/config.md
    # https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#step-1-install-containerd
    echo "Configuring nvidia container runtime"

    systemctl stop containerd
    systemctl disable containerd  # needs to be explicitly re-enabled after boot

    mkdir -p /etc/containerd/
    cat << 'EOT' > /etc/containerd/config.toml
version = 2
oom_score = 0

root = "/containerd-ssd/var/lib/containerd"
state = "/containerd-ssd/run/containerd"
[grpc]
  address = "/containerd-ssd/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "mcr.microsoft.com/oss/kubernetes/pause:3.6"

  [plugins."io.containerd.grpc.v1.cri".containerd]
    default_runtime_name = "nvidia-container-runtime"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime]
      runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime.options]
      BinaryName = "/usr/bin/nvidia-container-runtime"
      # Note: removing SystemdCgroup = true because of this issue:
      # https://github.com/NVIDIA/nvidia-docker/issues/1730
      # SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.untrusted]
      runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.untrusted.options]
      BinaryName = "/usr/bin/nvidia-container-runtime"
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"

  [plugins."io.containerd.grpc.v1.cri".registry.headers]
    X-Meta-Source-Client = ["azure/aks"]
[metrics]
  address = "0.0.0.0:10257"
EOT

    # Tell cri-tools where the socket is
    cat << 'EOT' > /etc/crictl.yaml
runtime-endpoint: unix:///containerd-ssd/run/containerd/containerd.sock
image-endpoint: unix:///containerd-ssd/run/containerd/containerd.sock
EOT

    systemctl daemon-reload
    systemctl restart containerd
}

configure_nvidia_persistenced() {
    # This is a daemon that manages the persistence mode of the GPUs.
    # It was enabled by default on previous Nvidia driver versions.
    # However, for 570, it seems that we need to explicitly enable it.
    # This seems to be a legacy feature, see: https://docs.nvidia.com/deploy/driver-persistence/index.html#persistence-mode
    echo "Configuring nvidia persistenced"

    # Ensure the nvidia-persistenced system group and user exist, ubuntu 2404, it was failing
    # due to the lack of user.
    sudo groupadd --system nvidia-persistenced || true
    sudo useradd --system --no-create-home --gid nvidia-persistenced nvidia-persistenced || true

    systemctl stop nvidia-persistenced

    mkdir -p /etc/systemd/system/nvidia-persistenced.service.d/

    cat << 'EOT' > /etc/systemd/system/nvidia-persistenced.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced --user nvidia-persistenced --verbose
EOT

    systemctl daemon-reload
    systemctl enable nvidia-persistenced || true
    systemctl start nvidia-persistenced || true
}

configure_kernel_for_kubelet() {
    # stolen from a native aks node setup
    bash -c "cat > /etc/sysctl.d/90-kubelet.conf" <<'EOT'
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOT
    sysctl -p /etc/sysctl.d/90-kubelet.conf
}


install_azure_cli() {
    # Install the Azure CLI so we can fetch secrets from Key Vault.
    curl -sfL -o /mnt/setup/install_azure_cli.sh https://aka.ms/InstallAzureCLIDeb
    bash /mnt/setup/install_azure_cli.sh

    # The bash script above installs the apt repository.
    # So we just need to install the specific version we want.
    DISTRO=$(lsb_release -cs)
    apt install --assume-yes --allow-downgrades \
    "azure-cli=${AZ_CLI_VER}-1~${DISTRO}"

    apt-mark hold azure-cli
}

create_resolv_conf_symlink() {
    ln -fs /run/systemd/resolve/resolv.conf /etc/resolv.conf
}

# is this gonna f things up
# This is required before installing the mlnx_ofed driver.
install_explicit_kernel_packages() {
    kernel_version=$(uname -r)
    PKGS=(
        "linux-image-${kernel_version}"
        "linux-buildinfo-${kernel_version}"
        "linux-modules-${kernel_version}"
        "linux-headers-${kernel_version}"
        "linux-modules-extra-${kernel_version}"
    )
    apt install -y "${PKGS[@]}"
    apt-mark hold "${PKGS[@]}"

    # Ensure required build tools are present
    apt install -y autoconf debhelper quilt gcc autotools-dev dh-dkms chrpath automake dh-autoreconf pkg-config bzip2 make
}

uninstall_snapd() {
    sudo apt remove -y --autoremove snapd
}

# Bind all workloads to specific NUMA domains via systemd.
bind_systemd_numa_nodes() {
# NOTE: this requires kubelet to use the systemd cgroup driver.
# TODO: add description of SEV and gh issue.

# Numa nodes of CPU mem.
  local mask="0-1"
  local dir="/etc/systemd/system.conf.d"
  local file="$dir/99-numa.conf"
  echo "Binding workloads to NUMA domains $mask"


 mkdir -p "$dir"
  # Write the systemd manager drop‑in
  cat >"$file" <<EOF
[Manager]
NUMAPolicy=bind
NUMAMask=${mask}
EOF
  chmod 0644 "${file}"
  chown root:root "${file}"
  # Pick up the new config
  systemctl daemon-reload
}

# These are custom kernel boot args for azure gpu nodes.
# They are required on GB200 VMs in order to expose the GPUs to the guest VM.
update_kernel_boot_args() {
    export KERNEL_GRUB_CMDLINE_LINUX='$GRUB_CMDLINE_LINUX console=tty1 console=ttyAMA0 earlycon=pl011,0xeffec000 initcall_blacklist=arm_pmu_acpi_init nvme_core.io_timeout=240 iommu.passthrough=1 irqchip.gicv3_nolpi=y module_blacklist=hv_balloon nvidia.NVreg_NvLinkDisable=0 arm_smmu_v3.disable_msipolling=1 init_on_alloc=0 randomize_kstack_offset=0'
    grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub.d/50-cloudimg-settings.cfg \
            && sudo sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${KERNEL_GRUB_CMDLINE_LINUX}\"/g" /etc/default/grub.d/50-cloudimg-settings.cfg \
            || echo "\"GRUB_CMDLINE_LINUX=${KERNEL_GRUB_CMDLINE_LINUX}\"" | sudo tee -a /etc/default/grub.d/50-cloudimg-settings.cfg
    update-grub
}

boot_sequence() {
    export DEBIAN_FRONTEND=noninteractive

    # Wait for cloud-init to finish. It keeps interfering with apt update because of lock.
    cloud-init status --wait || true

    # Avoid being upgraded to latest kernel.
    # apt-mark hold linux-azure

    apt update
    apt upgrade -y
    apt install build-essential -y

    # from helpful_debug_packages.txt
    apt install -y htop iputils-ping less net-tools netcat-openbsd nload nmon vim-tiny

    # install_explicit_kernel_packages
    # update_kernel_boot_args

    # use SSD for setup files and compilation
    mkdir -p /mnt/setup
    cd /mnt/setup
    # chown api:api /mnt/setup
    # Added after build
    chown ubuntu:ubuntu /mnt/setup

    disable_cloud_init_networking
    # uninstall_snapd
    
    configure_rdma_presistent_naming

    # needs to install the mlnx drivers before nvidia drivers
    # otherwise the nvidia-peermem will fail to be loaded.
    # install_infiniband_drivers

    install_nvidia_drivers

    # configure_waagent

    install_azure_cli
    install_kubelogin

    apt install -y jq

    install_containerd
    install_kubelet

    configure_kernel_for_kubelet
    # install_nvidia_containerd_runtime
    install_nvidia_container_toolkit
    configure_nvidia_containerd_runtime
    configure_nvidia_persistenced

    setup_peer_memory

    create_resolv_conf_symlink

    bind_systemd_numa_nodes

}

boot_sequence
