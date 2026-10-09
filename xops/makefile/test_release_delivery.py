"""Release authorization and resumable immutable publication, entirely offline."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'release_delivery', Path(__file__).parents[1] / 'agent/release_delivery.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
REPO = 'consciontologic/wfform'
BASE = f'/repos/{REPO}'
SHA = 'a' * 40
HEAD = 'b' * 40


class FakeAPI:
    def __init__(self):
        self.writes = []
        self.assets = []
        self.tag = None
        self.release = None
        self.main = SHA
        self.permission = 'write'
        self.environment = {'id': 7, 'name': 'production', 'can_admins_bypass': False,
                            'deployment_branch_policy': {'custom_branch_policies': True, 'protected_branches': False},
                            'protection_rules': [{'type': 'required_reviewers', 'reviewers': [
                                {'type': 'User', 'reviewer': {'id': 339074048, 'login': 'consciontologic', 'type': 'User'}}]}]}
        self.policies = [{'name': 'main', 'type': 'branch'}]
        self.run = {'head_sha': SHA, 'head_branch': 'main', 'event': 'workflow_dispatch',
                    'path': '.github/workflows/companion.yml',
                    'repository': {'full_name': REPO}, 'head_repository': {'full_name': REPO}}
        self.approvals = [{'state': 'approved', 'environments': [{'id': 7, 'name': 'production'}],
                           'user': {'id': 339074048, 'login': 'consciontologic', 'type': 'User'}}]
        self.pr = {'number': 3, 'merged': True, 'draft': False,
                   'merged_at': '2026-10-09T15:00:00Z', 'merge_commit_sha': SHA,
                   'user': {'login': 'github-actions[bot]', 'type': 'Bot'},
                   'base': {'ref': 'main', 'repo': {'full_name': REPO}},
                   'head': {'ref': 'hotfix/release-1.0.0', 'sha': HEAD,
                            'repo': {'full_name': REPO}}}
        self.reviews = [{'id': 10, 'state': 'APPROVED', 'commit_id': HEAD,
                         'submitted_at': '2026-10-09T14:00:00Z',
                         'user': {'login': 'maintainer', 'type': 'User'}}]
        self.checks = [{'id': i, 'name': name, 'head_sha': HEAD,
                        'app': {'id': 15368}, 'status': 'completed',
                        'conclusion': 'success'} for i, name in enumerate(
                            ['Web checks', 'Security checks', 'Linux package', 'Windows package'])]
        self.check_runs = {}
        for index, check in enumerate(self.checks):
            run_id = 100 + index
            check['details_url'] = f'https://github.com/{REPO}/actions/runs/{run_id}/job/{index + 1}'
            self.check_runs[str(run_id)] = {'head_sha': HEAD, 'event': 'pull_request',
                'path': ['.github/workflows/web.yml', '.github/workflows/security.yml',
                         '.github/workflows/companion.yml', '.github/workflows/companion.yml'][index],
                'repository': {'full_name': REPO}, 'head_repository': {'full_name': REPO},
                'status': 'completed', 'conclusion': 'success',
                'pull_requests': [{'number': 3, 'head': {'sha': HEAD}, 'base': {'ref': 'main'}}]}
        self.trees = {SHA: 'd' * 40, HEAD: 'd' * 40}

    def get(self, path):
        clean = path.split('?')[0]
        if clean.startswith(BASE + '/git/commits/'):
            sha = clean.rsplit('/', 1)[1]
            return {'sha': sha, 'tree': {'sha': self.trees[sha]}}
        if clean == BASE + '/environments/production': return copy.deepcopy(self.environment)
        if clean == BASE + '/environments/production/deployment-branch-policies':
            return {'branch_policies': copy.deepcopy(self.policies)}
        if clean == BASE + '/actions/runs/44': return copy.deepcopy(self.run)
        if clean == BASE + '/actions/runs/44/approvals': return copy.deepcopy(self.approvals)
        if clean.startswith(BASE + '/actions/runs/') and clean.rsplit('/', 1)[-1] in self.check_runs:
            return copy.deepcopy(self.check_runs[clean.rsplit('/', 1)[-1]])
        if clean == BASE + '/pulls/3': return copy.deepcopy(self.pr)
        if clean == BASE + '/git/ref/heads/main': return {'object': {'sha': self.main}}
        if clean == BASE + '/pulls/3/reviews': return copy.deepcopy(self.reviews)
        if clean == BASE + '/commits/' + HEAD + '/check-runs':
            return {'check_runs': copy.deepcopy(self.checks)}
        if clean == BASE + '/collaborators/maintainer/permission':
            return {'permission': self.permission}
        if clean == BASE + '/releases/8/assets': return copy.deepcopy(self.assets)
        if clean == BASE + '/releases': return [copy.deepcopy(self.release)] if self.release else []
        if clean == BASE + '/releases/tags/1.0.0':
            # GitHub documents this endpoint as published releases only.
            return copy.deepcopy(self.release) if self.release and not self.release['draft'] else None
        if clean == BASE + '/git/ref/tags/1.0.0': return copy.deepcopy(self.tag)
        raise AssertionError(path)

    def request(self, method, path, body):
        self.writes.append((method, path, body))
        if path == BASE + '/git/refs':
            self.tag = {'object': {'type': 'commit', 'sha': body['sha']}}
            return self.tag
        if path == BASE + '/releases':
            self.release = dict(body, id=8)
            return copy.deepcopy(self.release)
        if path == BASE + '/releases/8':
            self.release.update(body)
            return copy.deepcopy(self.release)
        raise AssertionError(path)

    def upload(self, repo, release_id, path):
        data = path.read_bytes()
        entry = {'id': len(self.assets) + 1, 'name': path.name, 'state': 'uploaded',
                 'size': len(data), 'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}
        self.writes.append(('upload', path.name, None))
        self.assets.append(entry)
        return entry



class PromotionAPI(FakeAPI):
    def __init__(self):
        super().__init__()
        self.pr['head']['ref'] = 'develop'
        self.source = copy.deepcopy(self.pr)
        self.source.update(number=2, merge_commit_sha=HEAD)
        self.source['head'] = {'ref': 'feature/release', 'sha': 'c' * 40, 'repo': {'full_name': REPO}}
        self.source['base']['ref'] = 'develop'
        self.trees['c' * 40] = 'd' * 40
        for check in self.checks:
            check['head_sha'] = 'c' * 40
        for run in self.check_runs.values():
            run.update(head_sha='c' * 40, pull_requests=[{'number': 2, 'head': {'sha': 'c' * 40}, 'base': {'ref': 'develop'}}])

    def get(self, path):
        if path.startswith(BASE + '/pulls?'):
            return [copy.deepcopy(self.source)]
        if path == BASE + '/pulls/2':
            return copy.deepcopy(self.source)
        if path.startswith(BASE + '/commits/' + 'c' * 40 + '/check-runs'):
            return {'check_runs': copy.deepcopy(self.checks)}
        if path.startswith(BASE + '/commits/' + HEAD + '/check-runs'):
            # Promotion jobs intentionally skip; they are not quality evidence.
            return {'check_runs': [dict(row, head_sha=HEAD, conclusion='skipped') for row in self.checks]}
        return super().get(path)


class PromotionEvidenceTest(unittest.TestCase):
    def test_skipped_promotion_reuses_exact_tested_develop_tree(self):
        api = PromotionAPI()
        self.assertEqual(release.authorize(api, REPO, 3, SHA, '1.0.0')['number'], 3)
        self.assertEqual(api.writes, [])

    def test_prefixed_release_branches_are_authorized_only_for_matching_version(self):
        for branch in ('codex/release/1.0.0', 'claude/release/1.0.0'):
            api = PromotionAPI()
            api.pr['head']['ref'] = branch
            with self.subTest(branch=branch):
                self.assertEqual(release.authorize(api, REPO, 3, SHA, '1.0.0')['number'], 3)
                with self.assertRaisesRegex(release.DeliveryError, 'version'):
                    release.authorize(api, REPO, 3, SHA, '1.0.1')

    def test_later_skipped_promotion_checks_do_not_mask_prior_develop_quality(self):
        api = PromotionAPI()
        row = dict(api.checks[0], id=900, conclusion='skipped',
                   details_url=f'https://github.com/{REPO}/actions/runs/900/job/900')
        api.checks.append(row)
        api.check_runs['900'] = dict(api.check_runs['100'],
            pull_requests=[{'number': 3, 'head': {'sha': 'c' * 40}, 'base': {'ref': 'main'}}])
        release.authorize(api, REPO, 3, SHA, '1.0.0')
        # A newer failed run for the actual source PR must still invalidate it.
        api.checks.append(dict(api.checks[0], id=901, conclusion='failure'))
        with self.assertRaises(release.DeliveryError): release.authorize(api, REPO, 3, SHA, '1.0.0')

    def test_main_merge_develop_merge_and_source_head_must_have_identical_trees(self):
        for sha in [SHA, HEAD, 'c' * 40]:
            api = PromotionAPI(); api.trees[sha] = 'e' * 40
            with self.subTest(sha=sha), self.assertRaises(release.DeliveryError):
                release.authorize(api, REPO, 3, SHA, '1.0.0')
        api = PromotionAPI(); api.source['merged'] = False
        with self.assertRaises(release.DeliveryError):
            release.authorize(api, REPO, 3, SHA, '1.0.0')

    def test_synthetic_candidate_merge_is_checked_before_merge(self):
        api = PromotionAPI()
        api.pr.update(merged=False, state='open', mergeable=True)
        self.assertEqual(release.promotion_evidence(api, api.pr)['source_pr'], 2)
        api.trees[SHA] = 'e' * 40
        with self.assertRaisesRegex(release.DeliveryError, 'tree'):
            release.promotion_evidence(api, api.pr)
        api.trees[SHA] = 'd' * 40; api.pr['mergeable'] = None
        with self.assertRaises(release.DeliveryError): release.promotion_evidence(api, api.pr)

    def test_prior_evidence_must_be_real_develop_pr_quality_not_push_or_dispatch(self):
        for mutation in [dict(event='push'), dict(event='workflow_dispatch'),
                         dict(path='.github/workflows/delivery.yml'), dict(pull_requests=[]),
                         dict(pull_requests=[{'number': 2, 'head': {'sha': 'c' * 40}, 'base': {'ref': 'main'}}])]:
            api = PromotionAPI(); api.check_runs['100'].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(release.DeliveryError):
                release.authorize(api, REPO, 3, SHA, '1.0.0')
        for mutation in [dict(conclusion='skipped'), dict(conclusion='failure'), dict(head_sha=HEAD), dict(app={'id': 9})]:
            api = PromotionAPI(); api.checks[0].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(release.DeliveryError):
                release.authorize(api, REPO, 3, SHA, '1.0.0')

    def test_merged_fork_into_develop_can_supply_verified_quality(self):
        api = PromotionAPI(); api.source['head']['repo']['full_name'] = 'contributor/wfform'
        for run in api.check_runs.values(): run['head_repository']['full_name'] = 'contributor/wfform'
        release.authorize(api, REPO, 3, SHA, '1.0.0')
        api.check_runs['100']['head_repository']['full_name'] = 'unrelated/wfform'
        with self.assertRaises(release.DeliveryError): release.authorize(api, REPO, 3, SHA, '1.0.0')

    def test_direct_hotfix_needs_own_quality_and_no_untested_merge_content(self):
        api = FakeAPI(); api.trees[SHA] = 'e' * 40
        with self.assertRaises(release.DeliveryError): release.authorize(api, REPO, 3, SHA, '1.0.0')
        api = FakeAPI(); api.check_runs['100']['event'] = 'workflow_dispatch'
        with self.assertRaises(release.DeliveryError): release.authorize(api, REPO, 3, SHA, '1.0.0')

class ReleaseAuthorizationTest(unittest.TestCase):
    def setUp(self): self.api = FakeAPI()
    def authorize(self):
        return release.authorize(self.api, REPO, 3, SHA, '1.0.0')

    def test_merged_current_head_with_green_checks_is_accepted(self):
        self.assertEqual(self.authorize()['number'], 3)
        self.assertEqual(self.api.writes, [])

    def test_unmerged_wrong_main_wrong_branch_and_wrong_sha_are_rejected(self):
        for field, value in [('merged', False), ('merge_commit_sha', 'c' * 40), ('draft', True)]:
            with self.subTest(field=field):
                self.api = FakeAPI(); self.api.pr[field] = value
                with self.assertRaises(release.DeliveryError): self.authorize()
        self.api = FakeAPI(); self.api.main = 'c' * 40
        with self.assertRaisesRegex(release.DeliveryError, 'main'): self.authorize()
        self.api = FakeAPI(); self.api.pr['head']['ref'] = 'feature/bypass'
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_pr_approval_is_not_a_second_gate(self):
        self.api.reviews = []
        self.authorize()
        self.assertEqual(self.api.writes, [])

    def test_hotfix_path_may_contain_release_without_becoming_version_branch(self):
        self.api.pr['head']['ref'] = 'hotfix/release/startup'
        self.authorize()

    def test_copilot_hotfix_can_use_deployment_approval(self):
        self.api.pr['user'] = {'login': 'Copilot', 'type': 'Bot'}
        self.api.pr['head']['ref'] = 'copilot/repair'
        self.api.pr['labels'] = [{'name': 'work:hotfix'}]
        self.authorize()
        self.api.pr['labels'] = []
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_environment_must_require_human_and_main_only(self):
        for change in [lambda e: e.update(protection_rules=[]),
                       lambda e: e['protection_rules'][0]['reviewers'][0]['reviewer'].update(type='Bot')]:
            self.api = FakeAPI(); change(self.api.environment)
            with self.assertRaises(release.DeliveryError): self.authorize()
        self.api = FakeAPI(); self.api.policies.append({'name': '*', 'type': 'branch'})
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_production_approval_requires_this_run_sha_and_eligible_human(self):
        release.deployment_approval(self.api, REPO, SHA, 44)
        for change in [lambda a: a.update(state='rejected'),
                       lambda a: a['user'].update(type='Bot'),
                       lambda a: a['user'].update(id=13),
                       lambda a: a['environments'][0].update(id=8)]:
            self.api = FakeAPI(); change(self.api.approvals[0])
            with self.assertRaises(release.DeliveryError):
                release.deployment_approval(self.api, REPO, SHA, 44)
        self.api = FakeAPI(); self.api.run['head_sha'] = 'c' * 40
        with self.assertRaises(release.DeliveryError):
            release.deployment_approval(self.api, REPO, SHA, 44)

    def test_required_checks_reject_wrong_producer_sha_and_latest_failure(self):
        for patch in [{'app': {'id': 9}}, {'conclusion': 'skipped'},
                      {'head_sha': 'c' * 40}, {'status': 'in_progress'}]:
            self.api = FakeAPI(); self.api.checks[0].update(patch)
            with self.subTest(patch=patch), self.assertRaises(release.DeliveryError): self.authorize()
        self.api = FakeAPI()
        self.api.checks.append(dict(self.api.checks[0], id=100, conclusion='failure'))
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_checks_from_wrong_workflow_fork_event_or_revision_are_rejected(self):
        for mutation in [dict(path='.github/workflows/spoof.yml'),
                         dict(head_sha='c' * 40), dict(event='pull_request_target'),
                         dict(repository={'full_name': 'outsider/wfform'}),
                         dict(head_repository={'full_name': 'outsider/wfform'}),
                         dict(conclusion='failure')]:
            self.api = FakeAPI(); self.api.check_runs['100'].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(release.DeliveryError):
                self.authorize()
        self.api = FakeAPI()
        self.api.checks[0]['details_url'] = 'https://attacker.invalid/actions/runs/100/job/1'
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_reviewer_configuration_cannot_drift_to_another_human(self):
        self.api.environment['protection_rules'][0]['reviewers'][0]['reviewer'].update(
            id=13, login='another-human')
        with self.assertRaises(release.DeliveryError): self.authorize()

    def test_plain_version_and_changelog_must_match_checked_out_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('version: 1.0.0\n')
            (root / 'CHANGELOG.md').write_text('## [1.0.0]\n\nReleased tools.\n')
            release.authorize(self.api, REPO, 3, SHA, '1.0.0', root)
            (root / 'pubspec.yaml').write_text('version: 1.0.1\n')
            with self.assertRaises(release.DeliveryError):
                release.authorize(self.api, REPO, 3, SHA, '1.0.0', root)
        for bad in ['v1.0.0', '01.0.0', '1.0.0+5', '../main']:
            with self.assertRaises(release.DeliveryError):
                release.authorize(self.api, REPO, 3, SHA, bad)


class ReleasePublicationTest(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.files = []
        for name in ['linux.zip', 'windows.zip']:
            path = Path(self.scratch.name) / name
            path.write_bytes(('verified ' + name).encode())
            self.files.append(path)

    def publish(self):
        return release.publish(self.api, REPO, 3, SHA, '1.0.0', 'Release notes', self.files, run_id=44)

    def test_complete_release_and_identical_rerun_never_overwrite(self):
        self.publish()
        self.assertFalse(self.api.release['draft'])
        self.assertEqual(self.api.tag['object']['sha'], SHA)
        writes = len(self.api.writes)
        self.publish()
        self.assertEqual(len(self.api.writes), writes)
        self.assertEqual(sum(w[0] == 'upload' for w in self.api.writes), 2)

    def test_missing_assets_resume_without_duplicate_release(self):
        upload = self.api.upload
        def interrupt(repo, release_id, path):
            if path == self.files[1]: raise release.DeliveryError('Interrupted upload')
            return upload(repo, release_id, path)
        self.api.upload = interrupt
        with self.assertRaisesRegex(release.DeliveryError, 'Interrupted'): self.publish()
        self.assertTrue(self.api.release['draft'])
        self.api.upload = upload
        self.publish()
        self.assertFalse(self.api.release['draft'])
        self.assertEqual(sum(w[1] == BASE + '/releases' for w in self.api.writes), 1)
        self.assertEqual(sum(w[0] == 'upload' for w in self.api.writes), 2)

    def test_conflicting_tag_cannot_be_changed(self):
        self.api.tag = {'object': {'type': 'commit', 'sha': 'c' * 40}}
        with self.assertRaisesRegex(release.DeliveryError, 'tag'): self.publish()
        self.assertEqual(self.api.writes, [])

    def test_different_asset_bytes_and_foreign_release_are_rejected(self):
        self.publish()
        self.files[0].write_bytes(b'different build')
        writes = len(self.api.writes)
        with self.assertRaisesRegex(release.DeliveryError, 'asset'): self.publish()
        self.assertEqual(len(self.api.writes), writes)
        self.api.release['body'] = 'Someone else created this release'
        with self.assertRaisesRegex(release.DeliveryError, 'release'): self.publish()

    def test_main_advances_during_upload_leaves_draft_unpublished(self):
        upload = self.api.upload
        def advance(repo, release_id, path):
            result = upload(repo, release_id, path)
            self.api.main = 'c' * 40
            return result
        self.api.upload = advance
        with self.assertRaisesRegex(release.DeliveryError, 'main'): self.publish()
        self.assertTrue(self.api.release['draft'])

    def test_no_approval_means_no_tag_release_or_upload(self):
        self.api.approvals = []
        self.api.environment['can_admins_bypass'] = True
        with self.assertRaises(release.DeliveryError): self.publish()
        self.assertEqual(self.api.writes, [])


class ReleaseAssetsTest(unittest.TestCase):
    def test_package_identity_checks_all_three_platforms_before_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder, stem, extension in [
                ('companion', 'wfformcomp-1.0.0-linux-x64', 'tar.gz'),
                ('companion', 'wfformcomp-1.0.0-windows-x64', 'zip'),
                ('release', 'wfform-1.0.0-web', 'tar.gz'),
            ]:
                archive = root / 'build' / folder / (stem + '.' + extension)
                archive.parent.mkdir(parents=True, exist_ok=True)
                archive.write_bytes(b'checked package bytes')
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                archive.with_name(archive.name + '.sha256').write_text(digest + '  ' + archive.name + '\n')
                archive.with_name(stem + '.json').write_text(json.dumps({
                    'version': '1.0.0', 'archive': archive.name, 'sha256': digest}))
            self.assertEqual(len(release.checked_assets(root, '1.0.0')), 9)
            archive.write_bytes(b'corruption after build')
            with self.assertRaisesRegex(release.DeliveryError, 'checksum'):
                release.checked_assets(root, '1.0.0')

    def test_api_redirects_never_forward_credentials_or_retry(self):
        from urllib.error import HTTPError
        class Opener:
            calls = 0
            def open(self, request, timeout):
                self.calls += 1
                raise HTTPError(request.full_url, 302, 'redirect', {}, None)
        api = release.API('test-only-token')
        api.opener = Opener()
        with self.assertRaisesRegex(release.DeliveryError, '302'):
            api.request('POST', BASE + '/releases', {'draft': True})
        self.assertEqual(api.opener.calls, 1)
        self.assertIsNone(release.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.org'))


if __name__ == '__main__': unittest.main()
