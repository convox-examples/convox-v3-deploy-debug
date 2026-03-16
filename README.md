# convox-v3-deploy-debug

Diagnostic tool for capturing pre-healthcheck service logs during Convox deployments.

`convox logs` does not surface service output until processes pass their health check. Most deploy failures happen before that point. This script bridges the gap by querying the cluster directly using Convox's namespace and label conventions.

## Quick Start

The easiest way to get started is the interactive guided mode. It checks your dependencies, lets you pick a rack and app from a menu, and configures cluster access for you:

```bash
# Download and make executable
chmod +x convox-v3-deploy-debug

# Run with no arguments to start the guided wizard
./convox-v3-deploy-debug
```

The wizard will:

1. Check that `convox`, `kubectl`, and `python3` are installed (with install instructions if anything is missing)
2. Show your available racks and let you pick one
3. Configure cluster access for that rack (temporary, session only)
4. List your apps and let you pick one to debug
5. Run the diagnostics

If you already know your rack and app name, you can skip the wizard:

```bash
./convox-v3-deploy-debug --rack production --app myapp
```

## Requirements

- `bash` 4.0+
- `convox` CLI (logged in to your console)
- `kubectl` (the interactive wizard configures this for you via `convox rack kubeconfig`)
- `python3` 3.6+ (used for JSON parsing)
- `curl` (only needed for `--repo` and remote `--convox-yml` URL features)
- `yq` v4+ (optional, improves convox.yml parsing; grep fallback exists)

If you run the script with no arguments, it checks all of these and gives you platform-specific install instructions for anything missing.

## Usage Reference

```
convox-v3-deploy-debug                           # Interactive guided mode
convox-v3-deploy-debug --setup                   # Same thing, explicit flag
convox-v3-deploy-debug --rack <rack> --app <app> [OPTIONS]
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
| `-A, --age <seconds>` | Process age threshold in seconds (default: 300) |
| `--all` | Include all processes, not just unhealthy/new ones |
| `-c, --checks <name>` | Run only specific diagnostic checks (repeatable, see below) |

### Diagnostic Checks (`-c`)

By default all three checks run. Use `-c` to run only specific ones. The flag is repeatable -- combine as needed.

| Check | What it does |
|-------|-------------|
| `overview` | Service rollout status, resource health, and deploy events |
| `init` | Detects processes stuck on init containers |
| `services` | Per-process logs, cluster events, and process classification |

```bash
# Run only the process check
./convox-v3-deploy-debug -r production -a myapp -c services

# Run rollout overview and init container checks together
./convox-v3-deploy-debug -r production -a myapp -c overview -c init

# All three (default behavior, same as omitting -c)
./convox-v3-deploy-debug -r production -a myapp -c overview -c init -c services
```

### Output

| Flag | Description |
|------|-------------|
| `-o, --output <mode>` | Output mode: `terminal`, `summary`, `json` (default: `terminal`) |
| `-n, --lines <count>` | Number of log lines per process (default: 200) |
| `--no-events` | Skip cluster events |
| `--no-previous` | Skip logs from previous crashes |
| `--describe` | Include full process detail (k8s: pod describe) |
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

Full diagnostic output with color-coded process status, logs, events, and previous crash logs. Best for interactive debugging.

### summary

Compact table view showing process name, service, status, readiness, restart count, and state detail. Good for quick triage when you need to identify which processes are failing.

### json

Machine-readable JSON output with all process data, logs, events, and classification. Pipe to `jq` for filtering or integrate into CI/CD pipelines.

```bash
# Get just the unhealthy processes
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.pods[] | select(.classification == "unhealthy")'

# Get process names and their state
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.pods[] | {name, classification, stateDetail}'
```

## Process Classification

Each process (k8s: pod) is classified into one of four categories:

| Classification | Meaning | Terminal Icon |
|---------------|---------|---------------|
| **unhealthy** | Process is not running (e.g., `Pending`, `Failed`, crash loop) | red `●` |
| **not-ready** | Process is running but has not passed health checks | yellow `●` |
| **new** | Process is running and ready, but younger than the age threshold | cyan `●` |
| **healthy** | Process is running, ready, and older than the age threshold | green `●` |

By default, only unhealthy, not-ready, and new processes are shown. Use `--all` to include healthy processes.

### Actionable Hints

When a process is in a known failure state, the tool shows a `hint` line with a plain-language explanation and what to do about it. These cover the most common deploy failures:

| Detail | Hint |
|--------|------|
| `CrashLoopBackOff` | Process is crash-looping on startup -- check the logs below for the error |
| `ImagePullBackOff` | Failed to pull the container image -- check that the build succeeded and the image tag exists |
| `ErrImagePull` | Failed to pull the container image -- check registry access and image name |
| `CreateContainerConfigError` | Container config is invalid -- check environment variables and secrets (missing env var or secret reference?) |
| `RunContainerError` | Container failed to start -- check the command in convox.yml and that the entrypoint exists |
| `OOMKilled` | Process ran out of memory and was killed -- increase scale.memory in convox.yml |
| `Completed` | Process exited successfully but is not expected to stop -- check your command does not exit on its own |
| `Error` | Process exited with an error -- check the logs below |
| `ContainerCannotRun` | Container cannot run -- check that the Dockerfile CMD or convox.yml command is valid |
| `InvalidImageName` | Image name is invalid -- check build configuration |
| `Unschedulable` | Not enough resources in the cluster to place this process -- check scale.cpu and scale.memory in convox.yml |
| `Pending` (phase) | Process is waiting to be scheduled -- this usually means the cluster is low on resources |

Hints also work for init container failures (e.g., `init:CrashLoopBackOff`).

In JSON mode, hints appear as a `hint` field on each pod object.

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
./convox-v3-deploy-debug -r production -a myapp

# Target a single service
./convox-v3-deploy-debug -r production -a myapp -s web

# Auto-discover services from local convox.yml
./convox-v3-deploy-debug -r production -a myapp -y ./convox.yml

# Auto-discover services from a GitHub repo
./convox-v3-deploy-debug -r production -a myapp --repo github.com/myorg/myapp

# Repo on a feature branch with a non-default manifest path
./convox-v3-deploy-debug -r production -a myapp \
  --repo github.com/myorg/myapp --branch staging --manifest deploy/convox.yml

# Auto-discover from a raw URL directly
./convox-v3-deploy-debug -r production -a myapp \
  -y https://raw.githubusercontent.com/myorg/myapp/main/convox.yml

# Wider time window, write to file
./convox-v3-deploy-debug -r production -a myapp -A 600 > deploy-debug.txt

# JSON output for programmatic consumption
./convox-v3-deploy-debug -r production -a myapp -o json > debug.json

# Summary mode for quick triage
./convox-v3-deploy-debug -r production -a myapp -o summary

# Run only the rollout overview check
./convox-v3-deploy-debug -r production -a myapp -c overview

# Run process diagnostics and init checks together
./convox-v3-deploy-debug -r production -a myapp -c services -c init

# Use a specific kubeconfig and context
./convox-v3-deploy-debug -r production -a myapp --kubeconfig ~/.kube/prod --context prod-cluster

# Include full process detail (k8s: pod describe)
./convox-v3-deploy-debug -r production -a myapp --describe

# Show all processes including healthy ones
./convox-v3-deploy-debug -r production -a myapp --all
```

## Interactive Guided Mode

Running the script with no arguments (or with `--setup`) starts an interactive wizard designed for users who may not be familiar with Kubernetes. The wizard handles the entire setup process:

```
$ ./convox-v3-deploy-debug

  convox-v3-deploy-debug v1.2.0
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Step 1 of 5  Dependencies

    ✓ convox CLI
    ✓ kubectl
    ✓ python3

  Step 2 of 5  Select Rack

  > Fetching available racks...
    Current rack: production

  Use current rack production? [Y/n] y
  > Selected rack: production

  Step 3 of 5  Cluster Access

  > Setting up temporary cluster access for production...
    Running: convox rack kubeconfig --rack production

    ✓ Cluster access configured (session only)
  > Testing cluster connectivity...
    ✓ Connected to cluster

  Step 4 of 5  Select App

  > Fetching apps on rack production...

  Select an app to debug:

     1  myapp
     2  api-gateway
     3  worker-pool

    Pick [1-3]: 1
  > Selected app: myapp

  Step 5 of 5  Service Discovery (optional)

    A convox.yml helps discover your service names for better output.
    The tool works fine without it.

  Do you have a convox.yml to point to? [y/N] n

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Ready to run diagnostics

    Rack      production
    App       myapp

  ──────────────────────────────────────────────────────────────────────────
  Quick-run (skip this wizard next time):
    ./convox-v3-deploy-debug --rack production --app myapp

  Run specific checks only (-c, repeatable, combine as needed):
    -c services    process logs and classification
    -c overview    service rollout status and events
    -c init        init container detection

    Example: ./convox-v3-deploy-debug --rack production --app myapp -c overview -c services
  ──────────────────────────────────────────────────────────────────────────

  Run diagnostics now? [Y/n] y
```

After you confirm, the tool runs the full diagnostics automatically. It also prints the equivalent CLI command so you can skip the wizard next time.

## How It Works

1. Parses CLI args, validates required flags (`--rack`, `--app`) and dependencies (`kubectl`, `python3`)
2. If `--repo` or a URL-based `--convox-yml` is provided, fetches the manifest via curl to a temp file (cleaned up on exit)
3. If a convox.yml is available (local or fetched), discovers service names using yq or grep fallback
4. **Service rollout overview** (`-c overview`) -- queries all services in the app to show a per-service status summary (running, deploying, stalled), resource health, and deploy-level events (see [Service and Resource Overview](#service-and-resource-overview) below)
5. **Init container check** (`-c init`) -- checks for processes stuck in `Init:` state and captures init container logs (all init containers, not just Convox's)
6. **Process diagnostics** (`-c services`) -- fetches all processes in the `<rack>-<app>` namespace as JSON, classifies them (unhealthy, not-ready, new, healthy), and collects current logs, previous crash logs, and cluster events for each non-healthy process (or all processes if `--all`)
7. Renders output in the selected mode: terminal (full color), summary (table), or json

## Service and Resource Overview

Before diving into individual service logs, the script shows a high-level overview of your app's services and resources. This is the first thing you see and answers the question "what's actually happening with my deploy?"

### Service Status

Shows the rollout status of each service in your app:

```
  SERVICE STATUS
  ──────────────────────────────────────────────────────────────────────────
  ● web  1/1 process ready  RUNNING
  ● worker  0/1 process ready  STALLED
      Deploy timed out -- processes did not become healthy before the deadline
      Check service logs below for crash details or health check failures
  ──────────────────────────────────────────────────────────────────────────
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
  ──────────────────────────────────────────────────────────────────────────
  ● postgres  1/1 running  OK
  ● redis  0/1 running  DOWN
      Services depending on this resource may fail to connect
  ──────────────────────────────────────────────────────────────────────────
```

This helps catch the common case where a service is failing because a backing resource is down, not because of a problem in your code.

### Service Events

Warning-level events from the deploy infrastructure are shown when present. These are events you would not otherwise see in `convox logs` or in the per-process output:

```
  SERVICE EVENTS
  ──────────────────────────────────────────────────────────────────────────
  ! worker  Could not create new processes
      Error creating: pods "worker-abc-123" is forbidden: exceeded quota
  ! worker  Failed to pull the service image -- check build output and registry access
      Failed to pull image "myorg/worker:bad-tag": rpc error: code = NotFound
  ──────────────────────────────────────────────────────────────────────────
```

Common events and what they mean:

| Event | What to check |
|-------|---------------|
| Could not create new processes | Cluster may be out of capacity; check resource quotas |
| Could not place process | Not enough CPU/memory in the cluster; adjust `scale.cpu` or `scale.memory` in convox.yml |
| Failed to pull the service image | Build may have failed or image tag is wrong; check `convox builds` |
| Process ran out of memory | Increase `scale.memory` in convox.yml |
| Failed to mount volume | Check volumeOptions in convox.yml |
| Deploy timed out | Processes did not become healthy in time; check health check settings and service logs |

### JSON output

In JSON mode, service and resource data is included in the top-level output:

```bash
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.services'
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
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.services[] | select(.status != "running")'

# Resources that are down
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.resources[] | select(.ready == 0)'

# All warning events grouped by service
./convox-v3-deploy-debug -r prod -a myapp -o json | jq '.services[] | select(.events | length > 0) | {name, events}'
```

## Test App

A sample two-service app is included in `test-app/` for validating the debug tool. It contains one healthy service and one that deliberately crashes, simulating the most common deploy failure pattern.

### Services

| Service | Behavior | Expected outcome |
|---------|----------|-----------------|
| **web** | Express app, returns 200 on `/health` | Comes up healthy, passes health checks |
| **worker** | Express app, logs startup messages, then crashes after 3s with a simulated database connection error | Enters a crash loop, never passes health checks |

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
# Easiest: interactive guided mode (picks rack, configures cluster access, picks app)
./convox-v3-deploy-debug

# With service discovery from convox.yml
./convox-v3-deploy-debug -r <rack> -a test-debug -y test-app/convox.yml

# Summary mode for quick triage
./convox-v3-deploy-debug -r <rack> -a test-debug -o summary

# Just the rollout overview
./convox-v3-deploy-debug -r <rack> -a test-debug -c overview

# JSON output
./convox-v3-deploy-debug -r <rack> -a test-debug -o json | jq .
```

### Expected output (terminal mode)

Below is representative output you should see after deploying the test app. The web service comes up healthy. The worker service crashes on startup and enters a crash loop.

```
  SERVICE STATUS
  ──────────────────────────────────────────────────────────────────────────
  ● web  1/1 process ready  RUNNING
  ● worker  0/1 process ready  STALLED
      Deploy timed out -- processes did not become healthy before the deadline
      Check service logs below for crash details or health check failures
  ──────────────────────────────────────────────────────────────────────────

  SERVICE EVENTS
  ──────────────────────────────────────────────────────────────────────────
  ! worker  Process is crash-looping on startup -- see logs below
      Back-off restarting failed container worker in pod worker-6f8b9c-x4z2k
  ──────────────────────────────────────────────────────────────────────────

  CONVOX V3 DEPLOY DEBUG  v1.2.0
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    Rack  <rack>    App  test-debug    namespace: <rack>-test-debug
    Time  2026-03-16T12:00:00Z    Age threshold  300s    Processes  1

  ──────────────────────────────────────────────────────────────────────────

  ● worker  not-ready
    process: worker-6f8b9c-x4z2k
    state: Running    ready: false    age: 45s    restarts: 3
    detail:  CrashLoopBackOff
    hint:    Process is crash-looping on startup -- check the logs below for the error

    ─── cluster events ───
      2026-...  Warning  BackOff   Back-off restarting failed container worker...
      2026-...  Warning  Unhealthy Readiness probe failed: HTTP probe failed...

    ─── service logs (last 200 lines) ───
      worker service starting up...
      worker: connecting to database...
      worker: running migrations...
      worker service listening on port 4000 (will crash shortly)
      worker: FATAL - failed to connect to database at DB_HOST:5432
      worker: error: connection refused (ECONNREFUSED)
      worker: shutting down

    ─── previous crash logs ───
      worker service starting up...
      worker: connecting to database...
      worker: running migrations...
      worker service listening on port 4000 (will crash shortly)
      worker: FATAL - failed to connect to database at DB_HOST:5432
      worker: error: connection refused (ECONNREFUSED)
      worker: shutting down
  ──────────────────────────────────────────────────────────────────────────

  ● Unhealthy   ● Not Ready   ● New   ● Healthy
```

### Expected output (summary mode)

```
  SERVICE STATUS
  ──────────────────────────────────────────────────────────────────────────
  ● web  1/1 process ready  RUNNING
  ● worker  0/1 process ready  STALLED
      Deploy timed out -- processes did not become healthy before the deadline
  ──────────────────────────────────────────────────────────────────────────

  Use terminal mode (-o terminal) for full service logs.

  Deploy Debug Summary  <rack>/test-debug  2026-03-16T12:00:00Z
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  PROCESS                                        SERVICE    STATUS       READY  RESTARTS DETAIL
  ──────────────────────────────────────────────────────────────────────────
  ● worker-6f8b9c-x4z2k                          worker     Running(45s) false  3        CrashLoopBackOff
    Process is crash-looping on startup -- check the logs below for the error
  ──────────────────────────────────────────────────────────────────────────

  Use terminal mode (-o terminal) for full service logs.
```

### Expected output (JSON mode)

```bash
./convox-v3-deploy-debug -r <rack> -a test-debug -o json | jq .
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
      "hint": "Process is crash-looping on startup -- check the logs below for the error",
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
- **Deploy events** -- Confirms the tool surfaces crash loop and health check failure events from the deploy infrastructure, not just from individual processes
- **Pre-healthcheck logs** -- The worker's startup output ("connecting to database...", "FATAL - failed to connect...") is captured even though `convox logs` would show nothing (health checks never pass)
- **Previous crash logs** -- Crash history from prior restart cycles is captured
- **Process classification** -- The worker process is correctly classified as not-ready
- **All output modes** -- Terminal, summary, and JSON all render correctly
- **Selective checks** -- You can run `./convox-v3-deploy-debug -r <rack> -a test-debug -c overview` to get just the rollout status without the full logs
