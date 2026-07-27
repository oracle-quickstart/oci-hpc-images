#!/usr/bin/env python3
"""
Mirror OKE APT repositories for offline/local use in custom images.

Usage:
    ./mirror-oke-repos.py [OUTPUT_DIR] [UBUNTU_VERSION]

Arguments:
    OUTPUT_DIR      - Where to save mirrored repos (default: /opt/oke-node-client-packages)
    UBUNTU_VERSION  - Which Ubuntu to mirror: 22, 24, or all (default: all)
                      22 = jammy (Ubuntu 22.04)
                      24 = noble (Ubuntu 24.04)
                      all = both versions

Environment Variables:
    OKE_PAR_BASE    - Override the default PAR URL for the OKE packages repository

Examples:
    ./mirror-oke-repos.py                           # Mirror all to default location
    ./mirror-oke-repos.py ./local-repos             # Mirror all to ./local-repos
    ./mirror-oke-repos.py ./local-repos 22          # Mirror Ubuntu 22.04 only
    ./mirror-oke-repos.py ./local-repos 24          # Mirror Ubuntu 24.04 only
    OKE_PAR_BASE="https://..." ./mirror-oke-repos.py  # Use custom PAR URL
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

# Kubernetes versions to mirror
K8S_VERSIONS = ["1.33", "1.34", "1.35", "1.36"]

# Architectures to mirror
ARCHITECTURES = ["amd64", "arm64"]

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
    ubuntu: str, k8s: str, output_dir: Path
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
    metadata_files = parse_release_file(release_path)
    
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
    
    # Step 3: Decompress and parse Packages files for each architecture
    print("\n[3/4] Parsing package lists...")
    deb_files: list[str] = []
    seen: set[str] = set()
    for arch in ARCHITECTURES:
        packages_path = decompress_packages(local_dir, arch)
        if not packages_path:
            print(f"  ✗ No Packages file found for {arch}")
            continue
        arch_debs = parse_packages_file(packages_path)
        print(f"  Found {len(arch_debs)} packages for {arch}")
        for deb in arch_debs:
            if deb not in seen:
                seen.add(deb)
                deb_files.append(deb)

    if not deb_files:
        print("  ✗ No packages found in any Packages file")
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
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/opt/oke-node-client-packages")
    ubuntu_arg = sys.argv[2] if len(sys.argv) > 2 else "all"
    
    # Determine Ubuntu versions to mirror
    if ubuntu_arg.lower() == "all":
        ubuntu_versions = ["jammy", "noble"]
    elif ubuntu_arg in UBUNTU_VERSIONS:
        ubuntu_versions = [UBUNTU_VERSIONS[ubuntu_arg]]
    else:
        print(f"Error: Invalid Ubuntu version '{ubuntu_arg}'")
        print("Valid options: 22, 24, all (or jammy, noble)")
        sys.exit(1)
    
    print("=" * 60)
    print("OKE APT Repository Mirror (Python)")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print(f"Ubuntu versions:  {', '.join(ubuntu_versions)}")
    print(f"K8s versions:     {', '.join(K8S_VERSIONS)}")
    print(f"Parallel workers: {MAX_WORKERS}")
    print("=" * 60)
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Mirror each repository
    results = []
    for ubuntu in ubuntu_versions:
        for k8s in K8S_VERSIONS:
            result = mirror_repository(ubuntu, k8s, output_dir)
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
