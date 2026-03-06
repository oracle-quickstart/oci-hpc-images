#!/usr/bin/env python3

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "python-hcl2",
#   "tabulate",
# ]
# ///

import argparse
import glob
import os
import pathlib
import sys

import hcl2
from tabulate import tabulate

def setup_cli():
    parser = argparse.ArgumentParser(
        description="Utility that lists all image flavors and their configurations"
    )
    parser.add_argument(
        "image_dir",
        default="images/",
        nargs='?',
        type=pathlib.Path,
        help="The base directory in which to find image configurations",
    )
    args = parser.parse_args()
    return args



def main():
    args = setup_cli()

    image_configs = {'image': [], 'build options': [], 'build groups': []}
    images = glob.glob('**/*.hcl', root_dir=args.image_dir, recursive=True)
    images.sort() 
    for path in images:
        with open(args.image_dir / path, 'r') as file:
            pkr_file = hcl2.load(file)
        build_options = []
        build_groups = []
        for var in pkr_file['variable']:
            if 'build_options' in var:
                build_options = var['build_options']['default'].split(',')
            if 'build_groups' in var:
                build_groups = var['build_groups']['default']
        image_name = os.path.basename(path)
        image_configs['image'].append(image_name)
        image_configs['build options'].append(', '.join(build_options))
        image_configs['build groups'].append(', '.join(build_groups))
    print(tabulate(image_configs, headers="keys", maxcolwidths=[48, 22, 22]))


if __name__ == "__main__":
    main()
