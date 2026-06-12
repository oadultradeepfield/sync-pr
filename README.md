# sync-pr

Rebase your feature branch onto the latest remote main branch to keep an open pull request up to date.

```bash
git clone https://github.com/oadultradeepfield/sync-pr.git
chmod +x sync-pr/sync-pr.sh
ln -sf "$(pwd)/git-sync-pr/sync-pr.sh" ~/.local/bin/sync-pr
```

Run `sync-pr <main>` from any Git repo to rebase your current branch onto the latest `origin/<main>`, or pass `sync-pr <feature> <main>` to target a specific branch.
