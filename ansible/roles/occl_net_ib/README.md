Install the OCCL Net IB plugin artifact into the baked image.

The role downloads an architecture-specific shared library from Object Storage
that works with both NCCL and RCCL. It installs on x86_64 and aarch64 images.

If the image is not x86_64 or aarch64, the role logs a skip reason and leaves
the plugin uninstalled instead of failing the image build.

The downloaded payload is installed to `/opt/occl-net/lib/liboccl-net-ib.so`,
both `libnccl-net-occl-ib.so` and `librccl-net-occl-ib.so` aliases are created,
`/opt/occl-net/lib` is registered with `ldconfig`, and helper variables are
written to `/etc/profile.d/occl-net-ib.sh`.

The role does not write `/etc/nccl.conf` or `/etc/rccl.conf`. To use the
plugin, set `NCCL_NET_PLUGIN=$OCCL_NET_IB_PLUGIN` or
`NCCL_NET_PLUGIN=$OCCL_NET_IB_PLUGIN_NAME` at runtime.

Enable installation by adding `occl_net_ib` to the image template's
`build_options`. The shared artifact version is set by
`occl_net_ib_version` in this role's `defaults/main.yml`; it is used for both
supported architectures.
