# CLAUDE.md

## Project Overview

`convox-deploy-debug` is a single-file Bash diagnostic tool distributed to Convox customers. It captures pre-healthcheck pod logs, events, and status during Convox deployments by querying kubectl directly. The tool bridges a gap in the Convox CLI where `convox logs` does not surface output until pods pass health checks.

This is a Convox-maintained customer-facing tool. It ships as a standalone script with no installation step beyond `chmod +x`.

## Repository Structure

```
convox-deploy-debug          # The script itself (bash, executable)
README.md                    # Customer-facing documentation
CLAUDE.md                    # This file (committed, shared with the team)
sync-docs.sh                 # Pulls upstream Convox docs for reference
.gitignore
docs/                        # Upstream Convox docs (gitignored, pulled via sync-docs.sh)
```

There is one deliverable: the script. Everything else is documentation and tooling.

## Convox Documentation Reference

The full Convox documentation from the upstream `convox/convox` repository (https://github.com/convox/convox, `docs/` directory, `master` branch) can be pulled into this project for local reference.

### Syncing Docs

```bash
# Pull/update docs from master
./sync-docs.sh

# Pull from a specific branch
./sync-docs.sh some-branch

# Remove the local docs copy
./sync-docs.sh --clean
```

This populates the `./docs/` directory with the full Convox documentation tree. The directory is gitignored since it is a copy of upstream content.

### Docs Directory Layout

After syncing, the docs are available at:

```
docs/
  reference/
    primitives/
      app/
        service.md          # Service definition, all convox.yml service attributes
        resource/
          README.md          # Resource overview, overlays, RDS, ElastiCache
          postgres.md        # Postgres/RDS-Postgres options
          redis.md           # Redis/ElastiCache-Redis options
          mysql.md
          mariadb.md
          memcached.md
          postgis.md
        balancer.md          # Custom load balancers
        build.md             # Build process, build args, caching
        process.md           # Running processes, one-off commands
        release.md           # Releases, promotions, rollbacks
        timer.md             # Cron timers, parallel execution
        object.md
        README.md            # App overview
      rack/
        README.md            # Rack overview
        instance.md
        registry.md
    convox-k8s-mapping.md    # Convox-to-Kubernetes resource mapping (key reference)
  configuration/             # convox.yml config, env vars, load balancers, etc.
  deployment/                # Rolling updates, deployment workflows
  installation/              # Rack installation guides per cloud provider
  getting-started/
  help/
  management/
  integrations/
  cloud/
  development/
  tutorials/
  example-apps/
```

### Key Documentation Files

When working on this tool, the most relevant docs are:

- **`docs/reference/convox-k8s-mapping.md`** -- The Convox-to-Kubernetes resource mapping. This is the authoritative reference for namespace patterns, label conventions, and how convox.yml sections translate to Kubernetes resources. The script's core logic depends on these conventions.
- **`docs/reference/primitives/app/service.md`** -- All service attributes in convox.yml (health checks, scaling, volumes, init containers, lifecycle hooks, etc.). Relevant when adding support for new service features.
- **`docs/reference/primitives/app/timer.md`** -- Timer/CronJob configuration. Relevant if expanding the tool to debug timer failures.
- **`docs/reference/primitives/app/resource/README.md`** -- Resource types (containerized and managed). Relevant if expanding to debug resource connectivity.

### Using Docs as Context

When making changes to the script, reference the local docs to verify Convox conventions before assuming behavior. For example:

- Namespace naming: confirmed in `docs/reference/convox-k8s-mapping.md`
- Label scheme (`system=convox`, `service=<name>`, etc.): confirmed in the same file
- Init container naming (`init`): confirmed in service.md and the k8s mapping doc (script discovers all init containers dynamically)
- Health check behavior: confirmed in `docs/reference/primitives/app/service.md` under the `health` and `liveness` sections
- Timer/CronJob naming (`timer-<name>`): confirmed in `docs/reference/primitives/app/timer.md`

If a convention is not documented in the local docs, check the upstream repo directly at https://github.com/convox/convox before making assumptions.

## Technical Context

### Convox Kubernetes Conventions

The script relies on these Convox-to-Kubernetes mapping conventions:

- App namespace pattern: `<rack-name>-<app-name>`
- Rack system namespace pattern: `<rack-name>-system`
- All Convox-managed resources carry the label `system=convox`
- Services are labeled `service=<service-name>`
- Resources are labeled `resource=<resource-name>`
- Init containers in Convox are conventionally named `init`, but the script discovers all init containers dynamically
- Environment secrets follow the pattern `env-<service-name>`

These conventions are stable across Convox v3 racks on all supported cloud providers (AWS, GCP, Azure, DigitalOcean).

### Dependencies

- `bash` (4.0+, for associative features and `pipefail`)
- `kubectl` (required, must have cluster access; all calls include `--request-timeout=10s`)
- `python3` (required, validated at startup; 3.6+ for `datetime.fromisoformat`, used for pod JSON parsing and JSON output escaping)
- `curl` (only for `--repo` and remote `--convox-yml` URL features)
- `yq` v4+ (optional, improves convox.yml parsing, grep fallback exists)

### How the Script Works

1. Parses CLI args (with `require_arg` guards on all value flags), validates required flags (`--rack`, `--app`) and dependencies (`kubectl`, `python3`)
2. If `--repo` or a URL-based `--convox-yml` is provided, fetches the manifest via curl to a temp file (cleaned up on exit via trap)
3. If a convox.yml is available (local or fetched), discovers service names using yq or grep fallback
4. Checks for pods stuck in `Init:` state and captures init container logs (discovers all init containers dynamically, not just the one named `init`)
5. Fetches all pods in the `<rack>-<app>` namespace as JSON via kubectl
6. Passes service filter list to Python via temp file (avoids shell interpolation issues with special characters)
7. Parses pod JSON with an inline Python script to classify pods (unhealthy, not-ready, new, healthy)
8. For each non-healthy pod (or all pods if `--all`): collects current logs, previous container logs, and Kubernetes events
9. Renders output in one of three modes: terminal (full color), summary (table), json
10. JSON output is assembled entirely via `python3 json.dump()` for correct escaping of all control characters

## Code Style and Conventions

### General Rules

- No em dashes or en dashes anywhere in output, comments, or documentation
- Direct, conversational tone in user-facing text (help output, error messages, README)
- No corporate jargon
- Keep error messages actionable: tell the user what went wrong and what to do about it

### Bash Style

- `set -euo pipefail` at the top, always
- Use `readonly` for constants
- Use `local` for all function variables
- shellcheck-clean (suppress with inline comments where necessary, e.g., intentional word splitting)
- Quote all variable expansions unless intentional splitting is needed
- Functions are lowercase with underscores
- Use `[[ ]]` over `[ ]`
- Heredocs for multi-line output, `cat <<EOF` pattern
- No bashisms that break on bash 4.x

### Output and Formatting

- Colors defined as variables, auto-disabled when stdout is not a terminal or `--no-color` is set
- All stderr output (warnings, errors, debug) goes through helper functions (`info`, `warn`, `err`, `debug`)
- Debug output is gated behind `DEBUG=1` / `--debug`
- The `separator` function draws a consistent divider line
- JSON output is built via `python3 json.dump()` for correct escaping; always test with `jq .` before shipping changes
- All kubectl calls use `--` before pod name positional args to prevent flag interpretation

### Versioning

- Semantic versioning: `MAJOR.MINOR.PATCH`
- Version is stored in the `VERSION` readonly variable at the top of the script and in the header comment block
- Update both locations when bumping
- Add a Version History entry to README.md for every release

## Testing

There is no automated test suite. Verify changes manually:

```bash
# Parse check
bash -n convox-deploy-debug

# shellcheck
shellcheck convox-deploy-debug

# Help output renders correctly
./convox-deploy-debug --help

# Version flag
./convox-deploy-debug --version

# Validate JSON output is parseable (requires a live cluster)
./convox-deploy-debug -r <rack> -a <app> -o json | jq .

# Test remote manifest fetch (public repo)
./convox-deploy-debug -r <rack> -a <app> --repo github.com/convox/convox --branch master --manifest examples/convox.yml

# Test color disable on pipe
./convox-deploy-debug -r <rack> -a <app> | cat

# Test error paths
./convox-deploy-debug -r nonexistent -a nonexistent
./convox-deploy-debug -r <rack> -a <app> --repo github.com/nonexistent/nonexistent
./convox-deploy-debug -r <rack> -a <app> -y /nonexistent/path

# Test argument guard (should error, not crash)
./convox-deploy-debug --rack
./convox-deploy-debug -r myrack --app
```

## Making Changes

### Adding a New Flag

1. Add a default value variable in the Defaults section
2. Add the case to `parse_args()` -- if the flag takes a value, use `require_arg "$1" "$@"` before reading `$2`
3. Add validation logic to `validate()` if needed
4. Document in the `usage()` function help text
5. Document in README.md under Usage Reference
6. Add to relevant examples in both help text and README

### Adding a New Output Mode

1. Add the mode name to the validation check in `validate()`
2. Add a new rendering block in `collect_diagnostics()` alongside the existing terminal/summary/json blocks
3. Document in README.md under Output Modes

### Changing Pod Classification Logic

The classification logic lives in the inline Python script inside `collect_diagnostics()`. The four categories (unhealthy, not-ready, new, healthy) map to the terminal legend and the JSON `classification` field. If you change these, update:

- The Python classification block
- The terminal legend at the bottom of terminal mode output
- The Pod Classification table in README.md

### Bumping the Version

1. Update `readonly VERSION="X.Y.Z"` in the script
2. Update the header comment block version
3. Update the artifact title if applicable
4. Add a Version History entry to README.md
5. Update CLAUDE.md if any conventions or structure changed