#!/usr/bin/env python3
"""Repair released v3.0-v3.2.1 NCCL scripts for compute-node BVR.

Pass script paths or a samples/gpu directory. Native NCCL shell scripts are
recognized by their contents, not their filenames. Container/RCCL scripts and
other files without legacy host NCCL paths remain unchanged by this repair.
Default: show diffs only. --apply saves adjacent
.pre-nccl-bvr backups; --restore previews rollback (--apply performs it).
Copy this tool from an updated compute node to your home directory, then run
it on the controller against the samples and retained healthcheck sources.
Distribute repaired healthchecks to existing nodes separately. Submit repaired
sbatch files from the controller; run native .sh benchmarks on a compute node
with the same communication stack as every target. Mixed-image jobs are unsafe.
This repairs executable/MPI selection, not hardware tuning or container stacks.
"""

import argparse
import ast
import difflib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


LEGACY_DIR = "/opt/oci-hpc/nccl-test/build"
VENDOR_MPI = "/usr/mpi/gcc/openmpi-*/bin/mpivars.sh"
MARKER = "# NCCL BVR compatibility: select paths on the executing compute node."
BACKUP_SUFFIX = ".pre-nccl-bvr"
HEALTHCHECKS = {
    "active_healthcheck.py": "run_local_nccl_test",
    "multi_node_active_healthcheck.py": "run_multi_node_nccl_test",
}

# Invalid leftover fragment shipped in nccl_run_alltoall.sh through v3.1.1.
ALLTOALL_TAIL = """  --np $np --hostfile $hostfile  -N 8 /opt/oci-hpc/nccl-test/build/alltoall_perf  -f 2 -g 1 -c 0 -n $iter  >> $logfile

  tail -n 15 $logfile


done"""

# Kept inside each patched script so existing Ansible file-copy behavior and
# standalone benchmark copies need no additional runtime file.
PYTHON_PATHS = '''def _nccl_bvr_paths():
    import re

    nccl_dir = "/opt/oci-hpc/nccl-tests/bin"
    binary = nccl_dir + "/all_reduce_perf"
    if not os.path.isfile(binary):
        return "/opt/oci-hpc/nccl-test/build", "/usr/mpi/gcc/openmpi-*/bin/mpivars.sh"

    # Ignore a caller's MPI environment; use the image binary's library lookup.
    # This also distinguishes the image MPI from additional user installations.
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    linkage = subprocess.check_output(["ldd", binary], env=env, text=True)
    match = re.search(r"libmpi\\.so\\.\\d+ => (/opt/openmpi-[^/\\s]+)/lib(?:64)?/", linkage)
    if not match:
        raise ValueError("NCCL binary does not resolve libmpi under /opt/openmpi-*")
    mpi_dir = match.group(1)
    mpivars = mpi_dir + "/bin/mpivars.sh"
    if not os.path.isfile(mpivars) or not os.access(mpi_dir + "/bin/mpirun", os.X_OK):
        raise ValueError("Incomplete NCCL MPI installation: " + mpi_dir)
    return nccl_dir, mpivars


'''

PYTHON_SELECT = '''    try:
        nccl_dir, nccl_mpivars = _nccl_bvr_paths()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        return False, f"NCCL Test Failed: {error}"
'''

SHELL_PATHS = '''nccl_dir=/opt/oci-hpc/nccl-test/build
nccl_mpivars=""
if [[ -f /opt/oci-hpc/nccl-tests/bin/all_reduce_perf ]]; then
    nccl_dir=/opt/oci-hpc/nccl-tests/bin
    # Resolve the image MPI without an inherited MPI library search path.
    nccl_mpi_lib=$(env -u LD_LIBRARY_PATH -u LD_PRELOAD ldd "$nccl_dir/all_reduce_perf" |
        awk '$1 ~ /^libmpi[.]so[.]/ && $2 == "=>" {print $3}')
    nccl_mpi_dir=${nccl_mpi_lib%/lib*/libmpi.so.*}
    if [[ "$nccl_mpi_dir" != /opt/openmpi-* ||
          ! -x "$nccl_mpi_dir/bin/mpirun" ||
          ! -f "$nccl_mpi_dir/bin/mpivars.sh" ]]; then
        echo "Cannot resolve the NCCL binary's MPI installation under /opt/openmpi-*" >&2
        exit 1
    fi
    nccl_mpivars="$nccl_mpi_dir/bin/mpivars.sh"
fi

'''


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected exactly one occurrence of: {old}")
    return text.replace(old, new, 1)


def patch_healthcheck(text, function_name):
    function = next(
        node for node in ast.parse(text).body
        if isinstance(node, ast.FunctionDef) and node.name == function_name
    )
    lines = text.splitlines(keepends=True)
    start, end = function.lineno - 1, function.end_lineno
    body = "".join(lines[start:end])
    if LEGACY_DIR not in body or VENDOR_MPI not in body:
        raise ValueError("Expected released NCCL executable and vendor MPI paths")

    if function_name == "run_local_nccl_test":
        if body.count(LEGACY_DIR) != body.count("source " + VENDOR_MPI):
            raise ValueError("Unexpected local NCCL command layout")
        body = body.replace(LEGACY_DIR, "{nccl_dir}")
        body = body.replace(VENDOR_MPI, "{nccl_mpivars}")
    else:
        body = replace_once(body, "glob.glob('" + VENDOR_MPI + "')", "glob.glob(nccl_mpivars)")
        body = replace_once(
            body, 'exec_cmd="' + LEGACY_DIR + '/all_reduce_perf"',
            'exec_cmd=f"{nccl_dir}/all_reduce_perf"',
        )

    signature, rest = body.split("\n", 1)
    body = signature + "\n" + PYTHON_SELECT + rest
    lines[start:end] = [MARKER + "\n" + PYTHON_PATHS + body]
    return "".join(lines)


def patch_benchmark(text):
    active_lines = [line for line in text.splitlines() if not line.lstrip().startswith("#")]
    if not any(LEGACY_DIR in line for line in active_lines):
        return text
    if not text.startswith("#!/bin/bash"):
        raise ValueError("Expected a Bash NCCL sample")
    # Remove only the exact known orphaned tail, not arbitrary syntax errors.
    if text.rstrip().endswith("done\n\n\n\n\n\n" + ALLTOALL_TAIL):
        text = text[:text.rfind(ALLTOALL_TAIL)].rstrip() + "\n"
    text = replace_once(
        text, "mpivars_path=`ls " + VENDOR_MPI + "`",
        'mpivars_path="${nccl_mpivars:-$(ls ' + VENDOR_MPI + ')}"',
    )
    text = text.replace(LEGACY_DIR, "${nccl_dir}")
    # Keep all leading Slurm directives ahead of executable shell statements.
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.strip() and not line.lstrip().startswith("#"))
    lines.insert(start, MARKER + "\n" + SHELL_PATHS)
    text = "".join(lines)
    if re.search(r"(?m)^\s*hostfile=", text) and not re.search(r"(?m)^\s*MACHINEFILE=", text):
        # Several released .sh variants pass an undefined MACHINEFILE.
        text = text.replace('--input_file $MACHINEFILE', '--input_file "$hostfile"')
    # QFAB allreduce samples contain a space after the continuation backslash.
    text = re.sub(r"\\[ \t]+\n", "\\\n", text)
    return text


def patched_text(path, text):
    if MARKER in text:
        return text
    function_name = HEALTHCHECKS.get(path.name)
    if function_name:
        return patch_healthcheck(text, function_name)
    if path.suffix in (".sh", ".sbatch"):
        return patch_benchmark(text)
    raise ValueError("Expected a .sh/.sbatch sample or a supported healthcheck: " + str(path))


def expand_targets(paths):
    targets = []
    for path in paths:
        if path.is_dir():
            targets.extend(sorted(p for p in path.iterdir() if p.is_file() and p.suffix in (".sh", ".sbatch")))
        else:
            targets.append(path)
    if not targets:
        raise ValueError("No .sh/.sbatch samples found")
    return dict.fromkeys(path.resolve() for path in targets)


def validate(path, text):
    if path.suffix == ".py":
        compile(text, str(path), "exec")
    else:
        subprocess.run(["bash", "-n"], input=text, text=True, check=True)


def write_file(path, text, metadata_source):
    """Replace one file atomically, preserving its owner and permissions."""
    metadata = metadata_source.stat()
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        output.write(text)
    try:
        os.chown(temporary, metadata.st_uid, metadata.st_gid)
        shutil.copystat(metadata_source, temporary)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path, help="sample scripts/directories or healthcheck Python files")
    parser.add_argument("--apply", action="store_true", help="write changes (default: diff only)")
    parser.add_argument("--restore", action="store_true", help="restore .pre-nccl-bvr backups; needs --apply to write")
    args = parser.parse_args()
    changes = []

    # Prepare and validate every target before touching any file.
    for path in expand_targets(args.files):
        original = path.read_text()
        backup = path.with_name(path.name + BACKUP_SUFFIX)
        if args.restore:
            if not backup.exists():
                if MARKER in original or patched_text(path, original) != original:
                    raise ValueError("Missing backup: " + str(backup))
                print("Unchanged (no repair backup): " + str(path))
                continue
            updated = backup.read_text()
            if original not in (updated, patched_text(path, updated)):
                raise ValueError("File changed after repair; review before restoring: " + str(path))
        else:
            updated = patched_text(path, original)
            if updated != original and backup.exists() and backup.read_text() != original:
                raise ValueError("Different backup already exists; refusing to overwrite: " + str(backup))
        if updated == original:
            print("Unchanged: " + str(path))
            continue
        # Backups can contain pre-existing syntax defects repaired by this tool.
        # Restoration above requires an exact original/repaired-content match.
        if not args.restore:
            validate(path, updated)
        print("".join(difflib.unified_diff(
            original.splitlines(keepends=True), updated.splitlines(keepends=True),
            fromfile=str(path), tofile=str(path) + (" (restored)" if args.restore else " (repaired)"),
        )), end="")
        changes.append((path, backup, original, updated))

    if not args.apply:
        print("Preview only; use --apply to write these changes.")
        return
    for path, backup, original, updated in changes:
        if not args.restore and not backup.exists():
            write_file(backup, original, path)
        write_file(path, updated, backup)
        print(("Restored: " if args.restore else "Repaired: ") + str(path))
        print("Backup retained: " + str(backup))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, SyntaxError, StopIteration, subprocess.CalledProcessError) as error:
        sys.exit("NCCL BVR fixup failed: " + (str(error) or "Expected NCCL function not found"))
