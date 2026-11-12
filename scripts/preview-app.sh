#!/bin/bash
set -euo pipefail
CODEXMETER_REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
exec python3 - "$CODEXMETER_REPOSITORY_ROOT" "$@" <<'PY'
import argparse
import ctypes
from datetime import datetime, timezone
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import zipfile

repository = Path(sys.argv.pop(1))
preview = Path('/private/tmp/codexmeter-unified-hud-qa/dashboard/CodexMeter.app')
preview_id = 'io.github.codexmeter.unified-hud-qa.dashboard'
source = repository / 'build/CodexMeter.app'
executable = preview / 'Contents/MacOS/CodexMeter'

parser = argparse.ArgumentParser(
    description='Update the existing fixed preview in place; never create another preview identity.',
    epilog='Launch example: scripts/preview-app.sh --launch -- --ui-preview-fixtures --show-settings')
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--prepare-only', dest='mode', action='store_const', const='prepare',
                  help='verify and update the existing preview without launching (default)')
mode.add_argument('--launch', dest='mode', action='store_const', const='launch',
                  help='prepare, then launch the same preview; default arguments use fixtures and workspace')
mode.add_argument('--launch-existing', dest='mode', action='store_const', const='launch-existing',
                  help='verify and relaunch the same package without copying or signing it')
mode.add_argument('--stop', dest='mode', action='store_const', const='stop',
                  help='verify and stop only the fixed preview without updating its contents')
mode.add_argument('--check', dest='mode', action='store_const', const='check',
                  help='read-only check of the fixed path, identifier, signature and running duplicates')
parser.add_argument('app_args', nargs=argparse.REMAINDER, help='exact application arguments after --')
parser.add_argument('--motion-playground', action='store_true',
                    help='replace only the executable with the standalone Motion Playground build')
parser.set_defaults(mode='prepare')
args = parser.parse_args()
app_args = args.app_args[1:] if args.app_args[:1] == ['--'] else args.app_args
launch_modes = ('launch', 'launch-existing')
if app_args and args.mode not in launch_modes:
    parser.error('application arguments require --launch or --launch-existing')
if app_args and '--ui-preview-fixtures' not in app_args:
    parser.error('preview launch arguments must include --ui-preview-fixtures; use the installed app for real data')


def run(*command):
    subprocess.run([str(value) for value in command], check=True)


def info(app):
    with (app / 'Contents/Info.plist').open('rb') as handle:
        return plistlib.load(handle)


def verify_preview():
    if not preview.is_dir() or preview.is_symlink() or preview.resolve() != preview:
        raise RuntimeError(f'The existing preview must be a real directory at {preview}')
    metadata = info(preview)
    if metadata.get('CFBundleIdentifier') != preview_id or metadata.get('CFBundleExecutable') != 'CodexMeter':
        raise RuntimeError('The existing preview identity does not match the fixed preview; refusing replacement')
    if not metadata.get('CFBundleName'):
        raise RuntimeError('The existing preview has no bundle name to preserve')
    run('/usr/bin/codesign', '--verify', '--strict', preview)
    return metadata


def process_inventory():
    # Kernel executable paths normalize /tmp aliases without parsing process arguments.
    library = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    pids = subprocess.check_output(['/bin/ps', '-axo', 'pid='], text=True).split()
    matches = []
    foreign = []
    for value in pids:
        pid = int(value)
        buffer = ctypes.create_string_buffer(4096)
        if library.proc_pidpath(pid, buffer, len(buffer)) <= 0:
            continue
        path = Path(os.path.realpath(os.fsdecode(buffer.value)))
        if path == executable:
            matches.append(pid)
        elif path.name == 'CodexMeter' and path.parent.name == 'MacOS':
            app = path.parent.parent.parent
            try:
                if info(app).get('CFBundleIdentifier') == preview_id:
                    foreign.append((pid, str(app)))
            except (OSError, plistlib.InvalidFileException, ValueError):
                continue
    if foreign:
        raise RuntimeError(f'The fixed preview identifier is running from another path: {foreign}')
    return matches


def stop_preview():
    pids = process_inventory()
    for pid in pids:
        if pid in process_inventory():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 15
    while process_inventory():
        if time.monotonic() >= deadline:
            raise RuntimeError('Preview did not stop within 15 seconds; no application contents were changed')
        time.sleep(0.1)
    # Recheck immediately before copying or replacing the existing Contents directory.
    if process_inventory():
        raise RuntimeError('Preview restarted during preparation; refusing to replace a running application')


def copy_contents(origin, destination):
    run('/usr/bin/ditto', '--norsrc', origin, destination)


def prepare():
    original = verify_preview()
    if not source.is_dir() or source.resolve() == preview:
        raise RuntimeError(f'Build the source application first: {source}')
    source_info = info(source)
    if source_info.get('CFBundleIdentifier') != 'io.github.codexmeter.app':
        raise RuntimeError('The repository build does not have the expected production bundle identifier')
    if source_info.get('CFBundleExecutable') != 'CodexMeter':
        raise RuntimeError('The repository build has an unexpected executable')
    run('/usr/bin/codesign', '--verify', '--strict', source)
    run(source / 'Contents/MacOS/CodexMeter', '--verify-resources')
    process_inventory()
    holding = Path(tempfile.mkdtemp(prefix='codexmeter-preview-holding-', dir='/private/tmp'))
    candidate = holding / 'candidate-contents'
    previous = holding / 'previous-contents'
    changed = False
    keep_holding = False
    try:
        # Holding directories contain Contents payloads, never another .app bundle.
        copy_contents(source / 'Contents', candidate)
        with (candidate / 'Info.plist').open('rb') as handle:
            metadata = plistlib.load(handle)
        metadata['CFBundleIdentifier'] = preview_id
        metadata['CFBundleName'] = original['CFBundleName']
        if 'CFBundleDisplayName' in original:
            metadata['CFBundleDisplayName'] = original['CFBundleDisplayName']
        with (candidate / 'Info.plist').open('wb') as handle:
            plistlib.dump(metadata, handle)
        stop_preview()
        copy_contents(preview / 'Contents', previous)
        if process_inventory():
            raise RuntimeError('Preview restarted before replacement; no application contents were changed')
        changed = True
        shutil.rmtree(preview / 'Contents')
        copy_contents(candidate, preview / 'Contents')
        run('/usr/bin/codesign', '--force', '--sign', '-', preview)
        verify_preview()
        run(executable, '--verify-resources')
    except Exception:
        if changed:
            try:
                if (preview / 'Contents').exists():
                    shutil.rmtree(preview / 'Contents')
                copy_contents(previous, preview / 'Contents')
                verify_preview()
            except Exception as restore_error:
                keep_holding = True
                print(f'Recovery payload retained at {previous}: {restore_error}', file=sys.stderr)
        raise
    finally:
        if not keep_holding:
            shutil.rmtree(holding)
    print(f'Prepared existing preview: {preview} [{preview_id}]')


def archive_preview(holding):
    backups = repository / 'build/motion-playground/backups'
    backups.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    archive = holding / 'preview-backup.zip'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', preview, archive)
    with zipfile.ZipFile(archive) as handle:
        failed = handle.testzip()
        required = {'CodexMeter.app/Contents/Info.plist',
                    'CodexMeter.app/Contents/MacOS/CodexMeter'}
        if failed or not required.issubset(handle.namelist()):
            raise RuntimeError(f'Preview backup failed ZIP verification: {failed or "missing package files"}')
    destination = backups / f'preview-{stamp}.zip'
    shutil.move(archive, destination)
    print(f'Preserved CRC-verified preview backup: {destination}')


def prepare_motion_playground():
    verify_preview()
    motion_binary = repository / 'build/motion-playground/OrbMotionPlayground'
    if not motion_binary.is_file() or not os.access(motion_binary, os.X_OK):
        raise RuntimeError(f'Build the standalone Motion Playground first: {motion_binary}')
    run(motion_binary, '--verify-resources')
    process_inventory()
    holding = Path(tempfile.mkdtemp(prefix='codexmeter-preview-holding-', dir='/private/tmp'))
    candidate = holding / 'candidate-contents'
    previous = holding / 'previous-contents'
    changed = False
    keep_holding = False
    try:
        stop_preview()
        archive_preview(holding)
        # Reuse the retained package identity, resources and isolated preferences.
        copy_contents(preview / 'Contents', candidate)
        shutil.copy2(motion_binary, candidate / 'MacOS/CodexMeter')
        copy_contents(preview / 'Contents', previous)
        if process_inventory():
            raise RuntimeError('Preview restarted before replacement; no application contents were changed')
        changed = True
        shutil.rmtree(preview / 'Contents')
        copy_contents(candidate, preview / 'Contents')
        run('/usr/bin/codesign', '--force', '--sign', '-', preview)
        verify_preview()
        run(executable, '--verify-resources')
    except Exception:
        if changed:
            try:
                if (preview / 'Contents').exists():
                    shutil.rmtree(preview / 'Contents')
                copy_contents(previous, preview / 'Contents')
                verify_preview()
            except Exception as restore_error:
                keep_holding = True
                print(f'Recovery payload retained at {previous}: {restore_error}', file=sys.stderr)
        raise
    finally:
        if not keep_holding:
            shutil.rmtree(holding)
    print(f'Prepared standalone Motion Playground in existing preview: {preview} [{preview_id}]')


def main():
    if args.mode == 'check':
        verify_preview()
        pids = process_inventory()
        if len(pids) > 1:
            raise RuntimeError(f'Multiple fixed preview processes are running: {pids}')
        print(f'Preview verified: {preview} [{preview_id}]; running processes: {len(pids)}')
        return
    if not preview.parent.is_dir():
        raise RuntimeError('The fixed preview parent is missing; this helper does not create preview identities')
    with (preview.parent / '.preview-app.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another preview update is already running')
        if args.mode in ('stop', 'launch-existing'):
            verify_preview()
            stop_preview()
            if args.mode == 'stop':
                print(f'Stopped fixed preview: {preview}')
                return
        else:
            if args.motion_playground:
                prepare_motion_playground()
            else:
                prepare()
        if args.mode in launch_modes:
            if process_inventory():
                raise RuntimeError('Preview restarted before launch; refusing a duplicate launch')
            launch_args = app_args or ['--ui-preview-fixtures', '--show-workspace']
            run('/usr/bin/open', preview, '--args', *launch_args)
            deadline = time.monotonic() + 10
            while True:
                pids = process_inventory()
                if len(pids) == 1:
                    print(f'Launched fixed preview process: {pids[0]}')
                    break
                if len(pids) > 1 or time.monotonic() >= deadline:
                    raise RuntimeError(f'Expected one fixed preview process after launch; found {pids}')
                time.sleep(0.1)


try:
    main()
except (OSError, RuntimeError, ValueError, plistlib.InvalidFileException,
        subprocess.CalledProcessError, zipfile.BadZipFile) as error:
    print(f'preview-app: {error}', file=sys.stderr)
    sys.exit(1)
PY
