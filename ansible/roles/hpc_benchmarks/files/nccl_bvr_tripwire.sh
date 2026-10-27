#!/bin/sh
# Transitional diagnostic at /opt/oci-hpc/nccl-test/build/all_reduce_perf.
# Every rank fails, but only rank zero prints the remediation instructions.
if [ "${OMPI_COMM_WORLD_RANK:-0}" = 0 ]; then
    cat >&2 <<'MESSAGE'
ERROR: NCCL_BVR_FIXUP_REQUIRED — this script uses the obsolete NCCL test path.
This image provides /opt/oci-hpc/nccl-tests/bin/all_reduce_perf with its own MPI.
No NCCL test ran. This is a stack/image compatibility error, not a hardware diagnosis.

Keep automatic healthchecks/remediation paused; old checks can misclassify this failure.

The fixup tool is on this updated compute node, but the benchmark scripts and
retained provisioning sources to repair are on the controller.
1. On the compute node, copy the tool into your shared home directory:
     cp /opt/oci-hpc/nccl-tests/bin/nccl_compat_fix.py "$HOME/nccl_compat_fix.py"
   If home is not shared, transfer that file to your home on the controller.
2. On the CONTROLLER, preview either one benchmark or the whole sample directory:
     python3 "$HOME/nccl_compat_fix.py" /opt/oci-hpc/samples/gpu/nccl_run_allreduce_GB.sbatch
     python3 "$HOME/nccl_compat_fix.py" /opt/oci-hpc/samples/gpu
   Preview the retained healthcheck sources too:
     python3 "$HOME/nccl_compat_fix.py" /config/playbooks/roles/healthchecks/files/active_healthcheck.py /config/playbooks/roles/healthchecks/files/multi_node_active_healthcheck.py
3. Review the diffs, then repeat the chosen command with sudo and --apply, e.g.:
     sudo python3 "$HOME/nccl_compat_fix.py" --apply /opt/oci-hpc/samples/gpu/nccl_run_allreduce_GB.sbatch
   Originals are saved beside each repaired file as .pre-nccl-bvr.
   To preview rollback, use --restore; add --apply to perform it.

Use the actual paths on your controller. Native NCCL samples from stack v3.0.0
through v3.2.1 are repaired by content, including GB/GB200, srun, tuner and QFAB
variants. Container benchmarks do not use the host NCCL binary and stay unchanged.
Updating controller sources does not update already-installed healthchecks:
distribute the repaired files to affected nodes before re-enabling checks.
Submit .sbatch jobs from the controller; run native .sh benchmarks from a compute
node matching the targets. Never mix old/new communication stacks in one job.
MESSAGE
fi
exit 78
