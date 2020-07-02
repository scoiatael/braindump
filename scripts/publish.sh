#!/bin/bash

if [ "`git status -s`" ]
then
    echo "The working directory is dirty. Please commit any pending changes."
    exit 1;
fi

set -euxo pipefail

echo "Deleting old publication"
rm -rf public
mkdir public
git worktree prune
rm -rf .git/worktrees/public/

echo "Checking out gh-pages branch into public"
git worktree add -B gh-pages public origin/gh-pages

echo "Removing existing files"
rm -rf public/*

echo "Generating site"
env HUGO_ENV=production hugo

echo "Updating gh-pages branch"
cd public && git add -f --all && git commit -m "Publishing to gh-pages (publish.sh): $(date)"

#echo "Pushing to github"
#git push --all
