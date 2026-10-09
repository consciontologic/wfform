#!/usr/bin/env bash
# Remote commit/push is intentionally confined to the requested GitHub workflow.
set -euo pipefail
report_status() {
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then printf 'status=%s\n' "$1" >> "$GITHUB_OUTPUT"; fi
}

if [[ ${GITHUB_ACTIONS:-} != true || ! ${GITHUB_REF:-} =~ ^refs/tags/(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || ${GITHUB_EVENT_NAME:-} != push ]]; then
  echo 'Website publication is only supported by the verified semantic-release GitHub workflow.' >&2
  exit 1
fi
: "${WFFORM_DEPLOY_TOKEN:?Add the WFFORM_DEPLOY_TOKEN Actions secret to the source repository.}"
: "${GH_TOKEN:?The source repository read token is required.}"
: "${GITHUB_SHA:?Missing source revision.}"
: "${GITHUB_REPOSITORY:?Missing source repository.}"
: "${RUNNER_TEMP:?Missing runner temporary directory.}"
if [[ $GITHUB_REPOSITORY != consciontologic/wfform ]]; then
  echo 'Website publication is only supported from consciontologic/wfform.' >&2
  exit 1
fi
[[ $# == 1 ]] || { echo 'Usage: publish-website.sh RELEASE_DIRECTORY' >&2; exit 64; }

# GitHub may schedule queued runs out of order. Never roll the site back to an
# older source commit, including when someone manually reruns an old workflow.
latest=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/main" --jq .object.sha)
if [[ $latest != "$GITHUB_SHA" ]]; then
  echo 'Skipping publication: source main has a newer commit.'
  report_status skipped-newer-main
  exit 0
fi

checkout=$(mktemp -d "$RUNNER_TEMP/wfform-website.XXXXXX")
askpass=$(mktemp "$RUNNER_TEMP/wfform-askpass.XXXXXX")
changes=$(mktemp "$RUNNER_TEMP/wfform-changes.XXXXXX")
cleanup() { rm -f "$askpass" "$changes"; rm -rf "$checkout"; }
trap cleanup EXIT
cat > "$askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "$WFFORM_DEPLOY_TOKEN" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass"
export GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0

git clone --no-checkout https://github.com/consciontologic/wfform.com.git "$checkout"
heads=$(git -C "$checkout" for-each-ref --format='%(refname)' refs/remotes/origin/)
if [[ -z $heads ]]; then
  git -C "$checkout" checkout --orphan main
elif git -C "$checkout" show-ref --verify --quiet refs/remotes/origin/main; then
  git -C "$checkout" checkout -B main origin/main
else
  echo 'The destination has commits but no main branch; choose its deployment branch explicitly before publishing.' >&2
  exit 1
fi

dart run tool/prepare_website.dart "$1" "$checkout" "$changes"
if [[ -s $changes ]]; then
  # Only deployment-owned changes enter the commit, including paths ignored by
  # an unrelated destination .gitignore. NUL separation preserves exact names.
  git -C "$checkout" add --all --force --pathspec-from-file="$changes" --pathspec-file-nul
fi
if git -C "$checkout" diff --cached --quiet; then
  echo 'Website artifacts are unchanged; no commit or push is needed.'
  report_status unchanged
  exit 0
fi

# Recheck after preparation as source main may have advanced while cloning.
latest=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/main" --jq .object.sha)
if [[ $latest != "$GITHUB_SHA" ]]; then
  echo 'Skipping publication: source main changed during artifact preparation.'
  report_status skipped-newer-main
  exit 0
fi
git -C "$checkout" -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "deploy(web): publish $GITHUB_REPOSITORY@$GITHUB_SHA"
# A concurrent destination edit fails normally. No force push or hidden retry.
git -C "$checkout" push origin HEAD:main
report_status published
echo 'Published static files to consciontologic/wfform.com main.'
