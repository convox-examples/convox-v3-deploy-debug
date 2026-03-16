# convox-v3-deploy-debug test app

Sample two-service app for validating the `convox-v3-deploy-debug` tool. One service is healthy, one deliberately crashes on startup. This simulates the most common deploy failure pattern where `convox logs` shows nothing because health checks never pass.

## Services

| Service | Port | Health check | Behavior |
|---------|------|-------------|----------|
| **web** | 3000 | `GET /health` returns 200 | Healthy Express app. Starts up, passes health checks, serves traffic. |
| **worker** | 4000 | `GET /health` returns 503 | Broken Express app. Logs startup messages, then crashes after 3 seconds with a simulated database connection failure (`ECONNREFUSED`). |

The worker's crash pattern is realistic: it starts, attempts to connect to a database, logs the failure, and exits. This produces CrashLoopBackOff in Kubernetes, which is exactly the scenario the debug tool is designed to diagnose.

## Setup

### Create the app

```bash
convox apps create test-debug --rack <rack>
```

### Deploy

```bash
cd test-app
convox deploy --rack <rack> --app test-debug
```

The deploy will partially succeed (web comes up) and partially fail (worker enters CrashLoopBackOff). Convox will eventually time out the deploy.

## Running the debug tool

Run from the repo root (one directory up from `test-app/`):

```bash
# Easiest: interactive guided mode (picks rack, configures kubectl, picks app)
./convox-v3-deploy-debug

# Full terminal output with service discovery
./convox-v3-deploy-debug -r <rack> -a test-debug -y test-app/convox.yml

# Quick triage with summary mode
./convox-v3-deploy-debug -r <rack> -a test-debug -o summary

# JSON output for scripting
./convox-v3-deploy-debug -r <rack> -a test-debug -o json | jq .

# Target just the broken service
./convox-v3-deploy-debug -r <rack> -a test-debug -s worker

# Include all pods (even the healthy web service)
./convox-v3-deploy-debug -r <rack> -a test-debug --all

# Include full pod describe output
./convox-v3-deploy-debug -r <rack> -a test-debug --describe
```

## What you should see

### Service overview

The top of the output shows the big picture:

```
SERVICE STATUS
------------------------------------------------------------------------------
  web       1/1 processes ready                                    [RUNNING]
  worker    0/1 processes ready                                    [STALLED]
    Deploy timed out -- processes did not become healthy before the deadline
    Not receiving traffic -- no processes passing health checks yet
    Check health.path in convox.yml matches a responding endpoint
    Tip: check process logs below for crash details or health check failures
------------------------------------------------------------------------------
```

- `web` is **RUNNING** -- healthy, processes ready, receiving traffic
- `worker` is **STALLED** -- no processes are ready, deploy has timed out

### Service events

Deploy-level warning events surface problems that `convox logs` does not show:

```
SERVICE EVENTS
------------------------------------------------------------------------------
  worker  Process is crash-looping on startup -- see logs below
    Back-off restarting failed container worker in pod worker-6f8b9c-x4z2k
------------------------------------------------------------------------------
```

### Process logs

The per-process section captures the worker's crash output:

```
[X] Pod 1/1: worker-6f8b9c-x4z2k
    Service: worker  Phase: Running  Ready: false  Age: 45s  Restarts: 3
    State: CrashLoopBackOff

    --- Logs (tail 200) ---
    worker service starting up...
    worker: connecting to database...
    worker: running migrations...
    worker service listening on port 4000 (will crash shortly)
    worker: FATAL - failed to connect to database at DB_HOST:5432
    worker: error: connection refused (ECONNREFUSED)
    worker: shutting down
```

These logs are the key value of the tool: they show exactly why the process is failing, even though `convox logs` returns nothing.

### Previous container logs

For crash-looping processes, the output from the previous crashed container is also captured:

```
    --- Previous Container Logs (crashed) ---
    worker service starting up...
    worker: connecting to database...
    ...
```

## Validation checklist

After deploying the test app and running the debug tool, verify:

### Interactive mode
- [ ] Running `./convox-v3-deploy-debug` with no arguments starts the guided wizard
- [ ] Dependency check reports `[ok]` for `convox`, `kubectl`, and `python3`
- [ ] Rack selection shows available racks and lets you pick one
- [ ] kubectl configuration step runs `convox rack kubeconfig` successfully
- [ ] App selection lists apps on the selected rack
- [ ] Confirmation step prints the equivalent CLI command for next time
- [ ] Diagnostics run successfully after confirming

### Diagnostic output
- [ ] Service overview shows `web` as RUNNING and `worker` as STALLED or DEPLOYING
- [ ] Traffic routing correctly reports `worker` is not receiving traffic
- [ ] Service events section shows CrashLoopBackOff or health check warning events
- [ ] Worker pod logs contain the startup and crash output
- [ ] Previous container logs are captured for the worker
- [ ] Web pod does NOT appear in output (it's healthy, filtered out by default)
- [ ] Web pod DOES appear with `--all` flag
- [ ] Summary mode shows a condensed table with correct status
- [ ] JSON output parses cleanly with `jq .`
- [ ] JSON output contains `services`, `resources`, and `pods` at the top level
- [ ] `--no-color` and piped output have no ANSI escape codes

## Cleanup

```bash
convox apps delete test-debug --rack <rack>
```
