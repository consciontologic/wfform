#!/usr/bin/env python3
"""Build receipts, smoke checks and immutable publication of the static PWA image.

The workflow supplies an allowlisted Docker context and a same-run Docker archive.
Only the human-gated publisher gets a registry credential. Nothing here deploys a
companion or grants a browser access to a host's tools.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = 'consciontologic/wfform'
SOURCE = 'https://github.com/' + REPOSITORY
IMAGE = 'ghcr.io/' + REPOSITORY
SEMVER = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')
SHA = re.compile(r'[a-f0-9]{40}')
DIGEST = re.compile(r'sha256:[a-f0-9]{64}')
MANIFEST_TYPES = ('application/vnd.oci.image.manifest.v1+json',
                  'application/vnd.docker.distribution.manifest.v2+json')


def image_reference(version):
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        raise ValueError('Container version must be plain MAJOR.MINOR.PATCH')
    return f'{IMAGE}:{version}'


def checked_sha(value):
    if not isinstance(value, str) or not SHA.fullmatch(value):
        raise ValueError('Expected a complete source commit SHA')
    return value


def docker(*args, input_bytes=None, environment=None):
    # Publication credentials never enter arbitrary container subprocesses.
    env = dict(os.environ if environment is None else environment)
    env.pop('GH_TOKEN', None)
    env.pop('GITHUB_TOKEN', None)
    result = subprocess.run(['docker', *args], input=input_bytes,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, check=False, timeout=600)
    if result.returncode != 0:
        # Do not echo subprocess output that might contain registry credentials.
        raise RuntimeError(f'Docker {args[0]} failed (exit {result.returncode})')
    return result.stdout


def validate_image(image, version, source_sha):
    image_reference(version)
    checked_sha(source_sha)
    expected = {'org.opencontainers.image.source': SOURCE,
                'org.opencontainers.image.version': version,
                'org.opencontainers.image.revision': source_sha}
    if (image.get('Os') != 'linux' or image.get('Architecture') != 'amd64'
            or not DIGEST.fullmatch(image.get('Id', ''))
            or any(image.get('Config', {}).get('Labels', {}).get(k) != v
                   for k, v in expected.items())):
        raise ValueError('Container identity, source labels or platform mismatch')
    return image['Id']


def inspect_image(version, source_sha):
    images = json.loads(docker('image', 'inspect', image_reference(version)))
    if not isinstance(images, list) or len(images) != 1:
        raise ValueError('Expected exactly one built image')
    return validate_image(images[0], version, source_sha)


def archive_hash(path):
    if not path.is_file() or path.is_symlink():
        raise ValueError('Expected an ordinary container archive')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def archive_image_id(path, version, inspected_id):
    """Use the config hash on both Docker's classic and containerd image stores."""
    if not DIGEST.fullmatch(inspected_id):
        raise ValueError('Invalid loaded container identity')
    with tarfile.open(path, 'r:') as archive:
        members = archive.getmembers()
        if len({member.name for member in members}) != len(members):
            raise ValueError('Ambiguous container archive members')

        def read(name):
            try:
                member = archive.getmember(name)
            except KeyError:
                raise ValueError('Container archive is missing identity metadata') from None
            if not member.isfile() or member.size > 1024 * 1024:
                raise ValueError('Invalid container archive identity metadata')
            with archive.extractfile(member) as source:
                return source.read()

        manifest = json.loads(read('manifest.json'))
        if (not isinstance(manifest, list) or len(manifest) != 1
                or manifest[0].get('RepoTags') != [image_reference(version)]):
            raise ValueError('Container archive must contain only the expected image')
        config = manifest[0].get('Config', '')
        if not re.fullmatch(r'(blobs/sha256/[a-f0-9]{64}|[a-f0-9]{64}\.json)', config):
            raise ValueError('Unexpected container configuration path')
        config_id = 'sha256:' + hashlib.sha256(read(config)).hexdigest()
        if inspected_id != config_id:
            # Docker29+ containerd reports the manifest ID rather than config ID.
            raw = read('blobs/sha256/' + inspected_id[7:])
            if ('sha256:' + hashlib.sha256(raw).hexdigest() != inspected_id
                    or manifest_image_id(json.loads(raw)) != config_id):
                raise ValueError('Loaded container does not match archive configuration')
        return config_id


def checked_receipt(directory, version, source_sha):
    path = directory / 'container.json'
    if not path.is_file() or path.is_symlink():
        raise ValueError('Container receipt is missing or not an ordinary file')
    receipt = json.loads(path.read_text())
    expected = {'format': 1, 'version': version, 'sourceSha': checked_sha(source_sha),
                'image': image_reference(version), 'platform': 'linux/amd64',
                'archiveSha256': archive_hash(directory / 'wfform.tar')}
    if (not isinstance(receipt, dict)
            or any(receipt.get(k) != v for k, v in expected.items())
            or not DIGEST.fullmatch(receipt.get('imageId', ''))):
        raise ValueError('Container archive or receipt does not match this release')
    return receipt


def read_web(directory):
    value = json.loads((directory / 'release.json').read_text())
    image_reference(value.get('packageVersion'))
    if value.get('format') != 3 or not re.fullmatch(r'[a-f0-9]{64}', value.get('version', '')):
        raise ValueError('Expected a validated versioned public web build')
    return value


def prepare(directory, web, source_sha):
    manifest = read_web(web)
    checked_sha(source_sha)
    directory.mkdir(parents=True, exist_ok=True)
    # Build action inputs come from these checked values, never raw dispatch text.
    outputs = {'version': manifest['packageVersion'], 'source_sha': source_sha,
               'image': image_reference(manifest['packageVersion'])}
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as target:
            for key, value in outputs.items():
                target.write(f'{key}={value}\n')
    print(json.dumps(outputs))


def seal(directory, web, source_sha, smoke_image=False):
    manifest = read_web(web)
    version = manifest['packageVersion']
    docker('load', '--input', str(directory / 'wfform.tar'))
    loaded_id = inspect_image(version, source_sha)
    image_id = archive_image_id(directory / 'wfform.tar', version, loaded_id)
    if smoke_image:
        smoke(loaded_id, manifest)
    receipt = {'format': 1, 'version': version, 'sourceSha': source_sha,
               'image': image_reference(version), 'imageId': image_id,
               'platform': 'linux/amd64', 'webReleaseVersion': manifest['version'],
               'archiveSha256': archive_hash(directory / 'wfform.tar')}
    (directory / 'container.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Container integrity verified: {receipt["image"]} ({image_id})')


def smoke(image_id, manifest):
    # Only this fresh container is removed. No host mounts, exposed ports or network.
    container_id = docker('run', '--detach', '--rm', '--network', 'none',
                          '--read-only', '--tmpfs', '/tmp:rw,noexec,nosuid,size=16m',
                          '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                          image_id).decode().strip()
    if not re.fullmatch(r'[a-f0-9]{64}', container_id):
        raise ValueError('Invalid smoke container ID')
    try:
        for attempt in range(20):
            try:
                body = docker('exec', container_id, 'wget', '-qO-',
                              'http://127.0.0.1:8080/release.json')
                break
            except RuntimeError:
                if attempt == 19:
                    raise
                time.sleep(0.25)
        if json.loads(body) != manifest:
            raise ValueError('Container served another web release manifest')
        index = docker('exec', container_id, 'wget', '-qO-',
                       'http://127.0.0.1:8080/index.html')
        if hashlib.sha256(index).hexdigest() != manifest['assets']['index.html']['sha256']:
            raise ValueError('Container index does not match the verified web build')
        docker('exec', container_id, 'wget', '-qO-', 'http://127.0.0.1:8080/healthz')
    finally:
        docker('rm', '--force', container_id)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the Basic or registry Bearer token to another location.
        return None


def open_request(request):
    return urllib.request.build_opener(NoRedirect()).open(request, timeout=30)


def response_json(response):
    raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError('Registry JSON exceeded limit')
    return json.loads(raw)


def registry_token(actor, credential):
    basic = base64.b64encode(f'{actor}:{credential}'.encode()).decode()
    query = urllib.parse.urlencode({'service': 'ghcr.io',
                                    'scope': f'repository:{REPOSITORY}:pull,push'})
    request = urllib.request.Request('https://ghcr.io/token?' + query,
                                     headers={'Authorization': 'Basic ' + basic})
    try:
        with open_request(request) as response:
            value = response_json(response)
    except urllib.error.HTTPError as error:
        code = error.code
        error.close()
        raise RuntimeError(f'Registry authentication failed: HTTP {code}') from None
    token = value.get('token')
    if not isinstance(token, str) or not token:
        raise ValueError('Registry did not return a usable access token')
    return token


def manifest_image_id(manifest):
    if (not isinstance(manifest, dict) or manifest.get('schemaVersion') != 2
            or manifest.get('mediaType') not in MANIFEST_TYPES
            or not DIGEST.fullmatch(manifest.get('config', {}).get('digest', ''))):
        raise ValueError('Unsupported registry manifest or invalid image digest')
    return manifest['config']['digest']


def registry_manifest(version, token):
    image_reference(version)
    request = urllib.request.Request(
        f'https://ghcr.io/v2/{REPOSITORY}/manifests/{version}',
        headers={'Authorization': 'Bearer ' + token, 'Accept': ', '.join(MANIFEST_TYPES)})
    try:
        with open_request(request) as response:
            return manifest_image_id(response_json(response))
    except urllib.error.HTTPError as error:
        code = error.code
        error.close()
        if code == 404:
            return None
        raise RuntimeError(f'Registry lookup failed: HTTP {code}') from None


def publish_immutable(image_id, lookup, push):
    existing = lookup()
    if existing is not None:
        if existing != image_id:
            raise ValueError('Container version already exists with different content; refusing overwrite')
        return 'unchanged'
    # Workflow concurrency serializes this repository's publishers. Registry tags
    # have no compare-and-swap API; external writers must follow the same policy.
    push()
    if lookup() != image_id:
        raise ValueError('Published container verification failed; do not retry blindly')
    return 'published'


def publication_request(env):
    version = env.get('WFFORM_RELEASE_VERSION', '')
    source_sha = checked_sha(env.get('WFFORM_RELEASE_SHA', ''))
    image_reference(version)
    if (env.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
            or env.get('GITHUB_REF') != 'refs/heads/main'
            or env.get('GITHUB_REPOSITORY') != REPOSITORY
            or env.get('GITHUB_SHA') != source_sha
            or not re.fullmatch(r'[1-9][0-9]*', env.get('WFFORM_RELEASE_PR', ''))):
        raise ValueError('Container publication requires the approved main release dispatch')
    return version, source_sha


def publish(directory):
    version, source_sha = publication_request(os.environ)
    receipt = checked_receipt(directory, version, source_sha)
    docker('load', '--input', str(directory / 'wfform.tar'))
    loaded_id = inspect_image(version, source_sha)
    if archive_image_id(directory / 'wfform.tar', version, loaded_id) != receipt['imageId']:
        raise ValueError('Loaded image does not match the same-run receipt')
    actor = os.environ.get('GITHUB_ACTOR', '')
    credential = os.environ.get('GH_TOKEN', '')
    if not actor or not credential:
        raise ValueError('Missing workflow actor or registry credential')
    token = registry_token(actor, credential)
    lookup = lambda: registry_manifest(version, token)
    # Docker stores login material only in this private ephemeral directory.
    # It is outside artifact/cache paths and removed on success or failure.
    temporary_root = Path(os.environ.get('RUNNER_TEMP', '.local'))
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='wfform-registry-', dir=temporary_root) as config:
        env = dict(os.environ, DOCKER_CONFIG=config)
        def push():
            docker('login', 'ghcr.io', '--username', actor, '--password-stdin',
                   input_bytes=credential.encode(), environment=env)
            docker('push', image_reference(version), environment=env)
        status = publish_immutable(receipt['imageId'], lookup, push)
    print(f'Container {status}: {image_reference(version)} ({receipt["imageId"]})')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f'## 📦 Container {status}\n\n`{image_reference(version)}` '
                          f'· Linux amd64 · image `{receipt["imageId"]}`.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'seal', 'publish'))
    parser.add_argument('--directory', type=Path, default=Path('build/container'))
    parser.add_argument('--web', type=Path, default=Path('build/publish-web'))
    parser.add_argument('--source-sha', default=os.environ.get('WFFORM_CONTAINER_SHA', ''))
    parser.add_argument('--smoke', action='store_true', help='Run the PR-only container HTTP smoke check')
    args = parser.parse_args()
    if args.command == 'publish':
        publish(args.directory)
    elif args.command == 'prepare':
        prepare(args.directory, args.web, args.source_sha)
    else:
        seal(args.directory, args.web, args.source_sha, smoke_image=args.smoke)


if __name__ == '__main__':
    main()
