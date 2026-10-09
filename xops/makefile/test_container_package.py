"""Container packaging and immutable GHCR publication, without credentials."""
import hashlib
import io
import importlib.util
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch
import urllib.error

SPEC = importlib.util.spec_from_file_location(
    'container_package', Path(__file__).parents[1] / 'agent/container_package.py')
container = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(container)
SHA = 'a' * 40
DIGEST = 'sha256:' + 'b' * 64
OTHER = 'sha256:' + 'c' * 64


class ContainerIdentityTest(unittest.TestCase):
    def test_legacy_and_containerd_ids_resolve_to_the_same_config_digest(self):
        config = b'{"os":"linux","architecture":"amd64"}'
        config_id = 'sha256:' + hashlib.sha256(config).hexdigest()
        manifest = json.dumps({'schemaVersion': 2,
            'mediaType': 'application/vnd.oci.image.manifest.v1+json',
            'config': {'digest': config_id}}).encode()
        manifest_id = 'sha256:' + hashlib.sha256(manifest).hexdigest()
        files = {'manifest.json': json.dumps([{'Config': 'blobs/sha256/' + config_id[7:],
                 'RepoTags': [container.image_reference('1.2.3')]}]).encode(),
                 'blobs/sha256/' + config_id[7:]: config,
                 'blobs/sha256/' + manifest_id[7:]: manifest}
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'image.tar'
            with tarfile.open(archive, 'w') as tar:
                for name, data in files.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
            for inspected_id in (config_id, manifest_id):
                self.assertEqual(container.archive_image_id(archive, '1.2.3', inspected_id), config_id)
            with self.assertRaises(ValueError):
                container.archive_image_id(archive, '1.2.3', OTHER)

    def test_only_plain_semver_for_fixed_repository(self):
        self.assertEqual(container.image_reference('1.2.3'),
                         'ghcr.io/consciontologic/wfform:1.2.3')
        for version in ('v1.2.3', 'latest', '1.2', '01.2.3', '1.2.3-rc.1',
                        '1.2.3+build', '1.2.3\n', '../1.2.3', '1.2.3;pwd'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                container.image_reference(version)

    def test_inspection_binds_image_to_version_source_and_platform(self):
        image = {'Id': DIGEST, 'Os': 'linux', 'Architecture': 'amd64',
                 'Config': {'Labels': {
                     'org.opencontainers.image.source': container.SOURCE,
                     'org.opencontainers.image.version': '1.2.3',
                     'org.opencontainers.image.revision': SHA}}}
        self.assertEqual(container.validate_image(image, '1.2.3', SHA), DIGEST)
        for key, value in [('Id', 'bad'), ('Os', 'windows'), ('Architecture', 'arm64')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                container.validate_image(dict(image, **{key: value}), '1.2.3', SHA)
        for label in image['Config']['Labels']:
            changed = json.loads(json.dumps(image))
            changed['Config']['Labels'][label] = 'wrong'
            with self.subTest(label=label), self.assertRaises(ValueError):
                container.validate_image(changed, '1.2.3', SHA)

    def test_manifest_index_and_invalid_config_are_not_accepted(self):
        valid = {'schemaVersion': 2,
                 'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                 'config': {'digest': DIGEST}}
        self.assertEqual(container.manifest_image_id(valid), DIGEST)
        for value in ({}, dict(valid, schemaVersion=1),
                      dict(valid, mediaType='application/vnd.oci.image.index.v1+json'),
                      dict(valid, config={'digest': 'bad'})):
            with self.subTest(value=value), self.assertRaises(ValueError):
                container.manifest_image_id(value)

    def test_archive_checksum_and_metadata_must_match_request(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'wfform.tar'
            archive.write_bytes(b'container')
            receipt = {'format': 1, 'version': '1.2.3', 'sourceSha': SHA,
                       'image': container.image_reference('1.2.3'), 'imageId': DIGEST,
                       'platform': 'linux/amd64',
                       'archiveSha256': hashlib.sha256(b'container').hexdigest()}
            (root / 'container.json').write_text(json.dumps(receipt))
            self.assertEqual(container.checked_receipt(root, '1.2.3', SHA), receipt)
            with self.assertRaises(ValueError):
                container.checked_receipt(root, '1.2.4', SHA)
            archive.write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                container.checked_receipt(root, '1.2.3', SHA)


class ContainerPublicationTest(unittest.TestCase):
    def test_missing_tag_is_pushed_once_and_verified(self):
        lookup = iter([None, DIGEST])
        pushes = []
        self.assertEqual(container.publish_immutable(DIGEST, lambda: next(lookup),
                         lambda: pushes.append('push')), 'published')
        self.assertEqual(pushes, ['push'])

    def test_identical_tag_is_read_only(self):
        self.assertEqual(container.publish_immutable(DIGEST, lambda: DIGEST,
                         lambda: self.fail('must not push')), 'unchanged')

    def test_conflicting_tag_is_never_replaced(self):
        with self.assertRaisesRegex(ValueError, 'already exists'):
            container.publish_immutable(DIGEST, lambda: OTHER,
                                        lambda: self.fail('must not push'))

    def test_failed_lookup_is_not_treated_as_absent(self):
        def failed():
            raise RuntimeError('registry unavailable')
        with self.assertRaises(RuntimeError):
            container.publish_immutable(DIGEST, failed, lambda: self.fail('must not push'))

    def test_uncertain_push_is_not_retried(self):
        pushes = []
        def failed():
            pushes.append('push')
            raise RuntimeError('connection lost')
        with self.assertRaises(RuntimeError):
            container.publish_immutable(DIGEST, lambda: None, failed)
        self.assertEqual(pushes, ['push'])

    def test_remote_must_match_after_push(self):
        lookup = iter([None, OTHER])
        with self.assertRaisesRegex(ValueError, 'verification'):
            container.publish_immutable(DIGEST, lambda: next(lookup), lambda: None)

    def test_only_manifest_404_means_absent(self):
        for code in (401, 403, 404, 429, 500):
            error = urllib.error.HTTPError('https://ghcr.io/v2/x/manifests/1.2.3',
                                           code, 'denied', {}, None)
            with self.subTest(code=code), patch.object(container, 'open_request', side_effect=error):
                if code == 404:
                    self.assertIsNone(container.registry_manifest('1.2.3', 'secret'))
                else:
                    with self.assertRaisesRegex(RuntimeError, f'HTTP {code}'):
                        container.registry_manifest('1.2.3', 'secret')

    def test_registry_token_failure_never_means_absent(self):
        error = urllib.error.HTTPError('https://ghcr.io/token', 404, 'missing', {}, None)
        with patch.object(container, 'open_request', side_effect=error):
            with self.assertRaisesRegex(RuntimeError, 'HTTP 404'):
                container.registry_token('actor', 'secret')

    def test_read_only_or_non_main_dispatch_cannot_publish(self):
        valid = {'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main',
                 'GITHUB_REPOSITORY': 'consciontologic/wfform', 'GITHUB_SHA': SHA,
                 'WFFORM_RELEASE_SHA': SHA, 'WFFORM_RELEASE_VERSION': '1.2.3',
                 'WFFORM_RELEASE_PR': '7'}
        self.assertEqual(container.publication_request(valid), ('1.2.3', SHA))
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REF', 'refs/heads/develop'),
                           ('GITHUB_REPOSITORY', 'someone/wfform'), ('WFFORM_RELEASE_SHA', 'b'*40),
                           ('WFFORM_RELEASE_VERSION', ''), ('WFFORM_RELEASE_PR', '')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                container.publication_request(dict(valid, **{key: value}))


if __name__ == '__main__':
    unittest.main()
