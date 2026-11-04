"""Download and unpack the fixed competition release. Python 3.8+, standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import ssl
import tempfile
import time
import urllib.request
import zipfile


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def download(url, path, expected_size, expected_sha, attempts=3):
    if path.exists():
        if path.stat().st_size == expected_size and digest(path) == expected_sha:
            return
        raise RuntimeError('Existing archive differs; choose another output directory: ' + str(path))
    part = path.with_name(path.name + '.part')
    for attempt in range(attempts):
        start = part.stat().st_size if part.exists() else 0
        if start == expected_size and digest(part) == expected_sha:
            part.replace(path)
            return
        if start >= expected_size:
            part.unlink()
            start = 0
        headers = {'User-Agent': 'forest-fire-fpga-downloader/1.0'}
        if start:
            headers['Range'] = 'bytes=%d-' % start
        try:
            context = ssl.create_default_context()
            for ca in (Path('C:/Program Files/Git/mingw64/etc/ssl/certs/ca-bundle.crt'), Path('C:/Program Files/Git/usr/ssl/certs/ca-bundle.crt')):
                if ca.is_file():
                    context.load_verify_locations(str(ca))
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90, context=context) as response:
                if response.status == 206:
                    content_range = response.headers.get('Content-Range', '')
                    if not content_range.startswith('bytes %d-' % start):
                        raise RuntimeError('Unexpected resumed response range')
                    mode = 'ab'
                elif response.status == 200:
                    mode = 'wb'
                    start = 0
                else:
                    raise RuntimeError('Unexpected HTTP status: %s' % response.status)
                count = start
                reported = count
                with part.open(mode) as stream:
                    for block in iter(lambda: response.read(1024 * 1024), b''):
                        count += len(block)
                        if count > expected_size:
                            raise RuntimeError('Download exceeds the pinned release size')
                        stream.write(block)
                        if count - reported >= 16 * 1024 * 1024:
                            print('Downloaded %.1f / %.1f MB' % (count / 1e6, expected_size / 1e6), flush=True)
                            reported = count
            if part.stat().st_size != expected_size:
                raise OSError('Incomplete download')
            if digest(part) != expected_sha:
                part.unlink()
                raise RuntimeError('SHA256 mismatch; extraction cancelled')
            part.replace(path)
            return
        except (OSError, TimeoutError) as error:
            if attempt + 1 == attempts:
                raise
            print('Download interrupted; retrying (%d/%d): %s' % (attempt + 1, attempts, error), flush=True)
            time.sleep(2)


def extract(archive, destination, root_name):
    target = destination / root_name
    if target.exists():
        raise RuntimeError('Project directory already exists; it will be preserved: ' + str(target))
    stage = Path(tempfile.mkdtemp(prefix='.extract-', dir=str(destination)))
    try:
        if archive.suffix.lower() == '.rar':
            extractor = shutil.which('unrar')
            if not extractor:
                candidate = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'WinRAR/UnRAR.exe'
                if candidate.is_file():
                    extractor = str(candidate)
            if not extractor:
                raise RuntimeError('Install WinRAR (Windows) or unrar (Linux), then rerun; downloaded archive is preserved')
            listing = subprocess.run([extractor, 'lb', '-scuc', str(archive)], capture_output=True, text=True, encoding='utf-8', errors='replace')
            if listing.returncode:
                raise RuntimeError('Unable to inspect RAR archive')
            for name in listing.stdout.splitlines():
                name = name.replace('\\', '/')
                relative = PurePosixPath(name)
                if (relative.is_absolute() or '..' in relative.parts or not relative.parts
                        or relative.parts[0] != root_name or any(':' in part for part in relative.parts)):
                    raise RuntimeError('Unsafe archive entry: ' + name)
            result = subprocess.run([extractor, 'x', '-idq', '-o-', '-y', str(archive), str(stage) + os.sep], capture_output=True)
            if result.returncode:
                raise RuntimeError('RAR extraction failed; download preserved for retry')
        else:
          with zipfile.ZipFile(archive) as package:
            for item in package.infolist():
                relative = PurePosixPath(item.filename)
                if (relative.is_absolute() or '..' in relative.parts or '\\' in item.filename
                        or not relative.parts or relative.parts[0] != root_name
                        or any(':' in part for part in relative.parts)
                        or stat.S_ISLNK(item.external_attr >> 16)):
                    raise RuntimeError('Unsafe archive entry: ' + item.filename)
                output = stage.joinpath(*relative.parts)
                if item.is_dir():
                    output.mkdir(parents=True, exist_ok=True)
                    continue
                output.parent.mkdir(parents=True, exist_ok=True)
                with package.open(item) as inp, output.open('wb') as out:
                    shutil.copyfileobj(inp, out)
        manifest = stage / root_name / 'MANIFEST.sha256'
        if not manifest.is_file():
            raise RuntimeError('Project manifest is missing')
        checked = 0
        for line in manifest.read_text(encoding='utf-8').splitlines():
            expected, name = line.split('  ', 1)
            relative = PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts or '\\' in name or any(':' in part for part in relative.parts):
                raise RuntimeError('Unsafe project manifest path')
            if digest(stage / root_name / Path(*relative.parts)) != expected:
                raise RuntimeError('Project file hash mismatch: ' + name)
            checked += 1
        (stage / root_name).rename(target)
        print('Project file hashes verified:', checked)
        return target
    finally:
        shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('release_manifest.json'))
    parser.add_argument('--destination', type=Path, default=Path(__file__).resolve().parent / 'downloaded')
    parser.add_argument('--download-only', action='store_true')
    args = parser.parse_args()
    release = json.loads(args.manifest.read_text(encoding='utf-8'))
    expected_url = 'https://github.com/%s/releases/download/%s/%s' % (release['repository'], release['tag'], release['asset_name'])
    if release['url'] != expected_url or not release['url'].startswith('https://github.com/'):
        raise RuntimeError('Release URL does not match its pinned repository, tag and asset')
    if Path(release['asset_name']).name != release['asset_name'] or '/' in release['asset_name'] or '\\' in release['asset_name']:
        raise RuntimeError('Invalid release asset name')
    args.destination.mkdir(parents=True, exist_ok=True)
    archive = args.destination / release['asset_name']
    if not args.download_only and (args.destination / release['archive_root']).exists():
        raise RuntimeError('Project directory already exists; use a new --destination')
    download(release['url'], archive, release['size'], release['sha256'])
    print('Release SHA256 verified:', release['sha256'])
    if args.download_only:
        print('Saved:', archive)
        return
    target = extract(archive, args.destination, release['archive_root'])
    print('Ready:', target)
    print('Read README.md; hardware: 01_hardware/project/ps_in.xpr; PC control: 03_control/start_control.py')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('ERROR: ' + str(error))
