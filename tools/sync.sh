#!/usr/bin/env bash
# Sync this project with GitHub (works in Termux on Android, Git Bash, Linux, macOS).
#   bash tools/sync.sh pull              -> just get the latest changes
#   bash tools/sync.sh "what I changed"  -> pull, commit everything, push
set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ "${1:-}" = "pull" ]; then
	git pull --rebase --autostash origin "$BRANCH"
	echo "Up to date with origin/$BRANCH"
	exit 0
fi

MSG="${1:-WIP $(date '+%Y-%m-%d %H:%M') from $(hostname 2>/dev/null || echo device)}"

git add -A
if git diff --cached --quiet; then
	echo "Nothing to commit."
else
	git commit -m "$MSG"
fi
git pull --rebase --autostash origin "$BRANCH"
for i in 1 2 3 4; do
	if git push -u origin "$BRANCH"; then
		echo "Pushed to origin/$BRANCH"
		exit 0
	fi
	echo "Push failed, retrying in $((2 ** i))s..."
	sleep $((2 ** i))
done
echo "Push failed. Check your connection / login (gh auth login)." >&2
exit 1
