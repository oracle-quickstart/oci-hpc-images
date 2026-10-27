#!/usr/bin/env python3
"""
Mirror OKE APT repositories for offline/local use in custom images.

Usage:
    ./mirror-oke-repos.py OUTPUT_DIR UBUNTU_VERSION KUBERNETES_VERSION ARCHITECTURE

Arguments:
    OUTPUT_DIR          - Where to save mirrored repositories
    UBUNTU_VERSION      - Which Ubuntu to mirror: 22, 24, jammy, noble, or all
    KUBERNETES_VERSION  - Kubernetes repository version, such as 1.36
    ARCHITECTURE        - Debian architecture: amd64 or arm64

Environment Variables:
    OKE_PAR_BASE    - Override the default PAR URL for the OKE packages repository

Examples:
    ./mirror-oke-repos.py ./local-repos jammy 1.36 amd64
    ./mirror-oke-repos.py ./local-repos noble 1.36 arm64
    OKE_PAR_BASE="https://..." ./mirror-oke-repos.py ./local-repos 24 1.36 amd64
"""

import gzip
import os
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# PAR URL - can be overridden via OKE_PAR_BASE environment variable
_DEFAULT_PAR_BASE = (
    "https://objectstorage.us-sanjose-1.oraclecloud.com/p/"
    "_Zaa2khW3lPESEbqZ2JB3FijAd0HeKmiP-KA2eOMuWwro85dcG2WAqua2o_a-PlZ/"
    "n/odx-oke/b/okn-repositories-private/o/prod"
)
PAR_BASE = os.environ.get("OKE_PAR_BASE", _DEFAULT_PAR_BASE)

SUPPORTED_ARCHITECTURES = {"amd64", "arm64"}

# Ubuntu version mappings
UBUNTU_VERSIONS = {
    "22": "jammy",
    "24": "noble",
    "jammy": "jammy",
    "noble": "noble",
}

# Number of parallel downloads
MAX_WORKERS = 8


@dataclass
class DownloadResult:
    url: str
    dest: str
    success: bool
    error: Optional[str] = None


def download_file(url: str, dest: Path, retries: int = 3) -> DownloadResult:
    """Download a file with retries."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "OKE-Mirror/1.0"})
            with urllib.request.urlopen(req, timeout=30) as response:
                dest.write_bytes(response.read())
            return DownloadResult(url, str(dest), True)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return DownloadResult(url, str(dest), False, "404 Not Found")
            if attempt == retries - 1:
                return DownloadResult(url, str(dest), False, str(e))
        except Exception as e:
            if attempt == retries - 1:
                return DownloadResult(url, str(dest), False, str(e))
    
    return DownloadResult(url, str(dest), False, "Max retries exceeded")


def parse_release_file(release_path: Path) -> list[str]:
    """Parse Release file to extract metadata file paths from MD5Sum section."""
    content = release_path.read_text()
    files = []
    in_md5sum = False
    
    for line in content.splitlines():
        if line.startswith("MD5Sum:"):
            in_md5sum = True
            continue
        if in_md5sum:
            if line and line[0].isupper() and ":" in line:
                # Hit next section (SHA1:, SHA256:, etc.)
                break
            parts = line.split()
            if len(parts) == 3:
                # Format: <hash> <size> <filename>
                files.append(parts[2])
    
    return files


def parse_packages_file(packages_path: Path) -> list[str]:
    """Parse Packages file to extract .deb file paths."""
    content = packages_path.read_text()
    deb_files = []
    
    for line in content.splitlines():
        if line.startswith("Filename:"):
            deb_files.append(line.split(": ", 1)[1])
    
    return deb_files


def decompress_packages(local_dir: Path, arch: str) -> Optional[Path]:
    """Decompress Packages.gz or Packages.bz2 if present for the given architecture."""
    packages_dir = local_dir / "dists/stable/main" / f"binary-{arch}"
    packages_plain = packages_dir / "Packages"
    packages_gz = packages_dir / "Packages.gz"

    if packages_gz.exists():
        try:
            with gzip.open(packages_gz, "rb") as f:
                packages_plain.write_bytes(f.read())
            return packages_plain
        except Exception:
            pass

    if packages_plain.exists():
        return packages_plain

    return None


def mirror_repository(
    ubuntu: str, k8s: str, architecture: str, output_dir: Path
) -> tuple[str, str, int, int, int]:
    """
    Mirror a single repository.
    Returns: (repo_key, status, pkg_count, meta_count, total_files)
    """
    repo_key = f"ubuntu-{ubuntu}/kubernetes-{k8s}"
    repo_url = f"{PAR_BASE}/ubuntu-{ubuntu}/kubernetes-{k8s}"
    local_dir = output_dir / f"ubuntu-{ubuntu}" / f"kubernetes-{k8s}"
    
    print(f"\n{'='*60}")
    print(f"Mirroring: {repo_key}")
    print(f"  URL: {repo_url}")
    print(f"  Local: {local_dir}")
    print(f"{'='*60}")
    
    local_dir.mkdir(parents=True, exist_ok=True)
    
    # Step 1: Download Release file
    print("\n[1/4] Downloading Release file...")
    release_url = f"{repo_url}/dists/stable/Release"
    release_path = local_dir / "dists/stable/Release"
    result = download_file(release_url, release_path)
    
    if not result.success:
        print(f"  ✗ Failed to download Release: {result.error}")
        return repo_key, "FAILED", 0, 0, 0
    print("  ✓ Release")
    
    # Also try Release.gpg (optional)
    download_file(f"{repo_url}/dists/stable/Release.gpg", 
                  local_dir / "dists/stable/Release.gpg")
    
    # Step 2: Parse Release and download metadata files
    print("\n[2/4] Downloading metadata files...")
    metadata_files = [
        file
        for file in parse_release_file(release_path)
        if architecture in file
        or not any(arch in file for arch in SUPPORTED_ARCHITECTURES)
    ]
    
    if not metadata_files:
        print("  ✗ No metadata files found in Release")
        return repo_key, "FAILED", 0, 0, 0
    
    # Download metadata files in parallel
    meta_downloads = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {}
        for file in metadata_files:
            url = f"{repo_url}/dists/stable/{file}"
            dest = local_dir / "dists/stable" / file
            futures[executor.submit(download_file, url, dest)] = file
        
        for future in as_completed(futures):
            result = future.result()
            meta_downloads.append(result)
            if result.success:
                print(f"  ✓ {futures[future]}")
    
    meta_success = sum(1 for r in meta_downloads if r.success)
    print(f"  Downloaded {meta_success}/{len(metadata_files)} metadata files")
    
    # Step 3: Decompress and parse the Packages file
    print("\n[3/4] Parsing package list...")
    packages_path = decompress_packages(local_dir, architecture)
    if not packages_path:
        print(f"  ✗ No Packages file found for {architecture}")
        return repo_key, "INCOMPLETE", 0, meta_success, meta_success

    deb_files = parse_packages_file(packages_path)
    print(f"  Found {len(deb_files)} packages for {architecture}")

    if not deb_files:
        print("  ✗ No packages found in Packages file")
        return repo_key, "INCOMPLETE", 0, meta_success, meta_success

    # Step 4: Download .deb packages in parallel
    print(f"\n[4/4] Downloading {len(deb_files)} unique packages...")
    pkg_downloads = []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {}
        for deb_path in deb_files:
            url = f"{repo_url}/{deb_path}"
            dest = local_dir / deb_path
            futures[executor.submit(download_file, url, dest)] = deb_path

        completed = 0
        for future in as_completed(futures):
            result = future.result()
            pkg_downloads.append(result)
            completed += 1

            # Progress indicator
            filename = Path(futures[future]).name
            status = "✓" if result.success else "✗"
            print(f"  [{completed}/{len(deb_files)}] {status} {filename}")

    pkg_success = sum(1 for r in pkg_downloads if r.success)
    print(f"\n  Downloaded {pkg_success}/{len(deb_files)} packages")
    
    if pkg_success > 0:
        return repo_key, "SUCCESS", pkg_success, meta_success, pkg_success + meta_success
    else:
        return repo_key, "INCOMPLETE", 0, meta_success, meta_success


def get_total_size(path: Path) -> str:
    """Get human-readable size of directory."""
    total = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    
    for unit in ["B", "KB", "MB", "GB"]:
        if total < 1024:
            return f"{total:.1f} {unit}"
        total /= 1024
    return f"{total:.1f} TB"


def main():
    # Parse arguments
    if len(sys.argv) != 5:
        print(
            "Usage: mirror-oke-repos.py OUTPUT_DIR UBUNTU_VERSION "
            "KUBERNETES_VERSION ARCHITECTURE"
        )
        sys.exit(1)

    output_dir = Path(sys.argv[1])
    ubuntu_arg = sys.argv[2]
    k8s_version = sys.argv[3]
    architecture = sys.argv[4]
    
    # Determine Ubuntu versions to mirror
    if ubuntu_arg.lower() == "all":
        ubuntu_versions = ["jammy", "noble"]
    elif ubuntu_arg in UBUNTU_VERSIONS:
        ubuntu_versions = [UBUNTU_VERSIONS[ubuntu_arg]]
    else:
        print(f"Error: Invalid Ubuntu version '{ubuntu_arg}'")
        print("Valid options: 22, 24, all (or jammy, noble)")
        sys.exit(1)

    version_parts = k8s_version.split(".")
    if len(version_parts) != 2 or not all(part.isdigit() for part in version_parts):
        print(f"Error: Invalid Kubernetes version '{k8s_version}'")
        print("Use the major.minor format, such as 1.36")
        sys.exit(1)

    if architecture not in SUPPORTED_ARCHITECTURES:
        print(f"Error: Invalid architecture '{architecture}'")
        print("Valid architectures: amd64, arm64")
        sys.exit(1)
    
    print("=" * 60)
    print("OKE APT Repository Mirror (Python)")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print(f"Ubuntu versions:  {', '.join(ubuntu_versions)}")
    print(f"K8s version:      {k8s_version}")
    print(f"Architecture:     {architecture}")
    print(f"Parallel workers: {MAX_WORKERS}")
    print("=" * 60)
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Mirror each repository
    results = []
    for ubuntu in ubuntu_versions:
        result = mirror_repository(ubuntu, k8s_version, architecture, output_dir)
        results.append(result)
    
    # Print summary
    print("\n" + "=" * 60)
    print("Mirror Summary")
    print("=" * 60)
    
    for repo_key, status, pkg_count, meta_count, _ in sorted(results):
        if status == "SUCCESS":
            status_str = f"SUCCESS ({pkg_count} pkgs, {meta_count} meta)"
        else:
            status_str = status
        print(f"  {repo_key:40} {status_str}")
    
    print(f"\nTotal size: {get_total_size(output_dir)}")
    print(f"Output at: {output_dir}")
    print("\nNext steps:")
    print(f"  1. Copy {output_dir} to /opt/oke-node-client-packages/ on your image")
    print("  2. Use oke-ubuntu-cloud-init.sh (will auto-detect local repo)")


if __name__ == "__main__":
    main()
