#!/usr/bin/env python3
"""Publish one approved main revision; never merge, move tags or replace assets.

Run only from the trusted main workflow. Inputs describe a release, never grant
permission to release it. GitHub production approval/checks and source identity are checked
again immediately before writes. API failures are not automatically retried.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import HTTPRedirectHandler, Request, build_opener

SEMVER = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')
SHA = re.compile(r'[0-9a-f]{40}')
REPOSITORY = 'consciontologic/wfform'
ROOT = Path(__file__).resolve().parents[2]


def delivery_policy():
    return json.loads((ROOT / '.github/delivery-policy.json').read_text())


class DeliveryError(RuntimeError):
    """A release gate failed, or a mutation outcome needs human inspection."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class API:
    def __init__(self, token):
        if not token:
            raise DeliveryError('GH_TOKEN is required.')
        self.token = token
        self.opener = build_opener(NoRedirect())

    def _send(self, method, url, data=None, content_type='application/json'):
        request = Request(url, data=data, method=method, headers={
            'Authorization': 'Bearer ' + self.token,
            'Accept': 'application/vnd.github+json',
            'Content-Type': content_type,
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'wfform-release-delivery',
        })
        try:
            with self.opener.open(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except HTTPError as error:
            error.close()
            if method == 'GET' and error.code == 404:
                return None
            raise DeliveryError(f'GitHub {method} failed (HTTP {error.code}); inspect before retrying.') from error
        except (OSError, ValueError) as error:
            raise DeliveryError(f'GitHub {method} outcome is uncertain; inspect before retrying.') from error

    def get(self, path):
        return self.request('GET', path, None)

    def request(self, method, path, body=None):
        if not path.startswith('/repos/' + REPOSITORY + '/') or '\n' in path:
            raise DeliveryError('Unexpected GitHub API destination.')
        return self._send(method, 'https://api.github.com' + path,
                          json.dumps(body).encode() if body is not None else None)

    def upload(self, repo, release_id, path):
        if repo != REPOSITORY or not isinstance(release_id, int):
            raise DeliveryError('Unexpected release upload destination.')
        return self._send('POST', f'https://uploads.github.com/repos/{repo}/releases/{release_id}/assets?name='
                          + quote(path.name, safe=''), path.read_bytes(), 'application/octet-stream')


def pages(api, path, key=None):
    """Bound pagination and fail closed instead of silently losing approvals."""
    records = []
    join = '&' if '?' in path else '?'
    for page in range(1, 21):
        payload = api.get(f'{path}{join}per_page=100&page={page}')
        values = payload.get(key) if key and isinstance(payload, dict) else payload
        if not isinstance(values, list):
            raise DeliveryError('GitHub returned an incomplete collection.')
        records.extend(values)
        if len(values) < 100:
            return records
    raise DeliveryError('GitHub collection exceeds the bounded release audit.')


def current_main(api, repo, sha):
    ref = api.get(f'/repos/{repo}/git/ref/heads/main') or {}
    if ref.get('object', {}).get('sha') != sha:
        raise DeliveryError('Release revision is no longer the current main commit.')


def release_notes(root, version):
    root = Path(root)
    match = re.search(r'^version:\s*(\S+)\s*$', (root / 'pubspec.yaml').read_text(), re.M)
    if not match or match[1] != version:
        raise DeliveryError('Release version differs from pubspec.yaml.')
    changelog = (root / 'CHANGELOG.md').read_text()
    match = re.search(r'^## \[' + re.escape(version) + r'\][^\n]*\n(?:(?!^## ).)*',
                      changelog, re.M | re.S)
    if not match or len(match[0].strip().splitlines()) < 3:
        raise DeliveryError('CHANGELOG.md lacks substantive notes for this version.')
    return match[0].strip()


def is_hotfix(pr):
    branch = pr.get('head', {}).get('ref', '')
    names = {item.get('name') for item in pr.get('labels', [])}
    return (bool(re.fullmatch(r'(?:(?:codex|claude)/)?hotfix/[A-Za-z0-9][A-Za-z0-9._/-]*', branch))
            or (branch.startswith('copilot/') and 'work:hotfix' in names))


def is_promotion(pr):
    branch = pr.get('head', {}).get('ref', '')
    return (pr.get('base', {}).get('ref') == 'main' and
            (branch == 'develop' or bool(re.fullmatch(
                r'(?:(?:codex|claude)/)?release/' + SEMVER.pattern, branch))))


def git_tree(api, sha):
    if not SHA.fullmatch(sha or ''):
        raise DeliveryError('Source provenance requires an immutable commit.')
    commit = api.get(f'/repos/{REPOSITORY}/git/commits/{sha}') or {}
    tree = commit.get('tree', {}).get('sha', '')
    if commit.get('sha') != sha or not SHA.fullmatch(tree):
        raise DeliveryError('Cannot verify the immutable Git tree.')
    return tree


def run_identity(pr, run, paths):
    head = pr.get('head', {})
    return (isinstance(run, dict) and run.get('head_sha') == head.get('sha')
            and run.get('event') == 'pull_request'
            and run.get('path', '').split('@')[0] in paths
            and run.get('repository', {}).get('full_name') == REPOSITORY
            and run.get('head_repository', {}).get('full_name') == head.get('repo', {}).get('full_name'))


def run_matches(pr, run, paths, merged_match=None):
    head, base = pr.get('head', {}), pr.get('base', {})
    if not run_identity(pr, run, paths):
        return False
    associations = run.get('pull_requests')
    if not isinstance(associations, list):
        return False
    if associations:
        return any(isinstance(item, dict) and item.get('number') == pr.get('number')
                   and item.get('base', {}).get('ref') == base.get('ref')
                   and item.get('head', {}).get('sha') == head.get('sha') for item in associations)
    # GitHub can clear this association after merging. Never use the historical
    # fallback for missing metadata, a conflicting PR association, or open PRs.
    return merged_match is not None and merged_match(run)


def merged_run_matches(api, pr, run, cache):
    """Recover only unique, never-retargeted merged PRs from immutable evidence."""
    head = pr.get('head', {})
    if (pr.get('merged') is not True or pr.get('state') != 'closed' or pr.get('draft')
            or any(pr.get(side, {}).get('repo', {}).get('full_name') != REPOSITORY for side in ('head', 'base'))
            or run.get('head_branch') != head.get('ref')):
        return False
    try:
        times = [datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                 for value in [pr.get('created_at'), run.get('created_at'), run.get('run_started_at'),
                               run.get('updated_at'), pr.get('merged_at')]]
    except (TypeError, ValueError):
        return False
    if times != sorted(times):
        return False
    if 'proof' not in cache:
        owner = head.get('repo', {}).get('full_name', '').partition('/')[0]
        branch = quote(owner + ':' + head['ref'], safe='')
        history = pages(api, f'/repos/{REPOSITORY}/pulls?state=all&head={branch}')
        if len(history) != 1:
            raise DeliveryError('Merged quality evidence requires a branch used by exactly one PR.')
        source = history[0]
        if (source.get('number') != pr.get('number') or source.get('state') != 'closed'
                or source.get('draft') or source.get('merged_at') != pr.get('merged_at')
                or source.get('merge_commit_sha') != pr.get('merge_commit_sha')
                or any(source.get(side, {}).get('ref') != pr.get(side, {}).get('ref')
                       or source.get(side, {}).get('repo', {}).get('full_name') != pr.get(side, {}).get('repo', {}).get('full_name')
                       for side in ('head', 'base'))
                or source.get('head', {}).get('sha') != head.get('sha')):
            raise DeliveryError('Merged PR identity changed during the historical quality audit.')
        events = pages(api, f'/repos/{REPOSITORY}/issues/{pr["number"]}/events')
        if any(not isinstance(event, dict) or event.get('event') in {
                'base_ref_changed', 'automatic_base_change_succeeded'} for event in events):
            raise DeliveryError('A retargeted PR cannot supply quality evidence without its run association.')
        merged_sha = pr.get('merge_commit_sha', '')
        if not SHA.fullmatch(merged_sha) or not SHA.fullmatch(head.get('sha', '')):
            raise DeliveryError('Merged source revisions must be immutable commits.')
        commit = api.get(f'/repos/{REPOSITORY}/git/commits/{merged_sha}') or {}
        parents = commit.get('parents')
        if (commit.get('sha') != merged_sha or not isinstance(parents, list) or len(parents) != 2
                or parents[1].get('sha') != head['sha']
                or commit.get('tree', {}).get('sha') != git_tree(api, head['sha'])):
            raise DeliveryError('Merged source must retain its tested head as second parent with identical content.')
        cache['proof'] = True
    return cache['proof']


def validate_checks(pr, checks, get_run, policy, conclusions=('success',), merged_match=None):
    """Use the latest check for this exact PR/lane, never a push or package dispatch.

    A promotion may share a SHA with a tested develop PR. Its skipped jobs must
    not hide the develop PR's successful evidence (nor rescue a later failure).
    """
    for name, paths in policy['checks'].items():
        eligible = []
        for check in checks:
            if check.get('name') != name:
                continue
            match = re.fullmatch(r'https://github\.com/' + re.escape(REPOSITORY)
                                 + r'/actions/runs/([0-9]+)/job/[0-9]+', check.get('details_url') or '')
            if not match:
                continue
            run = get_run(int(match[1])) or {}
            proved = run_matches(pr, run, paths, merged_match)
            if proved or (merged_match is not None and pr.get('merged') is True
                          and run_identity(pr, run, paths)
                          and run.get('head_branch') == pr.get('head', {}).get('ref')):
                # Keep newer ambiguous runs in selection: a post-merge rerun
                # or malformed association must not rescue an older success.
                eligible.append((check, run, proved))
        check, run, proved = max(eligible, key=lambda item: item[0].get('id', 0), default=({}, {}, False))
        if (not proved or check.get('head_sha') != pr['head']['sha']
                or check.get('app', {}).get('id') != policy['checks_app_id']
                or check.get('status') != 'completed' or check.get('conclusion') not in conclusions
                or run.get('status') != 'completed' or run.get('conclusion') not in {'success', 'skipped'}):
            raise DeliveryError('Required PR check lacks current successful workflow provenance: ' + name)
        if merged_match is not None and run.get('pull_requests') == []:
            try:
                bounds = [datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                          for value in [run.get('run_started_at'), check.get('started_at'), check.get('completed_at'),
                                        run.get('updated_at'), pr.get('merged_at')]]
            except (TypeError, ValueError):
                raise DeliveryError('Merged PR check completion time is unavailable: ' + name) from None
            if bounds != sorted(bounds):
                raise DeliveryError('Merged PR check did not complete within its pre-merge run: ' + name)


def quality_evidence(api, pr):
    base = pr.get('base', {})
    if (base.get('repo', {}).get('full_name') != REPOSITORY
            or not (base.get('ref') == 'develop' or (base.get('ref') == 'main' and is_hotfix(pr)))):
        raise DeliveryError('Quality evidence must come from a develop PR or recognized main hotfix.')
    checks = pages(api, f'/repos/{REPOSITORY}/commits/{pr["head"]["sha"]}/check-runs?filter=all', 'check_runs')
    cache = {}
    def run(number):
        if number not in cache:
            cache[number] = api.get(f'/repos/{REPOSITORY}/actions/runs/{number}')
        return cache[number]
    merged_cache = {}
    validate_checks(pr, checks, run, delivery_policy(),
                    merged_match=lambda value: merged_run_matches(api, pr, value, merged_cache))


def promotion_evidence(api, pr):
    """Read only: candidate/final merge and prior tested develop source must match."""
    if (not is_promotion(pr) or pr.get('draft')
            or any(pr.get(side, {}).get('repo', {}).get('full_name') != REPOSITORY for side in ('head', 'base'))):
        raise DeliveryError('Expected a same-repository develop or release promotion into main.')
    if not pr.get('merged') and (pr.get('state') != 'open' or pr.get('mergeable') is not True):
        raise DeliveryError('Promotion mergeability is not confirmed; wait for GitHub to calculate it.')
    tree = git_tree(api, pr['head']['sha'])
    if git_tree(api, pr.get('merge_commit_sha')) != tree:
        raise DeliveryError('Promotion merge tree differs from its source tree; untested content is refused.')
    # Bounded history is explicit. A stale unprovable candidate is never released.
    candidates = pages(api, f'/repos/{REPOSITORY}/pulls?state=closed&base=develop&sort=updated&direction=desc')
    for candidate in candidates:
        if not candidate.get('merged_at'):
            continue
        source = api.get(f'/repos/{REPOSITORY}/pulls/{candidate["number"]}') or {}
        if (not source.get('merged') or source.get('base', {}).get('ref') != 'develop'
                or source.get('base', {}).get('repo', {}).get('full_name') != REPOSITORY):
            continue
        if (git_tree(api, source.get('head', {}).get('sha')) != tree
                or git_tree(api, source.get('merge_commit_sha')) != tree):
            continue
        quality_evidence(api, source)
        return {'source_pr': source['number'], 'tree': tree,
                'source_head': source['head']['sha'], 'source_merge': source['merge_commit_sha']}
    raise DeliveryError('No merged develop PR proves successful quality for this exact source tree.')


def authorize(api, repo, pr_number, sha, version, root=None):
    if repo != REPOSITORY or not SHA.fullmatch(sha) or not SEMVER.fullmatch(version):
        raise DeliveryError('Expected this repository, a full SHA and plain MAJOR.MINOR.PATCH.')
    if not isinstance(pr_number, int) or pr_number <= 0:
        raise DeliveryError('Expected a release promotion PR number.')
    pr = api.get(f'/repos/{repo}/pulls/{pr_number}') or {}
    head, target = pr.get('head', {}), pr.get('base', {})
    if (not pr.get('merged') or pr.get('draft') or pr.get('merge_commit_sha') != sha
            or target.get('ref') != 'main' or not (is_promotion(pr) or is_hotfix(pr))
            or any(pr.get(side, {}).get('repo', {}).get('full_name') != repo for side in ('head', 'base'))
            or not SHA.fullmatch(head.get('sha', ''))):
        raise DeliveryError('Expected a merged, same-repository release or hotfix promotion into main.')
    if re.fullmatch(r'(?:(?:codex|claude)/)?release/' + SEMVER.pattern, head.get('ref', '')) and head['ref'].rsplit('/', 1)[-1] != version:
        raise DeliveryError('Release branch version does not match the requested publication.')
    current_main(api, repo, sha)
    production_environment(api, repo)
    if root is not None:
        release_notes(root, version)
    if is_hotfix(pr):
        quality_evidence(api, pr)
        if git_tree(api, sha) != git_tree(api, head['sha']):
            raise DeliveryError('Hotfix merge tree contains content not represented by its tested head.')
    else:
        promotion_evidence(api, pr)
    return pr


def production_environment(api, repo):
    """Configuration drift must not turn a required human gate into a bypass."""
    base = f'/repos/{repo}/environments/production'
    environment = api.get(base) or {}
    policy = environment.get('deployment_branch_policy') or {}
    if (environment.get('name') != 'production' or not environment.get('id')
            or policy.get('custom_branch_policies') is not True
            or policy.get('protected_branches') is not False):
        raise DeliveryError('Production must restrict deployment to the main branch.')
    branches = pages(api, base + '/deployment-branch-policies', 'branch_policies')
    if len(branches) != 1 or branches[0].get('name') != 'main' or branches[0].get('type', 'branch') != 'branch':
        raise DeliveryError('Production deployment must allow only the main branch.')
    reviewers = [reviewer for rule in environment.get('protection_rules', [])
                 if rule.get('type') == 'required_reviewers' for reviewer in rule.get('reviewers', [])]
    if not reviewers or any(r.get('type') != 'User' or r.get('reviewer', {}).get('type') != 'User'
                            or not r.get('reviewer', {}).get('id') for r in reviewers):
        raise DeliveryError('Production requires at least one eligible human reviewer, without bot/team alternatives.')
    expected = delivery_policy()['production_reviewer']
    if len(reviewers) != 1 or any(
            r['reviewer']['id'] != expected['id']
            or r['reviewer'].get('login', '').lower() != expected['login'].lower()
            for r in reviewers):
        raise DeliveryError('Production reviewer differs from the explicitly configured human release approver.')
    return environment, {r['reviewer']['id'] for r in reviewers}


def deployment_approval(api, repo, sha, run_id):
    """Read GitHub's audit record; never call any workflow approval endpoint."""
    if not isinstance(run_id, int) or run_id <= 0:
        raise DeliveryError('A concrete workflow run is required for final human approval.')
    environment, humans = production_environment(api, repo)
    base = f'/repos/{repo}/actions/runs/{run_id}'
    run = api.get(base) or {}
    if (run.get('head_sha') != sha or run.get('head_branch') != 'main'
            or run.get('event') != 'workflow_dispatch'
            or run.get('path') != '.github/workflows/companion.yml'
            or run.get('repository', {}).get('full_name') != repo
            or run.get('head_repository', {}).get('full_name') != repo):
        raise DeliveryError('Production approval belongs to a different workflow or source revision.')
    reviews = api.get(base + '/approvals')
    if not isinstance(reviews, list):
        raise DeliveryError('Production approval history is unavailable.')
    relevant = [review for review in reviews if any(
        item.get('id') == environment['id'] and item.get('name') == 'production'
        for item in review.get('environments', []))]
    if any(review.get('state') == 'rejected' for review in relevant):
        raise DeliveryError('Production was rejected; start a new reviewed release run.')
    if not any(review.get('state') == 'approved' and review.get('user', {}).get('type') == 'User'
               and review.get('user', {}).get('id') in humans for review in relevant):
        raise DeliveryError('This workflow run has no eligible human production approval.')
    current_main(api, repo, sha)


def checked_assets(root, version):
    """Exactly web/Linux/Windows triples, each archive checked against metadata."""
    root = Path(root)
    paths = []
    for folder, stem, extension in [
        ('companion', f'wfformcomp-{version}-linux-x64', 'tar.gz'),
        ('companion', f'wfformcomp-{version}-windows-x64', 'zip'),
        ('release', f'wfform-{version}-web', 'tar.gz'),
    ]:
        archive = root / 'build' / folder / f'{stem}.{extension}'
        checksum = archive.with_name(archive.name + '.sha256')
        metadata = archive.with_name(stem + '.json')
        if any(not p.is_file() or p.is_symlink() for p in [archive, checksum, metadata]):
            raise DeliveryError('A required release package, checksum or metadata file is missing.')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        expected = f'{digest}  {archive.name}'
        data = json.loads(metadata.read_text())
        if (checksum.read_text().strip() != expected or data.get('version') != version
                or data.get('archive') != archive.name or data.get('sha256') != digest):
            raise DeliveryError('A release package failed its checksum or version identity check.')
        paths.extend([archive, checksum, metadata])
    return paths


def assert_asset(entry, path):
    digest = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
    if (entry.get('state') != 'uploaded' or entry.get('size') != path.stat().st_size
            or entry.get('digest') != digest):
        raise DeliveryError(f'Existing release asset conflicts or lacks a verified digest: {path.name}.')


def publish(api, repo, pr_number, sha, version, notes, assets, root=None, *, run_id=None):
    authorize(api, repo, pr_number, sha, version, root)
    deployment_approval(api, repo, sha, run_id)
    if not assets or len({p.name for p in assets}) != len(assets):
        raise DeliveryError('Release assets must be nonempty and uniquely named.')
    base = f'/repos/{repo}'
    marker = f'<!-- wfform-release pr={pr_number} sha={sha} version={version} -->'
    body = notes.strip() + '\n\n' + marker
    # Tag lookup only promises published releases. Listing with contents:write
    # includes drafts, so interrupted uploads can resume without duplicate drafts.
    releases = [item for item in pages(api, f'{base}/releases') if item.get('tag_name') == version]
    if len(releases) > 1:
        raise DeliveryError('Multiple releases use this version; inspect before recovery.')
    existing = releases[0] if releases else None
    if existing and (existing.get('tag_name') != version or existing.get('target_commitish') != sha
                     or existing.get('name') != version or existing.get('body') != body
                     or existing.get('prerelease')):
        raise DeliveryError('Existing release identity or notes conflict; nothing is overwritten.')
    tag = api.get(f'{base}/git/ref/tags/{version}')
    if tag and tag.get('object') != {'type': 'commit', 'sha': sha}:
        # Real GitHub refs include additional object fields; compare only identity.
        obj = tag.get('object', {})
        if obj.get('type') != 'commit' or obj.get('sha') != sha:
            raise DeliveryError('Existing tag does not identify this approved commit; tags are immutable.')
    if not tag:
        if existing:
            raise DeliveryError('Existing release has lost its tag; inspect before recovery.')
        current_main(api, repo, sha)
        api.request('POST', f'{base}/git/refs', {'ref': 'refs/tags/' + version, 'sha': sha})
    if not existing:
        current_main(api, repo, sha)
        existing = api.request('POST', f'{base}/releases', {
            'tag_name': version, 'target_commitish': sha, 'name': version,
            'body': body, 'draft': True, 'prerelease': False})
    release_id = existing['id']
    entries = pages(api, f'{base}/releases/{release_id}/assets')
    by_name = {entry['name']: entry for entry in entries}
    names = {path.name for path in assets}
    if len(by_name) != len(entries) or set(by_name) - names:
        raise DeliveryError('Existing release contains unexpected or duplicate assets.')
    # Inspect all existing files before uploading any missing file.
    for path in assets:
        if path.name in by_name:
            assert_asset(by_name[path.name], path)
    for path in assets:
        if path.name not in by_name:
            if not existing.get('draft'):
                raise DeliveryError('Published release is incomplete; do not modify a public release.')
            current_main(api, repo, sha)
            assert_asset(api.upload(repo, release_id, path), path)
    entries = pages(api, f'{base}/releases/{release_id}/assets')
    if len(entries) != len(assets) or {e['name'] for e in entries} != names:
        raise DeliveryError('Release assets are incomplete; draft was retained.')
    by_name = {entry['name']: entry for entry in entries}
    for path in assets:
        assert_asset(by_name[path.name], path)
    # Long uploads must not outlive changed approval policy or a newer main.
    authorize(api, repo, pr_number, sha, version, root)
    deployment_approval(api, repo, sha, run_id)
    if existing.get('draft'):
        api.request('PATCH', f'{base}/releases/{release_id}', {'draft': False, 'make_latest': 'true'})
    return f'https://github.com/{repo}/releases/tag/{version}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['authorize', 'approval', 'publish'])
    args = parser.parse_args()
    if (os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
            or os.environ.get('GITHUB_REF') != 'refs/heads/main'):
        raise DeliveryError('Release delivery only runs from a trusted main workflow dispatch.')
    repo = os.environ.get('GITHUB_REPOSITORY', '')
    sha = os.environ.get('WFFORM_RELEASE_SHA', '')
    if os.environ.get('GITHUB_SHA') != sha:
        raise DeliveryError('Workflow revision must equal the selected release revision.')
    version = os.environ.get('WFFORM_RELEASE_VERSION', '')
    try:
        pr = int(os.environ.get('WFFORM_RELEASE_PR', ''))
    except ValueError as error:
        raise DeliveryError('A release PR number is required.') from error
    api = API(os.environ.get('GH_TOKEN'))
    root = Path.cwd()
    if args.command == 'authorize':
        authorize(api, repo, pr, sha, version, root)
        print(f'✅ Release source, required checks and human approval policy verified for {version} at {sha}.')
    elif args.command == 'approval':
        authorize(api, repo, pr, sha, version, root)
        deployment_approval(api, repo, sha, int(os.environ.get('GITHUB_RUN_ID', '')))
        print('✅ Eligible human approved production for this workflow run.')
    else:
        url = publish(api, repo, pr, sha, version, release_notes(root, version),
                      checked_assets(root, version), root, run_id=int(os.environ.get('GITHUB_RUN_ID', '')))
        print(f'🎉 Verified release: {url}')


if __name__ == '__main__':
    try:
        main()
    except (DeliveryError, OSError, ValueError, KeyError) as error:
        print(f'❌ Release stopped: {error}', file=sys.stderr)
        sys.exit(1)
