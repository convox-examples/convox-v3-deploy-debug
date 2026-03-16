# convox-deploy-debug

Diagnostic tool for capturing pre-healthcheck pod logs during Convox deployments.

`convox logs` does not surface pod output until containers pass their health check. Most deploy failures happen before that point. This script bridges the gap by querying kubectl directly using Convox's namespace and label conventions.

## Quick Start

The easiest way to get started is the interactive guided mode. It checks your dependencies, lets you pick a rack and app from a menu, and configures kubectl for you:

```bash
# Download and make executable
chmod +x convox-deploy-debug

# Run with no arguments to start the guided wizard
./convox-deploy-debug
```

The wizard will:

1. Check that `convox`, `kubectl`, and `python3` are installed (with install instructions if anything is missing)
2. Show your available racks and let you pick one
3. Configure kubectl to talk to that rack's cluster
4. List your apps and let you pick one to debug
5. Run the diagnostics

If you already know your rack and app name, you can skip the wizard:

```bash
./convox-deploy-debug --rack production --app myapp
```

## Requirements

- `bash` 4.0+
- `convox` CLI (logged in to your console)
- `kubectl` (the interactive wizard can configure this for you via `convox rack kubeconfig`)
- `python3` 3.6+ (used for pod JSON parsing)
- `curl` (only needed for `--repo` and remote `--convox-yml` URL features)
- `yq` v4+ (optional, improves convox.yml parsing; grep fallback exists)

If you run the script with no arguments, it checks all of these and gives you platform-specific install instructions for anything missing.

## Usage Reference

```
convox-deploy-debug                           # Interactive guided mode
convox-deploy-debug --setup                   # Same thing, explicit flag
convox-deploy-debug --rack <rack> --app <app> [OPTIONS]
```

### Required

| Flag | Description |
|------|-------------|
| `-r, --rack <name>` | Convox rack name |
| `-a, --app <name>` | Convox app name |

### Service Discovery

| Flag | Description |
|------|-------------|
| `-s, --service <name>` | Target a specific service (repeatable) |
| `-y, --convox-yml <path\|url>` | Local file path or raw URL to a convox.yml |
| `--repo <url>` | Repo URL to fetch convox.yml from (public repos only) |
| `--branch <name>` | Branch to use with `--repo` (default: `main`) |
| `--manifest <path>` | Path to convox.yml within the repo (default: `convox.yml`) |

For private repos, clone locally and use `--convox-yml <path>` instead of `--repo`.

### Filtering

| Flag | Description |
|------|-------------|
| `-A, --age <seconds>` | Pod age threshold in seconds (default: 300) |
| `--all` | Include all pods, not just unhealthy/new ones |

### Output

| Flag | Description |
|------|-------------|
| `-o, --output <mode>` | Output mode: `terminal`, `summary`, `json` (default: `terminal`) |
| `-n, --lines <count>` | Number of log lines per pod (default: 200) |
| `--no-events` | Skip pod events |
| `--no-previous` | Skip logs from previous (crashed) containers |
| `--describe` | Include full `kubectl describe pod` output |
| `--no-color` | Disable colored output |

### Cluster

| Flag | Description |
|------|-------------|
| `--kubeconfig <path>` | Path to kubeconfig file |
| `--context <name>` | Kubernetes context to use |

### General

| Flag | Description |
|------|-------------|
| `--setup` | Interactive guided setup (walks you through everything) |
| `-h, --help` | Show help |
| `-v, --version` | Show version |
| `--debug` | Enable debug output |

## Output Modes

### terminal (default)

Full diagnostic output with color-coded pod status, logs, events, and previous container logs. Best for interactive debugging.

### summary

Compact table view showing pod name, service, status, readiness, restart count, and state detail. Good for quick triage when you need to identify which pods are failing.

### json

Machine-readable JSON output with all pod data, logs, events, and classification. Pipe to `jq` for filtering or integrate into CI/CD pipelines.

```bash
# Get just the unhealthy pods
./convox-deploy-debug -r prod -a myapp -o json | jq '.pods[] | select(.classification == "unhealthy")'

# Get pod names and their state
./convox-deploy-debug -r prod -a myapp -o json | jq '.pods[] | {name, classification, stateDetail}'
```

## Pod Classification

The script classifies each pod into one of four categories:

| Classification | Meaning | Terminal Icon |
|---------------|---------|---------------|
| **unhealthy** | Pod phase is not `Running` (e.g., `Pending`, `Failed`, `CrashLoopBackOff`) | `[X]` (red) |
| **not-ready** | Pod is `Running` but has not passed readiness checks | `[!]` (yellow) |
| **new** | Pod is `Running` and ready, but younger than the age threshold | `[*]` (cyan) |
| **healthy** | Pod is `Running`, ready, and older than the age threshold | `[+]` (green) |

By default, only unhealthy, not-ready, and new pods are shown. Use `--all` to include healthy pods.

## Repo URL Format

The `--repo` flag accepts public repository URLs from GitHub, GitLab, and Bitbucket. The script constructs the raw file URL automatically.

Accepted formats:

```
github.com/org/repo
gitlab.com/org/repo
bitbucket.org/org/repo
https://github.com/org/repo
https://github.com/org/repo.git
git@github.com:org/repo.git
```

## Examples

```bash
# Basic: debug all services
./convox-deploy-debug -r production -a myapp

# Target a single service
./convox-deploy-debug -r production -a myapp -s web

# Auto-discover services from local convox.yml
./convox-deploy-debug -r production -a myapp -y ./convox.yml

# Auto-discover services from a GitHub repo
./convox-deploy-debug -r production -a myapp --repo github.com/myorg/myapp

# Repo on a feature branch with a non-default manifest path
./convox-deploy-debug -r production -a myapp \
  --repo github.com/myorg/myapp --branch staging --manifest deploy/convox.yml

# Auto-discover from a raw URL directly
./convox-deploy-debug -r production -a myapp \
  -y https://raw.githubusercontent.com/myorg/myapp/main/convox.yml

# Wider time window, write to file
./convox-deploy-debug -r production -a myapp -A 600 > deploy-debug.txt

# JSON output for programmatic consumption
./convox-deploy-debug -r production -a myapp -o json > debug.json

# Summary mode for quick triage
./convox-deploy-debug -r production -a myapp -o summary

# Use a specific kubeconfig and context
./convox-deploy-debug -r production -a myapp --kubeconfig ~/.kube/prod --context prod-cluster

# Include full pod describe output
./convox-deploy-debug -r production -a myapp --describe

# Show all pods including healthy ones
./convox-deploy-debug -r production -a myapp --all
```

## Interactive Guided Mode

Running the script with no arguments (or with `--setup`) starts an interactive wizard designed for users who may not be familiar with Kubernetes. The wizard handles the entire setup process:

```
$ ./convox-deploy-debug

convox-deploy-debug v1.2.0 -- Interactive Setup
------------------------------------------------------------------------------

Checking dependencies...

  [ok] convox CLI
  [ok] kubectl
  [ok] python3

>>> Checking current Convox rack...
  Current rack: production

>>> Fetching available racks...

  Use current rack production? [Y/n] y
>>> Selected rack: production

  kubectl needs access to the cluster backing this rack.
  This runs: convox rack kubeconfig --rack production

  Configure kubectl for rack production? [Y/n] y
>>> Fetching kubeconfig from Convox...
  [ok] kubectl configured (using temp kubeconfig)

>>> Fetching apps on rack production...

Select an app to debug:

  1) myapp
  2) api-gateway
  3) worker-pool

Enter a number (1-3): 1
>>> Selected app: myapp

  A convox.yml helps discover your service names for better output.
  This is optional -- the tool works without it.

  Do you have a convox.yml to point to? [y/N] n

------------------------------------------------------------------------------

Ready to run diagnostics:
  Rack:  production
  App:   myapp

  Tip: next time you can skip this wizard with:
    ./convox-deploy-debug --rack production --app myapp

  Run diagnostics now? [Y/n] y

>>> Starting diagnostics...
```

After you confirm, the tool runs the full diagnostics automatically. It also prints the equivalent CLI command so you can skip the wizard next time.

## How It Works

1. Parses CLI args, validates required flags (`--rack`, `--app`) and dependencies (`kubectl`, `python3`)
2. If `--repo` or a URL-based `--convox-yml` is provided, fetches the manifest via curl to a temp file (cleaned up on exit)
3. If a convox.yml is available (local or fetched), discovers service names using yq or grep fallback
4. **Service rollout overview** -- queries all services in the app to show a per-service status summary (running, deploying, stalled), resource health, and deploy-level events (see [Service and Resource Overview](#service-and-resource-overview) below)
5. Checks for pods stuck in `Init:` state and captures init container logs (all init containers, not just Convox's)
6. Fetches all pods in the `<rack>-<app>` namespace as JSON via kubectl
7. Parses pod JSON with an inline Python script to classify pods (unhealthy, not-ready, new, healthy)
8. For each non-healthy pod (or all pods if `--all`): collects current logs, previous container logs, and Kubernetes events
9. Renders output in the selected mode: terminal (full color), summary (table), or json

## Service and Resource Overview

Before diving into individual process logs, the script shows a high-level overview of your app's services and resources. This is the first thing you see and answers the question "what's actually happening with my deploy?"

### Service Status

Shows the rollout status of each service in your app:

```
SERVICE STATUS
------------------------------------------------------------------------------
  web       1/1 processes ready                                    [RUNNING]
  worker    0/1 processes ready                                    [STALLED]
    Deploy timed out -- processes did not become healthy before the deadline
    Tip: check process logs below for crash details or health check failures
------------------------------------------------------------------------------
```

Possible statuses:

| Status | Meaning |
|--------|---------|
| **RUNNING** | All processes are up and healthy |
| **DEPLOYING** | New processes are being rolled out |
| **STALLED** | Deploy is stuck -- processes are not becoming healthy |
| **SCALED DOWN** | Service has 0 desired processes |

When a service has a port configured but no processes are passing health checks, you'll also see:

```
    Not receiving traffic -- no processes passing health checks yet
    Check health.path in convox.yml matches a responding endpoint
```

Agent-type services (one process per node) are labeled accordingly.

### Resource Status

If your app uses containerized resources (postgres, redis, etc.), their health is shown:

```
RESOURCE STATUS
------------------------------------------------------------------------------
  postgres    1/1 running                                              [OK]
  redis       0/1 running                                           [DOWN]
    Services depending on this resource may fail to connect
------------------------------------------------------------------------------
```

This helps catch the common case where a service is failing because a backing resource is down, not because of a problem in your code.

### Service Events

Warning-level events from the deploy infrastructure are shown when present. These are events you would not otherwise see in `convox logs` or in the per-process output:

```
SERVICE EVENTS
------------------------------------------------------------------------------
  worker  Could not create new processes
    Error creating: pods "worker-abc-123" is forbidden: exceeded quota
  worker  Failed to pull the container image -- check build output and registry access
    Failed to pull image "myorg/worker:bad-tag": rpc error: code = NotFound
------------------------------------------------------------------------------
```

Common events and what they mean:

| Event | What to check |
|-------|---------------|
| Could not create new processes | Cluster may be out of capacity; check resource quotas |
| Could not schedule process | Not enough CPU/memory in the cluster; adjust `scale.cpu` or `scale.memory` in convox.yml |
| Failed to pull the container image | Build may have failed or image tag is wrong; check `convox builds` |
| Process ran out of memory | Increase `scale.memory` in convox.yml |
| Failed to mount volume | Check volume configuration in convox.yml |
| Deploy timed out | Processes did not become healthy in time; check health check settings and process logs |

### JSON output

In JSON mode, service and resource data is included in the top-level output:

```bash
./convox-deploy-debug -r prod -a myapp -o json | jq '.services'
```

```json
{
  "services": [
    {
      "name": "web",
      "desired": 2,
      "ready": 2,
      "available": 2,
      "status": "running",
      "stallMessage": "",
      "receivingTraffic": true,
      "events": []
    }
  ],
  "resources": [
    {
      "name": "postgres",
      "desired": 1,
      "ready": 1,
      "available": 1,
      "status": "running",
      "receivingTraffic": null
    }
  ],
  "pods": [...]
}
```

Useful jq filters:

```bash
# Services that are not running
./convox-deploy-debug -r prod -a myapp -o json | jq '.services[] | select(.status != "running")'

# Resources that are down
./convox-deploy-debug -r prod -a myapp -o json | jq '.resources[] | select(.ready == 0)'

# All warning events grouped by service
./convox-deploy-debug -r prod -a myapp -o json | jq '.services[] | select(.events | length > 0) | {name, events}'
```

## Test App

A sample two-service app is included in `test-app/` for validating the debug tool. It contains one healthy service and one that deliberately crashes, simulating the most common deploy failure pattern.

### Services

| Service | Behavior | Expected outcome |
|---------|----------|-----------------|
| **web** | Express app, returns 200 on `/health` | Comes up healthy, passes health checks |
| **worker** | Express app, logs startup messages, then crashes after 3s with a simulated database connection error | Enters CrashLoopBackOff, never passes health checks |

### Deploying the test app

```bash
# Create an app on your rack (one-time)
convox apps create test-debug --rack <rack>

# Deploy from the test-app directory
cd test-app
convox deploy --rack <rack> --app test-debug
```

### Running the debug tool against it

In another terminal while the deploy is in progress (or after it stalls):

```bash
# Easiest: interactive guided mode (picks rack, configures kubectl, picks app)
./convox-deploy-debug

# With service discovery from convox.yml
./convox-deploy-debug -r <rack> -a test-debug -y test-app/convox.yml

# Summary mode for quick triage
./convox-deploy-debug -r <rack> -a test-debug -o summary

# JSON output
./convox-deploy-debug -r <rack> -a test-debug -o json | jq .
```

### Expected output (terminal mode)

Below is representative output you should see after deploying the test app. The web service comes up healthy. The worker service crashes on startup and enters CrashLoopBackOff.

```
SERVICE STATUS
------------------------------------------------------------------------------
  web       1/1 processes ready                                    [RUNNING]
  worker    0/1 processes ready                                    [STALLED]
    Deploy timed out -- processes did not become healthy before the deadline
    Tip: check process logs below for crash details or health check failures
------------------------------------------------------------------------------

SERVICE EVENTS
------------------------------------------------------------------------------
  worker  Process is crash-looping on startup -- see logs below
    Back-off restarting failed container worker in pod worker-6f8b9c-x4z2k
------------------------------------------------------------------------------

CONVOX DEPLOY DEBUG  v1.2.0
Rack: <rack>  App: test-debug  Namespace: <rack>-test-debug
Time: 2026-03-16T12:00:00Z  Age threshold: 300s
Target pods: 1
------------------------------------------------------------------------------

[X] Pod 1/1: worker-6f8b9c-x4z2k
    Service: worker  Phase: Running  Ready: false  Age: 45s  Restarts: 3
    State: CrashLoopBackOff

    --- Events ---
    2026-...  Warning  BackOff   Back-off restarting failed container worker...
    2026-...  Warning  Unhealthy Readiness probe failed: HTTP probe failed...

    --- Logs (tail 200) ---
    worker service starting up...
    worker: connecting to database...
    worker: running migrations...
    worker service listening on port 4000 (will crash shortly)
    worker: FATAL - failed to connect to database at DB_HOST:5432
    worker: error: connection refused (ECONNREFUSED)
    worker: shutting down

    --- Previous Container Logs (crashed) ---
    worker service starting up...
    worker: connecting to database...
    worker: running migrations...
    worker service listening on port 4000 (will crash shortly)
    worker: FATAL - failed to connect to database at DB_HOST:5432
    worker: error: connection refused (ECONNREFUSED)
    worker: shutting down
------------------------------------------------------------------------------

Legend:  [X] Unhealthy  [!] Not Ready  [*] New  [+] Healthy
```

### Expected output (summary mode)

```
SERVICE STATUS
------------------------------------------------------------------------------
  web       1/1 processes ready                                    [RUNNING]
  worker    0/1 processes ready                                    [STALLED]
    Deploy timed out -- processes did not become healthy before the deadline
------------------------------------------------------------------------------

Use terminal mode (-o terminal) for full process logs.

Deploy Debug Summary  <rack>/test-debug  2026-03-16T12:00:00Z
------------------------------------------------------------------------------
POD                                           SERVICE    STATUS       READY  RESTARTS DETAIL
------------------------------------------------------------------------------
worker-6f8b9c-x4z2k                          worker     Running(45s) false  3        CrashLoopBackOff
------------------------------------------------------------------------------

Use terminal mode (-o terminal) for full logs.
```

### Expected output (JSON mode)

```bash
./convox-deploy-debug -r <rack> -a test-debug -o json | jq .
```

```json
{
  "namespace": "<rack>-test-debug",
  "rack": "<rack>",
  "app": "test-debug",
  "timestamp": "2026-03-16T12:00:00Z",
  "services": [
    {
      "name": "web",
      "desired": 1,
      "ready": 1,
      "available": 1,
      "status": "running",
      "stallMessage": "",
      "receivingTraffic": true,
      "events": []
    },
    {
      "name": "worker",
      "desired": 1,
      "ready": 0,
      "available": 0,
      "status": "stalled",
      "stallMessage": "Deploy timed out -- processes did not become healthy before the deadline",
      "receivingTraffic": false,
      "events": [
        {
          "service": "worker",
          "time": "2026-03-16T12:00:00Z",
          "reason": "BackOff",
          "message": "Process is crash-looping on startup -- see logs below",
          "raw": "Back-off restarting failed container worker in pod worker-6f8b9c-x4z2k"
        }
      ]
    }
  ],
  "resources": [],
  "pods": [
    {
      "name": "worker-6f8b9c-x4z2k",
      "service": "worker",
      "phase": "Running",
      "ready": false,
      "ageSeconds": 45,
      "restarts": 3,
      "classification": "not-ready",
      "stateDetail": "CrashLoopBackOff",
      "logs": "worker service starting up...\nworker: connecting to database...\nworker: running migrations...\nworker service listening on port 4000 (will crash shortly)\nworker: FATAL - failed to connect to database at DB_HOST:5432\nworker: error: connection refused (ECONNREFUSED)\nworker: shutting down",
      "previousLogs": "worker service starting up...\n...",
      "events": "..."
    }
  ]
}
```

### What this validates

- **Service overview** -- Confirms the tool correctly identifies `web` as running and `worker` as stalled
- **Traffic routing** -- Confirms the tool detects that `worker` is not receiving traffic
- **Deploy events** -- Confirms the tool surfaces CrashLoopBackOff and health check failure events from the deployment infrastructure, not just from individual pods
- **Pre-healthcheck logs** -- The worker's startup output ("connecting to database...", "FATAL - failed to connect...") is captured even though `convox logs` would show nothing (health checks never pass)
- **Previous container logs** -- Crash history from prior restart cycles is captured
- **Pod classification** -- The worker pod is correctly classified as not-ready/unhealthy
- **All output modes** -- Terminal, summary, and JSON all render correctly

## Version History

### v1.2.0

- Added interactive guided mode (`--setup` or no arguments): walks through dependency checks, rack selection, kubectl configuration, and app selection with numbered menus
- Dependency checker provides platform-specific install instructions for `convox`, `kubectl`, and `python3`
- Automatic kubectl configuration via `convox rack kubeconfig` during interactive setup
- Prints equivalent CLI command after wizard so users can skip it next time
- Added service rollout overview: per-service status (running, deploying, stalled) shown before pod details
- Added resource health check: containerized resource status (postgres, redis, etc.) shown when present
- Added service-level deploy events: warning events from the deploy infrastructure (image pull failures, scheduling failures, quota exceeded, etc.) translated to actionable Convox-friendly messages
- Added traffic routing detection: flags services with ports that have no processes passing health checks
- Added agent (DaemonSet) service support in the overview
- JSON output now includes top-level `services` and `resources` arrays alongside `pods`
- Added `test-app/` sample application for validating the debug tool

### v1.1.0

- Added `--repo` flag for fetching convox.yml from public GitHub/GitLab/Bitbucket repos
- Added `--branch` and `--manifest` flags for repo-based manifest fetching
- Added `--convox-yml` support for raw URLs
- Added `--describe` flag for full pod describe output
- Added `--kubeconfig` and `--context` flags for cluster targeting
- Added `--debug` flag for troubleshooting the script itself
- Added argument validation guards for all flags that take values
- Added `python3` dependency check at startup
- Added `--request-timeout=10s` to all kubectl calls to prevent hangs
- Added init container diagnostics in all output modes (terminal, summary, json)
- Init container log collection now discovers all init containers dynamically
- JSON output now uses Python's `json.dumps()` for correct escaping of all control characters
- Service list passed to Python classifier via temp file instead of shell interpolation
- Pod age calculation handles timestamp parse failures gracefully instead of silently defaulting to 0
- Pod count uses `grep -c .` instead of `wc -l` to avoid off-by-one
- Added `--` separator in kubectl calls to prevent pod names from being interpreted as flags

### v1.0.0

- Initial release
- Terminal, summary, and JSON output modes
- Pod classification: unhealthy, not-ready, new, healthy
- Service discovery from convox.yml (yq with grep fallback)
- Init container issue detection
- Previous container log collection for crash debugging
- Color auto-detection with `--no-color` override
