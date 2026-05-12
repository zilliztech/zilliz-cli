# Best Practices for Operating Zilliz Cloud with zilliz / zz

This guide is for users of the `zilliz` / `zz` CLI. It summarizes recommended workflows for operating Zilliz Cloud safely and efficiently. `zilliz` and `zz` have identical behavior; `zz` is only a shorter alias — every command below also works with `zz` (e.g. `zz cluster list`).

Running the binary with no arguments (`zilliz` or `zz`) launches the interactive TUI. All examples in this guide use the CLI form.

## 1. First-time setup

For first-time users, start with the guided onboarding flow:

```bash
zilliz quickstart
```

It walks you through login, organization selection, cluster context setup, and prints common next-step commands.

For non-interactive environments, print the cheatsheet only:

```bash
zilliz quickstart --non-interactive
```

If you are already logged in, skip the login step:

```bash
zilliz quickstart --skip-login
```

## 2. Login and authentication

### Local interactive usage

Use browser-based login:

```bash
zilliz login
```

On a headless host where no browser can open, suppress auto-launch and use the URL printed on stderr:

```bash
zilliz login --no-browser
```

Log out and clear stored credentials:

```bash
zilliz logout
```

### API key login

Prompt for an API key interactively:

```bash
zilliz login --api-key
```

Pass an API key directly:

```bash
zilliz login --api-key sk-xxx
```

For automation and CI, prefer an environment variable so the API key does not appear in shell history:

```bash
export ZILLIZ_API_KEY=sk-xxx
zilliz cluster list
```

### China Cloud

China Cloud only supports API-key login. `--cn` must be combined with `--api-key`:

```bash
zilliz login --cn --api-key
```

or pass the key directly (not recommended in shared shells):

```bash
zilliz login --cn --api-key sk-xxx
```

`--cn` targets `api.cloud.zilliz.com.cn` and persists the endpoint, so subsequent commands continue to target China Cloud until you `zilliz logout` or run a fresh `zilliz login` against the global cloud.

### Configuration files

The CLI stores state under `~/.zilliz/` (override with `ZILLIZ_CONFIG_DIR`):

- `~/.zilliz/credentials` — `api_key`, `user`, `org`, `plan` (mode `0o600` on Unix)
- `~/.zilliz/config` — `cluster_id`, `endpoint`, `database`

`ZILLIZ_API_KEY` overrides whatever is stored in `credentials`. In CI, set `ZILLIZ_CONFIG_DIR` to a fresh temp directory to avoid polluting the runner's global config.

## 3. Verify identity and organization

Show the current authentication status:

```bash
zilliz whoami
```

Alias:

```bash
zilliz info
```

Switch organization interactively:

```bash
zilliz switch
```

Switch to a specific organization ID:

```bash
zilliz switch <org-id>
```

Before production operations, run:

```bash
zilliz whoami
zilliz context current
```

Confirm that the current account, organization, and cluster context are correct.

## 4. Cluster context

Data-plane operations, such as collection, vector, and index operations, usually require a cluster context.

Set context interactively:

```bash
zilliz context set
```

Set context with a cluster ID:

```bash
zilliz context set --cluster-id <cluster-id>
```

Show current context:

```bash
zilliz context current
```

Clear current context:

```bash
zilliz context clear
```

If a command reports that no context is set, run:

```bash
zilliz context set --cluster-id <cluster-id>
```

For users who frequently switch clusters, store common cluster IDs in shell variables:

```bash
export DEV_CLUSTER=...
export PROD_CLUSTER=...

zilliz context set --cluster-id "$DEV_CLUSTER"
```

## 5. Control-plane vs data-plane operations

### Control-plane operations

Control-plane commands manage cloud resources, for example:

```bash
zilliz cluster list
zilliz cluster describe
zilliz project list
zilliz backup list
zilliz billing usage
```

These commands mainly call Zilliz Cloud management APIs.

### Data-plane operations

Data-plane commands operate on Milvus data. Covered resources include:

- `collection`, `alias`, `external-collection`
- `database`, `partition`, `index`
- `vector` (insert, upsert, search, hybrid-search, query, get, delete)
- `user`, `role` (Dedicated only)

```bash
zilliz collection list
zilliz collection describe --name <name>
zilliz vector search
zilliz index create
```

These commands depend on the current cluster context.

Recommended habit:

- Before managing clusters or projects, verify the current organization.
- Before operating collections or vectors, verify the current context.

## 6. Output formats

Supported output formats:

```bash
-o table
-o json
-o yaml
-o csv
-o text
```

The default is `table`.

For human inspection, use the default table output:

```bash
zilliz cluster list
zilliz collection list
```

For scripts and automation, use JSON:

```bash
zilliz cluster list -o json
```

With `jq`:

```bash
zilliz cluster list -o json | jq .
```

Export CSV:

```bash
zilliz cluster list -o csv > clusters.csv
```

Suppress headers:

```bash
zilliz cluster list -o csv --no-header
```

## 7. Filter output with JMESPath

`--query` supports JMESPath for filtering output inside the CLI.

Example:

```bash
zilliz cluster list -o json --query "clusters[*].{id:clusterId,name:clusterName}"
```

Extract cluster IDs only:

```bash
zilliz cluster list -o json --query "clusters[*].clusterId"
```

Recommendations:

- Use `table` for human-readable output.
- Use `json` for scripts.
- Use `--query` for field selection and filtering.
- Combine with `jq` for more processing.

## 8. Dangerous operations

Dangerous operations, such as delete, release, suspend, restore, and clear, ask for confirmation.

Example:

```bash
zilliz collection drop --name <name>
```

In scripts, explicitly skip confirmation:

```bash
zilliz collection drop --name <name> --yes
```

Best practices:

- Do not casually add `--yes` when operating production resources manually.
- In scripts, add `--yes` explicitly to avoid blocking.
- Before deleting or restoring, describe the target resource first.

Recommended production deletion flow:

```bash
zilliz whoami
zilliz context current
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

## 9. Async jobs

Some control-plane operations are asynchronous, such as cluster creation and backup restore. Use `--wait` to wait until the job completes:

```bash
zilliz cluster create --wait
```

Recommendations:

- Use `--wait` for manual resource creation, restore, or changes.
- Use `--wait` in CI when later steps depend on completion.
- Without `--wait`, a command may only return a job ID; query status separately with:

```bash
zilliz job describe --job-id <job-id>
```

## 10. Pagination and full exports

For list operations that support pagination, use `--all` to fetch all pages:

```bash
zilliz cluster list --all
```

Export all results as JSON:

```bash
zilliz cluster list --all -o json > clusters.json
```

Export all results as CSV:

```bash
zilliz cluster list --all -o csv > clusters.csv
```

Recommendations:

- For quick human inspection, omit `--all`.
- For complete script exports, use `--all`.

## 11. Complex request bodies

For complex objects such as collections and indexes, put the JSON request body in a file and use `--body file://...`:

```bash
zilliz collection create --body file://schema.json
```

Recommendations:

- Store complex schemas in JSON files.
- Commit schema files to version control.
- Use code review for production resource changes.
- Avoid writing long JSON payloads directly in the shell.

## 12. Collection operations

Common flow:

```bash
zilliz context set --cluster-id <cluster-id>
zilliz collection list
zilliz collection describe --name <name>
```

Create a collection:

```bash
zilliz collection create --body file://schema.json
```

Before dropping a collection, verify the context and target:

```bash
zilliz context current
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

Drop a collection in scripts:

```bash
zilliz collection drop --name <name> --yes
```

## 13. Local Milvus standalone

For local development you can manage a Milvus standalone Docker deployment directly from the CLI (wraps the upstream `standalone_embed.sh`).

```bash
zilliz milvus standalone install    # download the script into ./milvus-standalone
zilliz milvus standalone start      # bring up the container
zilliz milvus standalone stop
zilliz milvus standalone restart
zilliz milvus standalone delete --yes   # destructive: removes volumes
zilliz milvus standalone upgrade --yes  # destructive: pulls latest script
```

Common flags: `--dir <path>` to choose the install directory, `--dry-run` to preview without touching Docker.

Requires bash and a working Docker daemon. Default endpoints after `start`: Milvus on `localhost:19530`, WebUI on `http://localhost:9091`, embedded etcd on `localhost:2379`.

## 14. Backups

Common commands:

```bash
zilliz backup list --cluster-id <cluster-id>
zilliz backup describe --cluster-id <cluster-id> --backup-id <id>
```

`backup describe` requires BOTH `--cluster-id` (the source cluster) and `--backup-id`.

Restore comes in two granularities:

```bash
# Restore a full backup into a brand-new cluster
zilliz backup restore-cluster \
  --cluster-id <source-cluster-id> \
  --backup-id <backup-id> \
  --project-id <target-project-id> \
  --name <new-cluster-name> \
  --cu-size <n> \
  --collection-status LOADED \
  --wait

# Restore specific collections into an existing cluster
zilliz backup restore-collection \
  --cluster-id <source-cluster-id> \
  --backup-id <backup-id> \
  --dest-cluster-id <target-cluster-id> \
  --body file://restore.json
```

Recommendations:

- Before restoring, confirm the backup's cluster, project, and region via `backup describe`.
- After restore, verify status with `cluster list` / `cluster describe` (for `restore-cluster`) or `collection list` (for `restore-collection`).
- Restore and delete operations are high risk; be careful with `--yes` in production.

## 15. On-demand Cluster / VectorLake

List and describe on-demand clusters:

```bash
zilliz on-demand-cluster list
zilliz on-demand-cluster describe
```

For VectorLake on-demand cluster context, use:

```bash
zilliz context set --cluster-id <cluster-id> --on-demand
```

Recommendations:

- Use `--on-demand` when setting context for on-demand clusters.
- Verify that the current project, region, and cluster match.
- Be aware that on-demand cluster parameters can differ from regular Dedicated cluster parameters.

## 16. Shell completion

Install shell completion:

```bash
zilliz completion install
```

Check status:

```bash
zilliz completion status
```

Remove completion:

```bash
zilliz completion uninstall
```

Print completion scripts:

```bash
zilliz completion show bash
zilliz completion show zsh
zilliz completion show fish
```

Install completion if you use the CLI frequently.

## 17. Command history

List command history:

```bash
zilliz history list
```

Search command history:

```bash
zilliz history search --keyword cluster
```

Clear command history:

```bash
zilliz history clear
```

Recommendations:

- Use history to recover complex commands.
- Sensitive parameters are redacted, but you should still avoid passing API keys directly on the command line.
- Clear history regularly on shared machines or bastion hosts.

## 18. Upgrade

Check for a newer version:

```bash
zilliz upgrade --check
```

Upgrade:

```bash
zilliz upgrade
```

Skip confirmation:

```bash
zilliz upgrade --yes
```

Force re-install (useful if the installer aborted mid-run):

```bash
zilliz upgrade --force
```

Alias:

```bash
zilliz update
```

Recommendations:

- When you encounter compatibility issues, check the CLI version first.
- Keep team members on similar versions to avoid behavior differences.
- In CI, pin the CLI version instead of upgrading on every run.

## 19. CI and automation

In CI, use an isolated config directory and an API key environment variable:

```bash
export ZILLIZ_API_KEY="$ZILLIZ_API_KEY"
export ZILLIZ_CONFIG_DIR="$RUNNER_TEMP/.zilliz"

zilliz cluster list -o json
```

For data-plane operations:

```bash
export ZILLIZ_API_KEY="$ZILLIZ_API_KEY"
export ZILLIZ_CONFIG_DIR="$RUNNER_TEMP/.zilliz"

zilliz context set --cluster-id "$CLUSTER_ID"
zilliz collection list -o json
```

Recommendations:

- Use `ZILLIZ_API_KEY`; do not hard-code API keys in scripts.
- Use an isolated `ZILLIZ_CONFIG_DIR` to avoid polluting global machine config.
- Use `-o json` consistently.
- Add `--yes` explicitly for dangerous operations.
- Use `--wait` for async operations.
- Use `--all` for complete list exports.
- Pass all required options explicitly; do not rely on interactive prompts.

## 20. Useful command templates

Show current status:

```bash
zilliz whoami
zilliz context current
```

Log in and set a cluster:

```bash
zilliz login
zilliz switch
zilliz context set
```

List clusters:

```bash
zilliz cluster list -o json
```

Extract cluster IDs:

```bash
zilliz cluster list -o json --query "clusters[*].clusterId"
```

Set data-plane context:

```bash
zilliz context set --cluster-id <cluster-id>
```

List collections:

```bash
zilliz collection list
```

Create a collection:

```bash
zilliz collection create --body file://schema.json
```

Drop a collection:

```bash
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

Drop a collection in scripts:

```bash
zilliz collection drop --name <name> --yes
```

Create a resource and wait for completion:

```bash
zilliz cluster create --wait
```

Export a list:

```bash
zilliz cluster list --all -o csv > clusters.csv
```

## 21. Common pitfalls

### Context is not set

Symptom:

```text
No cluster context set
```

Fix:

```bash
zilliz context set --cluster-id <cluster-id>
```

### Wrong organization

Verify identity and switch organization:

```bash
zilliz whoami
zilliz switch
```

### Wrong cluster

Verify and reset context:

```bash
zilliz context current
zilliz context set --cluster-id <cluster-id>
```

### API key leaks into shell history

Not recommended:

```bash
zilliz login --api-key sk-xxx
```

Recommended:

```bash
export ZILLIZ_API_KEY=sk-xxx
zilliz cluster list
```

or enter it interactively:

```bash
zilliz login --api-key
```

## 22. Quick checklist

1. First-time setup: `zilliz quickstart`.
2. Local interactive login: `zilliz login`.
3. CI authentication: `ZILLIZ_API_KEY`.
4. Before data-plane operations: `zilliz context set --cluster-id <id>`.
5. Before production operations: `zilliz whoami` and `zilliz context current`.
6. Script output: `-o json`.
7. Field filtering: `--query`.
8. Full paginated data: `--all`.
9. Async jobs: `--wait`.
10. Dangerous operations in scripts: `--yes`.
11. Complex request bodies: `--body file://xxx.json`.
12. Check for updates periodically: `zilliz upgrade --check`.
