"""Offline delivery safety contracts; no credentials or live GitHub mutations."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'xops/agent'))
SPEC = importlib.util.spec_from_file_location('delivery', ROOT / 'xops/agent/delivery.py')
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)
REPO = 'consciontologic/wfform'
SHA = 'a' * 40


def pr(head='feature/tools', base='develop', **changes):
    result = {'number': 7, 'node_id': 'PR_7', 'state': 'open', 'draft': False,
              'head': {'ref': head, 'sha': SHA, 'repo': {'full_name': REPO}},
              'base': {'ref': base, 'repo': {'full_name': REPO}},
              'labels': [], 'body': '', 'merged': False, 'user': {'login': 'author'}}
    result.update(changes)
    return result


def policy():
    return json.loads((ROOT / '.github/delivery-policy.json').read_text())


def evidence():
    rows, runs = [], {}
    for index, (name, paths) in enumerate(policy()['checks'].items(), 1):
        rows.append({'id': index, 'name': name, 'head_sha': SHA,
                     'status': 'completed', 'conclusion': 'success',
                     'app': {'id': 15368},
                     'details_url': f'https://github.com/{REPO}/actions/runs/{index}/job/{index}'})
        runs[index] = {'head_sha': SHA, 'event': 'pull_request', 'path': paths[0],
                       'repository': {'full_name': REPO}, 'head_repository': {'full_name': REPO},
                       'status': 'completed', 'conclusion': 'success'}
    return rows, runs


class FakeAPI:
    def __init__(self):
        self.comments = []
        self.writes = []
        self.reads = {}
        self.tasks = []
        self.fail_post = False

    def get(self, path):
        if '/comments?' in path:
            return copy.deepcopy(self.comments)
        return copy.deepcopy(self.reads[path])

    def paged(self, path, key=None, limit=100):
        return self.get(path)

    def request(self, method, path, body=None):
        self.writes.append((method, path, body))
        if method == 'POST' and path.endswith('/comments'):
            comment = {'id': len(self.comments) + 1, 'body': body['body'],
                       'user': {'login': 'github-actions[bot]', 'type': 'Bot'}}
            self.comments.append(comment)
            return copy.deepcopy(comment)
        if method == 'PATCH' and '/issues/comments/' in path:
            number = int(path.rsplit('/', 1)[1])
            self.comments[number - 1]['body'] = body['body']
            return self.comments[number - 1]
        if self.fail_post:
            raise delivery.DeliveryError('Unknown POST outcome')
        return {'id': 'task-1', 'state': 'queued', 'html_url': f'https://github.com/{REPO}/tasks/task-1'}


class DeliverySafetyTest(unittest.TestCase):
    def test_expected_gitflow_lanes(self):
        cases = [('feature/tools', 'develop', 'feature'),
                 ('codex/bugfix/x', 'develop', 'bugfix'),
                 ('hotfix/startup', 'main', 'hotfix'),
                 ('release/1.0.0', 'main', 'release'),
                 ('copilot/prep', 'release/1.0.0', 'preparation')]
        for head, base, lane in cases:
            with self.subTest(head=head):
                self.assertEqual(delivery.pr_lane(pr(head, base), REPO), lane)

    def test_refuses_draft_fork_wrong_lane_and_protected_head(self):
        bad = [pr(draft=True), pr('feature/x', 'main'), pr('release/v1.0.0', 'main'),
               pr('main', 'develop'), pr('copilot/x', 'main'), pr(state='closed')]
        fork = pr()
        fork['head']['repo']['full_name'] = 'elsewhere/wfform'
        bad.append(fork)
        for pull in bad:
            with self.subTest(pull=pull), self.assertRaises(delivery.DeliveryError):
                delivery.pr_lane(pull, REPO)

    def test_copilot_lane_requires_explicit_label(self):
        pull = pr('copilot/x', 'develop')
        with self.assertRaises(delivery.DeliveryError):
            delivery.pr_lane(pull, REPO)
        pull['labels'] = [{'name': 'work:feature'}]
        self.assertEqual(delivery.pr_lane(pull, REPO), 'feature')
        pull['labels'].append({'name': 'work:hotfix'})
        with self.assertRaises(delivery.DeliveryError):
            delivery.pr_lane(pull, REPO)

    def test_success_requires_each_check_and_trusted_workflow(self):
        checks, runs = evidence()
        delivery.check_evidence(pr(), checks, runs.__getitem__, policy())
        for mutation in ['missing', 'failed', 'producer', 'stale', 'path', 'fork', 'run_sha']:
            mutated, run_copy = copy.deepcopy(checks), copy.deepcopy(runs)
            if mutation == 'missing':
                mutated.pop()
            elif mutation == 'failed':
                mutated[0]['conclusion'] = 'failure'
            elif mutation == 'producer':
                mutated[0]['app']['id'] = 666
            elif mutation == 'stale':
                mutated[0]['head_sha'] = 'b' * 40
            elif mutation == 'path':
                run_copy[1]['path'] = '.github/workflows/pretend.yml'
            elif mutation == 'fork':
                run_copy[1]['head_repository']['full_name'] = 'fork/wfform'
            else:
                run_copy[1]['head_sha'] = 'b' * 40
            with self.subTest(mutation=mutation), self.assertRaises(delivery.DeliveryError):
                delivery.check_evidence(pr(), mutated, run_copy.__getitem__, policy())

    def test_newer_failing_run_does_not_use_old_success(self):
        checks, runs = evidence()
        newer = dict(checks[0], id=100, conclusion='failure')
        with self.assertRaises(delivery.DeliveryError):
            delivery.check_evidence(pr(), checks + [newer], runs.__getitem__, policy())

    def test_untrusted_details_url_is_not_followed(self):
        checks, runs = evidence()
        checks[0]['details_url'] = 'https://attacker.invalid/actions/runs/1/job/1'
        calls = []
        with self.assertRaises(delivery.DeliveryError):
            delivery.check_evidence(pr(), checks, lambda run: calls.append(run), policy())
        self.assertEqual(calls, [])

    def test_live_native_protection_is_mandatory(self):
        required = list(policy()['checks'])
        rule = {'requiresApprovingReviews': True, 'requiredApprovingReviewCount': 1,
                'dismissesStaleReviews': True, 'requiresConversationResolution': True,
                'requiresStatusChecks': True, 'requiresStrictStatusChecks': True,
                'requiredStatusCheckContexts': required, 'isAdminEnforced': True,
                'bypassPullRequestAllowances': {'totalCount': 0}}
        delivery.protection_gate(rule, policy(), production=True)
        for key in ['requiresConversationResolution', 'requiresStatusChecks',
                    'requiresStrictStatusChecks', 'isAdminEnforced']:
            with self.subTest(key=key), self.assertRaises(delivery.DeliveryError):
                delivery.protection_gate(dict(rule, **{key: False}), policy(), production=True)
        with self.assertRaises(delivery.DeliveryError):
            delivery.protection_gate(None, policy())

    def test_routine_merge_does_not_add_a_human_pr_gate(self):
        rule = {'requiresApprovingReviews': False, 'requiredApprovingReviewCount': 0,
                'dismissesStaleReviews': False, 'requiresConversationResolution': True,
                'requiresStatusChecks': True, 'requiresStrictStatusChecks': True,
                'requiredStatusCheckContexts': list(policy()['checks']), 'isAdminEnforced': True,
                'bypassPullRequestAllowances': {'totalCount': 0}}
        delivery.protection_gate(rule, policy(), production=True)

    def test_unknown_event_and_fork_workflow_are_rejected(self):
        event = {'repository': {'full_name': REPO, 'default_branch': 'main'}}
        with self.assertRaises(delivery.DeliveryError):
            delivery.event_gate('pull_request_target', event, policy())
        event['workflow_run'] = {'name': '🌐 Web quality', 'head_repository': {'full_name': 'fork/wfform'}}
        with self.assertRaises(delivery.DeliveryError):
            delivery.event_gate('workflow_run', event, policy())
        delivery.event_gate('schedule', event, policy())

    def test_reservation_before_paid_task_and_duplicate_is_noop(self):
        api = FakeAPI()
        calls = []
        def submit(body, token):
            self.assertEqual(len(api.comments), 1)
            self.assertIn('reserved', api.comments[0]['body'])
            calls.append(body)
            return {'id': 'task-1', 'state': 'queued', 'html_url': f'https://github.com/{REPO}/tasks/task-1'}
        issue = {'number': 9, 'title': 'Fix wrapping', 'body': 'Match the existing behavior.'}
        first = delivery.delegate(api, issue, 'bugfix', None, 'maintainer', 'test-token', submit)
        second = delivery.delegate(api, issue, 'bugfix', None, 'maintainer', 'test-token', submit)
        self.assertEqual(len(calls), 1)
        self.assertEqual(first['state'], 'submitted')
        self.assertEqual(second['state'], 'submitted')
        self.assertEqual(calls[0]['model'], 'gpt-5.3-codex')

    def test_uncertain_paid_task_never_retries(self):
        api, calls = FakeAPI(), []
        def submit(body, token):
            calls.append(body)
            raise SystemExit('outcome is unknown')
        issue = {'number': 9, 'title': 'Fix wrapping', 'body': 'Task'}
        with self.assertRaises(delivery.DeliveryError):
            delivery.delegate(api, issue, 'bugfix', None, 'maintainer', 'test-token', submit)
        result = delivery.delegate(api, issue, 'bugfix', None, 'maintainer', 'test-token', submit)
        self.assertEqual(result['state'], 'uncertain')
        self.assertEqual(len(calls), 1)

    def test_failed_reservation_never_submits_task(self):
        api, calls = FakeAPI(), []
        def fail(*args):
            raise delivery.DeliveryError('Comment outcome unknown')
        api.request = fail
        issue = {'number': 9, 'title': 'Fix wrapping', 'body': 'Task'}
        with self.assertRaises(delivery.DeliveryError):
            delivery.delegate(api, issue, 'bugfix', None, 'maintainer', 'test-token', lambda *args: calls.append(args))
        self.assertEqual(calls, [])

    def test_forged_receipt_does_not_impersonate_controller(self):
        api = FakeAPI()
        api.comments = [{'id': 5, 'user': {'login': 'stranger', 'type': 'User'},
                         'body': delivery.marker('task', '9') + '\n' + json.dumps({'state': 'submitted'})}]
        self.assertIsNone(delivery.receipt(api, 9, 'task', '9'))

    def test_untrusted_actor_and_issue_changes_reject_delegation(self):
        event = {'sender': {'login': 'reader', 'type': 'User'}, 'label': {'name': 'ai:feature'},
                 'action': 'labeled', 'issue': {'number': 9, 'title': 'Feature', 'body': 'One'}}
        api = FakeAPI()
        api.reads[f'/repos/{REPO}/collaborators/reader/permission'] = {'permission': 'read'}
        with self.assertRaises(delivery.DeliveryError):
            delivery.intake(api, 'issues', event, policy())
        api.reads[f'/repos/{REPO}/collaborators/reader/permission'] = {'permission': 'write'}
        api.reads[f'/repos/{REPO}/issues/9'] = {'number': 9, 'state': 'open', 'title': 'Feature', 'body': 'Changed', 'labels': [{'name': 'ai:feature'}]}
        with self.assertRaises(delivery.DeliveryError):
            delivery.intake(api, 'issues', event, policy())

    def test_release_dispatch_requires_authorization_and_has_once_receipt(self):
        api, calls = FakeAPI(), []
        pull = pr('release/1.0.0', 'main', state='closed', merged=True, merge_commit_sha=SHA)
        def authorize(*args):
            calls.append(args)
            return pull
        delivery.dispatch_release(api, pull, '1.0.0', authorize)
        delivery.dispatch_release(api, pull, '1.0.0', authorize)
        dispatches = [write for write in api.writes if write[1].endswith('/dispatches')]
        self.assertEqual(len(dispatches), 1)
        self.assertEqual(dispatches[0][2], {'ref': 'main', 'inputs': {'version': '1.0.0', 'release_sha': SHA, 'release_pr': '7'}})
        blocked = FakeAPI()
        def reject(*args):
            raise delivery.DeliveryError('No eligible approval')
        with self.assertRaises(delivery.DeliveryError):
            delivery.dispatch_release(blocked, pull, '1.0.0', reject)
        self.assertEqual(blocked.writes, [])

    def test_repair_budget_is_once_per_issue_even_when_head_changes(self):
        api, calls = FakeAPI(), []
        saved = {'model': 'gpt-5.3-codex', 'kind': 'bugfix', 'version': None,
                 'actor': 'maintainer', 'base_ref': 'develop'}
        pull = pr('copilot/x', 'develop', labels=[{'name': 'work:bugfix'}])
        failures = [{'name': 'Web checks', 'url': f'https://github.com/{REPO}/actions/runs/1/job/1'}]
        def submit(body, token):
            self.assertIn('reserved', api.comments[0]['body'])
            calls.append(body)
            return {'id': 'repair-1', 'state': 'queued', 'html_url': f'https://github.com/{REPO}/tasks/repair-1'}
        delivery.repair_once(api, {'number': 9}, saved, pull, failures, 'test', submit)
        pull['head']['sha'] = 'b' * 40
        delivery.repair_once(api, {'number': 9}, saved, pull, failures, 'test', submit)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]['head_ref'], 'copilot/x')
        self.assertEqual(calls[0]['base_ref'], 'develop')
        self.assertEqual(calls[0]['model'], 'gpt-5.3-codex')

    def test_repair_only_accepts_terminal_trusted_current_head_failure(self):
        checks, runs = evidence()
        checks[0]['conclusion'] = 'failure'
        runs[1]['conclusion'] = 'failure'
        failed = delivery.failed_check_evidence(pr(), checks, runs.__getitem__, policy())
        self.assertEqual([row['name'] for row in failed], ['Web checks'])
        for mutation in ['pending', 'cancelled', 'stale', 'app', 'path']:
            changed, copies = copy.deepcopy(checks), copy.deepcopy(runs)
            if mutation == 'pending':
                copies[1]['status'] = 'in_progress'
            elif mutation == 'cancelled':
                changed[0]['conclusion'] = 'cancelled'
            elif mutation == 'stale':
                changed[0]['head_sha'] = 'b' * 40
            elif mutation == 'app':
                changed[0]['app']['id'] = 123
            else:
                copies[1]['path'] = '.github/workflows/fake.yml'
            self.assertEqual(delivery.failed_check_evidence(pr(), changed, copies.__getitem__, policy()), [], mutation)

    def test_repair_refuses_a_different_base_or_unmanaged_branch(self):
        api = FakeAPI()
        saved = {'model': 'gpt-5.3-codex', 'kind': 'bugfix', 'version': None,
                 'actor': 'maintainer', 'base_ref': 'develop'}
        for pull in [pr('copilot/x', 'main'), pr('feature/x', 'develop')]:
            with self.assertRaises(delivery.DeliveryError):
                delivery.repair_once(api, {'number': 9}, saved, pull, [{}], 'test', lambda *args: self.fail('must not submit'))
        self.assertEqual(api.writes, [])

    def test_promotion_reuses_existing_pr_and_does_not_reopen_declined_pr(self):
        api = FakeAPI()
        existing = pr('release/1.0.0', 'main', state='closed')
        from urllib.parse import urlencode
        query = urlencode({'state': 'all', 'head': 'consciontologic:release/1.0.0', 'base': 'main', 'per_page': 100})
        api.reads[f'/repos/{REPO}/pulls?' + query] = [existing]
        result = delivery.ensure_pr(api, api, 'release/1.0.0', 'main', 'Release', 'Body')
        self.assertEqual(result['number'], 7)
        self.assertEqual(api.writes, [])

    def test_branch_update_binds_current_head_and_never_updates_protected_heads(self):
        api = FakeAPI()
        pull = pr(mergeable_state='behind')
        api.reads[f'/repos/{REPO}/branches/feature%2Ftools'] = {'protected': False, 'commit': {'sha': SHA}}
        self.assertTrue(delivery.update_branch(api, pull))
        self.assertEqual(api.writes, [('PUT', f'/repos/{REPO}/pulls/7/update-branch', {'expected_head_sha': SHA})])
        for protected in ['main', 'develop']:
            candidate = pr(protected, 'develop', mergeable_state='behind', body='<!-- wfform-delivery:backmerge -->')
            with self.assertRaises(delivery.DeliveryError):
                delivery.update_branch(api, candidate)
        candidate = pr(mergeable_state='behind')
        candidate['head']['repo']['full_name'] = 'fork/wfform'
        with self.assertRaises(delivery.DeliveryError):
            delivery.update_branch(api, candidate)
        self.assertEqual(len(api.writes), 1)
        self.assertFalse(delivery.update_branch(api, pr(mergeable_state='clean')))
        release = pr('release/1.0.0', 'main', mergeable_state='behind')
        api.reads[f'/repos/{REPO}/branches/release%2F1.0.0'] = {'protected': True, 'commit': {'sha': SHA}}
        with self.assertRaisesRegex(delivery.DeliveryError, 'protected'):
            delivery.update_branch(api, release)
        api.reads[f'/repos/{REPO}/branches/feature%2Ftools']['commit']['sha'] = 'b' * 40
        with self.assertRaisesRegex(delivery.DeliveryError, 'changed'):
            delivery.update_branch(api, pull)
        self.assertEqual(len(api.writes), 1)

    def test_uncertain_repair_is_not_submitted_again(self):
        api, calls = FakeAPI(), []
        saved = {'model': 'gpt-5.3-codex', 'kind': 'bugfix', 'version': None,
                 'actor': 'maintainer', 'base_ref': 'develop'}
        pull = pr('copilot/x', 'develop')
        failures = [{'name': 'Web checks', 'url': 'https://github.com/consciontologic/wfform/actions/runs/1/job/1'}]
        def submit(*args):
            calls.append(args)
            raise SystemExit('Unknown result')
        with self.assertRaises(delivery.DeliveryError):
            delivery.repair_once(api, {'number': 9}, saved, pull, failures, 'test', submit)
        delivery.repair_once(api, {'number': 9}, saved, pull, failures, 'test', submit)
        self.assertEqual(len(calls), 1)

    def test_controller_workflow_checks_out_only_default_branch(self):
        workflow = (ROOT / '.github/workflows/delivery.yml').read_text()
        self.assertIn('ref: main', workflow)
        self.assertNotIn('pull_request_target:', workflow)
        self.assertNotIn('pull_request:', workflow)
        self.assertNotIn('download-artifact', workflow)
        self.assertIn('environment: automation', workflow)
        self.assertIn('persist-credentials: false', workflow)
        self.assertIn('cancel-in-progress: false', workflow)
        self.assertIn('WFFORM_DELIVERY_TOKEN', workflow)

    def test_real_agent_artifact_database_id_resolves_to_visible_pr_number(self):
        from urllib.parse import urlencode
        api = FakeAPI()
        saved = {'base_ref': 'release/1.0.0'}
        task = {'artifacts': [{'provider': 'github', 'type': 'pull',
                              'data': {'id': 4800810052, 'global_id': ''}}],
                'sessions': [{'head_ref': 'copilot/release-100-preparation', 'base_ref': 'release/1.0.0'}]}
        query = urlencode({'state': 'open', 'head': 'consciontologic:copilot/release-100-preparation',
                           'base': 'release/1.0.0', 'per_page': 100})
        item = pr('copilot/release-100-preparation', 'release/1.0.0', number=2, id=4800810052)
        api.reads[f'/repos/{REPO}/pulls?' + query] = [item]
        self.assertEqual([pull['number'] for pull in delivery.managed_pull_requests(api, task, saved)], [2])
        api.reads[f'/repos/{REPO}/pulls?' + query][0]['id'] = 2
        self.assertEqual(delivery.managed_pull_requests(api, task, saved), [])
        self.assertEqual(api.writes, [])

    def test_completed_managed_task_with_real_artifact_shape_becomes_ready(self):
        from urllib.parse import urlencode
        api, tasks = FakeAPI(), FakeAPI()
        saved = {'state': 'submitted', 'task_id': 'initial-1', 'model': 'gpt-5.3-codex',
                 'kind': 'bugfix', 'version': None, 'base_ref': 'develop'}
        delivery.write_receipt(api, 9, 'task', '9', saved)
        pull = pr('copilot/fix', 'develop', id=4800810052, draft=True,
                  labels=[{'name': 'work:bugfix'}])
        api.reads[f'/repos/{REPO}/issues?state=open&labels=delivery%3Amanaged&per_page=10&sort=updated'] = [{'number': 9}]
        task = {'state': 'completed', 'artifacts': [{'provider': 'github', 'type': 'pull',
                                                  'data': {'id': 4800810052, 'global_id': ''}}],
                'sessions': [{'head_ref': 'copilot/fix', 'base_ref': 'develop', 'model': 'sweagent-capi:gpt-5.3-codex'}]}
        tasks.reads[f'/agents/repos/{REPO}/tasks/initial-1'] = task
        query = urlencode({'state': 'open', 'head': 'consciontologic:copilot/fix', 'base': 'develop', 'per_page': 100})
        api.reads[f'/repos/{REPO}/pulls?' + query] = [pull]
        api.reads[f'/repos/{REPO}/pulls/7'] = pull
        checks, runs = evidence()
        api.reads[f'/repos/{REPO}/commits/{SHA}/check-runs?filter=latest'] = checks
        for number, run in runs.items():
            api.reads[f'/repos/{REPO}/actions/runs/{number}'] = run
        request = api.request
        def ready(method, path, body=None):
            if path == '/graphql':
                self.assertIn('markPullRequestReadyForReview', body['query'])
                self.assertEqual(body['variables']['id'], 'PR_7')
                api.writes.append((method, path, body))
                return {'data': {'markPullRequestReadyForReview': {'pullRequest': {'number': 7}}}}
            return request(method, path, body)
        api.request = ready
        self.assertEqual(delivery.task_followups(api, tasks, policy()), {7})
        task['sessions'][0]['model'] = 'more-expensive-model'
        self.assertEqual(delivery.task_followups(api, tasks, policy()), set())
        self.assertEqual(len([row for row in api.writes if row[1] == '/graphql']), 1)

    def test_auto_merge_uses_expected_head_and_durable_identity(self):
        api, creator = FakeAPI(), FakeAPI()
        checks, runs = evidence()
        api.reads[f'/repos/{REPO}/commits/{SHA}/check-runs?filter=latest'] = checks
        for number, run in runs.items():
            api.reads[f'/repos/{REPO}/actions/runs/{number}'] = run
        native = {'id': 'PR_7', 'headRefOid': SHA, 'isDraft': False,
                  'baseRefName': 'develop', 'autoMergeRequest': None,
                  'baseRef': {'branchProtectionRule': {
                      'requiresStatusChecks': True, 'requiresStrictStatusChecks': True,
                      'requiresConversationResolution': True, 'isAdminEnforced': True,
                      'bypassPullRequestAllowances': {'totalCount': 0},
                      'requiredStatusCheckContexts': list(policy()['checks'])}}}
        def read_graph(method, path, body):
            self.assertTrue(body['query'].startswith('query'))
            return {'data': {'repository': {'pullRequest': native}}}
        api.request = read_graph
        def write_graph(method, path, body):
            creator.writes.append((method, path, body))
            return {'data': {'enablePullRequestAutoMerge': {'pullRequest': {'number': 7}}}}
        creator.request = write_graph
        delivery.arm_auto_merge(api, pr(mergeable_state='clean'), policy(), creator)
        self.assertEqual(len(creator.writes), 1)
        self.assertEqual(creator.writes[0][2]['variables']['input']['expectedHeadOid'], SHA)
        native['headRefOid'] = 'b' * 40
        with self.assertRaises(delivery.DeliveryError):
            delivery.arm_auto_merge(api, pr(mergeable_state='clean'), policy(), creator)
        self.assertEqual(len(creator.writes), 1)

    def test_backmerge_seeds_isolated_branch_once_and_preserves_divergence(self):
        from urllib.parse import urlencode
        api, creator = FakeAPI(), FakeAPI()
        branch = 'bugfix/backmerge-1.0.0'
        ref = f'/repos/{REPO}/git/ref/heads/{branch}'
        query = urlencode({'state': 'all', 'head': 'consciontologic:' + branch, 'base': 'develop', 'per_page': 100})
        api.reads[ref] = None
        api.reads[f'/repos/{REPO}/pulls?' + query] = []
        delivery.prepare_backmerge(api, creator, '1.0.0', SHA)
        self.assertEqual(creator.writes[0], ('POST', f'/repos/{REPO}/git/refs',
                                         {'ref': 'refs/heads/' + branch, 'sha': SHA}))
        self.assertEqual(creator.writes[1][2]['head'], branch)
        existing = pr(branch, 'develop')
        api.reads[ref] = {'object': {'sha': 'b' * 40}}
        api.reads[f'/repos/{REPO}/compare/{SHA}...' + 'b' * 40] = {'status': 'ahead'}
        api.reads[f'/repos/{REPO}/pulls?' + query] = [existing]
        self.assertEqual(delivery.prepare_backmerge(api, creator, '1.0.0', SHA)['number'], 7)
        self.assertEqual(len(creator.writes), 2)
        api.reads[f'/repos/{REPO}/compare/{SHA}...' + 'b' * 40] = {'status': 'diverged'}
        with self.assertRaises(delivery.DeliveryError):
            delivery.prepare_backmerge(api, creator, '1.0.0', SHA)
        self.assertEqual(len(creator.writes), 2)

    def test_release_branch_never_overwrites_or_targets_protected_refs(self):
        api = FakeAPI()
        path = f'/repos/{REPO}/git/ref/heads/release/1.0.0'
        api.reads[path] = None
        api.reads[f'/repos/{REPO}/git/ref/heads/develop'] = {'object': {'sha': SHA}}
        delivery.ensure_release_branch(api, '1.0.0')
        self.assertEqual(api.writes, [('POST', f'/repos/{REPO}/git/refs',
                                      {'ref': 'refs/heads/release/1.0.0', 'sha': SHA})])
        api.reads[path] = {'object': {'sha': 'b' * 40}}
        delivery.ensure_release_branch(api, '1.0.0')
        self.assertEqual(len(api.writes), 1)
        with self.assertRaises(delivery.DeliveryError):
            delivery.ensure_release_branch(api, '../main')


if __name__ == '__main__':
    unittest.main()
