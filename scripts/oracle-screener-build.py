#!/usr/bin/env python3
"""Generate and build Oracle's isolated, opt-in Screener simulator project."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = Path.home() / '.codex/skills/tb5-build-cache/scripts/tb5_paths.py'

def run(args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Exact iOS Simulator UUID')
    args = parser.parse_args()
    paths = json.loads(run([sys.executable, str(PREFLIGHT), '--project', str(ROOT)],
                           capture_output=True, text=True).stdout)
    # Xcode and XcodeGen can rewrite Package.resolved and generated plists.
    # Copy tracked sources and this integration's inputs to a new TB5 directory.
    build_root = Path(paths['build_root'])
    build_root.mkdir(parents=True, exist_ok=True)
    run_root = Path(tempfile.mkdtemp(prefix='screener-', dir=build_root))
    source = run_root / 'source'
    source.mkdir()
    files = run(['git', 'ls-files', '-z', '--cached'], capture_output=True).stdout
    for name in ['project.oracle-screener.yml', 'OracleBallApp/pages/oracle/ui/OracleScreenerProbe.swift']:
        if (ROOT / name).is_file():
            files += name.encode() + b'\0'
    run(['rsync', '-a', '--from0', '--files-from=-', str(ROOT) + '/', str(source) + '/'],
        input=files)
    generated = run_root / 'generated'
    generated.mkdir()
    for name in ['OracleBallApp', 'OracleWidgets', 'OracleModelDownloader', 'OracleWidgetsExtension.entitlements']:
        target = source / name
        (generated / name).symlink_to(target, target_is_directory=target.is_dir())
    env = os.environ.copy()
    env['ORACLE_SCREENER_ROOT'] = str(source)
    run(['xcodegen', 'generate', '--spec', str(source / 'project.oracle-screener.yml'),
         '--project', str(generated), '--project-root', str(source)], env=env)
    run(['xcodebuild', '-project', str(generated / 'OracleScreener.xcodeproj'),
         '-scheme', 'OracleBallApp', '-configuration', 'Debug',
         '-destination', 'id=' + args.device,
         '-derivedDataPath', paths['xcode_derived_data'],
         '-clonedSourcePackagesDirPath', paths['xcode_source_packages'],
         '-packageCachePath', paths['swiftpm_cache'], '-IDEBuildLocationStyle=Unique',
         'CODE_SIGNING_ALLOWED=NO', 'build', '-quiet'])
    print('Source snapshot:', source)
    print('App:', Path(paths['xcode_derived_data']) / 'Build/Products/Debug-iphonesimulator/OracleBallApp.app')


if __name__ == '__main__':
    main()
