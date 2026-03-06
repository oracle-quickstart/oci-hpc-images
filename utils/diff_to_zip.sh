#!/usr/bin/env bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes


script_name="$(basename "$0")"

usage() {
    cat <<EOF
Usage: ${script_name} [OPTIONS] <oci-hpc-images-export-zipfile> [<working-dir>]

Positional arguments:
  oci-hpc-images-export-zipfile    An exported zip archive for oci-hpc-images
  working-dir                      Working directory where the zip had been exported to
                                   (default: current working dir ./)

Options:
  -o                 output diff file
  -h                 Show this help and exit

Examples:
  ${script_name}  oci-hpc-images-main.zip oci-hpc-images/
  ${script_name} -o fixes.diff oci-hpc-images-my-branch.zip oci-hpc-images-test/
EOF
}

# defaults
DEFAULT_WORKDIR="./"

# Parse options
while getopts ":o:h" opt; do
    case "${opt}" in
        o)
            output_file="${OPTARG}"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "Error: Option -${OPTARG} requires an argument." >&2
            usage
            exit 1
            ;;
        \?)
            echo "Error: Invalid option: -${OPTARG}" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

# Positional args
if [ "$#" -lt 1 ]; then
    echo "Error: Missing required positional argument: oci-hpc-images-export-zipfile" >&2
    usage
    exit 1
fi

zipfile=$1
workdir=${2:-$DEFAULT_WORKDIR}
echo ${workdir}
exit
tmp=$(mktemp -d)
unzip -q "${zipfile}" -d "${tmp}"

if [ -n "${output_file:-}" ]; then
    diff -ruN "${tmp}" "${workdir}" | tee "${output_file}"
else
    diff -ruN "${tmp}" "${workdir}"
fi
