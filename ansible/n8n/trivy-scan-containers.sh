#!/usr/bin/env python3
"""
trivy-scan-containers.sh (Python rewrite)
Scans all running Docker container images with Trivy.
Outputs JSON summary suitable for n8n ingestion.

Usage: trivy-scan-containers.sh [HIGH,CRITICAL]
"""

import subprocess
import json
import sys
from datetime import datetime, timezone


def run_cmd(cmd, timeout=300):
    """Run a shell command and return stdout, stderr, returncode."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Command timed out", -1


def get_running_containers():
    """Get mapping of unique images to their container names."""
    stdout, _, rc = run_cmd("docker ps --format '{{.Image}}|{{.Names}}'")
    if rc != 0 or not stdout:
        return {}

    image_containers = {}
    for line in stdout.splitlines():
        parts = line.split("|", 1)
        if len(parts) != 2:
            continue
        img, name = parts
        if img in image_containers:
            image_containers[img].append(name)
        else:
            image_containers[img] = [name]

    return image_containers


def scan_image(image, severity, timeout=300):
    """Scan a single image with Trivy. Returns parsed results."""
    cmd = (
        f"trivy image --severity {severity} --format json "
        f"--quiet --skip-db-update '{image}'"
    )
    stdout, stderr, rc = run_cmd(cmd, timeout=timeout)

    # Exit code 1 means vulnerabilities found (not an error)
    if rc not in (0, 1) or not stdout:
        return None, f"Trivy exited with code {rc}: {stderr[:200]}"

    try:
        data = json.loads(stdout)
    except json.JSONDecodeError as e:
        return None, f"JSON parse error: {str(e)}"

    # Extract vulnerabilities
    high = 0
    critical = 0
    vulns = []

    for result_block in data.get("Results", []):
        for v in result_block.get("Vulnerabilities", []):
            sev = v.get("Severity", "")
            if sev == "HIGH":
                high += 1
            elif sev == "CRITICAL":
                critical += 1
            vulns.append({
                "id": v.get("VulnerabilityID", ""),
                "pkg": v.get("PkgName", ""),
                "installed": v.get("InstalledVersion", ""),
                "fixed": v.get("FixedVersion", ""),
                "severity": sev,
                "title": (v.get("Title", "") or "")[:120],
            })

    # Sort: critical first, then by ID; keep top 10
    vulns.sort(key=lambda x: (0 if x["severity"] == "CRITICAL" else 1, x["id"]))
    vulns = vulns[:10]

    return {
        "critical": critical,
        "high": high,
        "total": critical + high,
        "topVulns": vulns,
    }, None


def main():
    severity = sys.argv[1] if len(sys.argv) > 1 else "HIGH,CRITICAL"
    scan_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Get running containers
    image_containers = get_running_containers()
    if not image_containers:
        output = {
            "scanDate": scan_date,
            "error": "No running containers found",
            "severity": severity,
            "totalImages": 0,
            "scannedOk": 0,
            "scanFailed": 0,
            "totalCritical": 0,
            "totalHigh": 0,
            "containers": [],
        }
        print(json.dumps(output))
        return

    total_images = len(image_containers)
    scanned_ok = 0
    scan_failed = 0
    results = []

    for image, containers in sorted(image_containers.items()):
        containers_str = ", ".join(containers)
        print(f"Scanning: {image} ({containers_str})...", file=sys.stderr)

        scan_result, error = scan_image(image, severity)

        if scan_result is not None:
            scanned_ok += 1
            results.append({
                "image": image,
                "containers": containers_str,
                "status": "scanned",
                **scan_result,
            })
        else:
            scan_failed += 1
            results.append({
                "image": image,
                "containers": containers_str,
                "status": "scan_error",
                "error": error or "Unknown error",
                "critical": 0,
                "high": 0,
                "total": 0,
                "topVulns": [],
            })

    # Sort: most critical first
    results.sort(key=lambda x: (-x.get("critical", 0), -x.get("high", 0)))

    total_critical = sum(r.get("critical", 0) for r in results)
    total_high = sum(r.get("high", 0) for r in results)

    output = {
        "scanDate": scan_date,
        "severity": severity,
        "totalImages": total_images,
        "scannedOk": scanned_ok,
        "scanFailed": scan_failed,
        "totalCritical": total_critical,
        "totalHigh": total_high,
        "containers": results,
    }

    print(json.dumps(output))


if __name__ == "__main__":
    main()
