#!/usr/bin/env python3
"""Archive Oracle using the next App Store Connect build number."""
import argparse
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Marketing version, for example 1.0")
    parser.add_argument("--archive-path", required=True)
    parser.add_argument("--profile", help="asc authentication profile")
    parser.add_argument("xcodebuild_args", nargs=argparse.REMAINDER,
                        help="Xcode build flags after --, including signing and output paths")
    args = parser.parse_args()
    archive = Path(args.archive_path).expanduser().resolve()
    if archive.exists():
        parser.error("archive path already exists")
    command = ["asc"]
    if args.profile:
        command += ["--profile", args.profile]
    command += ["builds", "next-build-number", "--app", "6827254640", "--version", args.version,
                "--platform", "IOS", "--output", "json"]
    result = json.loads(subprocess.check_output(command, text=True))
    number = str(result["nextBuildNumber"])
    if not number.isascii() or not number.isdigit() or int(number) < 1:
        raise ValueError("App Store Connect returned an invalid build number")
    extra = args.xcodebuild_args
    if extra and extra[0] == "--":
        extra = extra[1:]
    # Prevent caller-provided flags from silently changing the audited number.
    if any(arg.startswith(("CURRENT_PROJECT_VERSION=", "MARKETING_VERSION=")) for arg in extra):
        parser.error("version overrides are supplied by this script")
    repo = Path(__file__).resolve().parent.parent
    print(f"Archiving Oracle {args.version} ({number}); the lookup does not reserve the number.", flush=True)
    subprocess.run(["xcodebuild", "-project", str(repo / "CityChainApp.xcodeproj"),
                    "-scheme", "OracleBallApp", "-configuration", "Release", "-destination",
                    "generic/platform=iOS", "-archivePath", str(archive),
                    f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={number}",
                    *extra, "archive"], cwd=repo, check=True)


if __name__ == "__main__":
    main()
