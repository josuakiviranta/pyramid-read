# BALANCER - FRAME OF REFERENCE

This is a frame of reference / lookup table for Balancer.

## DESCRIPTION

Balancer is a small data broker network that lets users sell their local computer data to companies.

It consists of three different actors with three different codebases:
1. Local computer user with `balancer-seller-cli`
2. Balancer broker node with `balancer-server`
3. Balancer customer company with `balancer-buyer-cli`

---

## Repository Layout

```
proto/                          # .proto source files (shared across all three modules)
src/
  sandboxed-file-validator/     # shared sandbox package: Goja + Starlark runtimes, approximate token counting
  balancer-server/              # broker server — module: github.com/balancer/balancer-server
    cmd/server/                 #   relay server binary
    cmd/arbitration/            #   arbitration worker binary (separate binary, same module)
    internal/                   #   server internals
    db/migrations/              #   SQLite migration files
    proto/                      #   generated Go gRPC stubs (protoc output, checked in)
  balancer-seller-cli/          # seller CLI — module: github.com/balancer/balancer-seller-cli
    cmd/                        #   Cobra root command
    internal/                   #   CLI internals
  balancer-buyer-cli/           # buyer CLI — module: github.com/balancer/balancer-buyer-cli
    cmd/                        #   Cobra root command
    internal/                   #   CLI internals
specs/                          # specification documents
```

### Go Module Paths

| Module | Path |
|---|---|
| broker server + arbitration worker | `github.com/balancer/balancer-server` |
| seller CLI | `github.com/balancer/balancer-seller-cli` |
| buyer CLI | `github.com/balancer/balancer-buyer-cli` |
| shared sandbox | `github.com/balancer/sandboxed-file-validator` |

### Shared Dependencies

Both CLIs and the server reference the shared sandbox package and the generated proto stubs via
Go `replace` directives in their `go.mod` — no copying, single source of truth:

```
# in balancer-seller-cli/go.mod and balancer-buyer-cli/go.mod:
require github.com/balancer/sandboxed-file-validator v0.0.0
replace github.com/balancer/sandboxed-file-validator => ../../src/sandboxed-file-validator

require github.com/balancer/balancer-server v0.0.0
replace github.com/balancer/balancer-server => ../../src/balancer-server

# in balancer-server/go.mod:
require github.com/balancer/sandboxed-file-validator v0.0.0
replace github.com/balancer/sandboxed-file-validator => ../../src/sandboxed-file-validator
```

The `balancer-server` replace gives CLIs access to the generated proto stubs at
`src/balancer-server/proto/` without publishing a separate module.

---

## Data Flow

See [data-flow.md](./data-flow.md) for the full data flow reference — normal flow, arbitration flow,
stage-by-stage description, and key properties.

## Balancer-seller-cli

CLI tool for data sellers (local computer users). See [balancer-seller-cli.md](./balancer-seller-cli.md) for full spec.
See [balancer-seller-cli-implementation-plan.md](./balancer-seller-cli-implementation-plan.md) for implementation plan.

- Registers seller via **Firebase Authentication** (Google OAuth device flow); **Stripe Connect** (Accounts v2) onboarding runs immediately after — both done once on first launch, auto-triggered if no credentials found
- Runs a background **heartbeat daemon** that polls server for pending requests (default: once per day, configurable; system notifications on new requests)
- Lets seller review requests: company name (Google email), company message, and full evaluation script body — all human-readable before any action is taken
- AI-native — `requests analyze` outputs message vs eval script side-by-side; `--json` on all commands; `skills/balancer-seller-cli/SKILL.md` included
- Runs **built-in PII anonymisation**, then **seller custom anonymisation scripts**, then **buyer evaluation script** — sandboxed pipeline on seller's machine before anything leaves
- Seller gives final approval; can remove specific files before transfer
- Generates session key K, computes SHA-256 claim hashes, encrypts files with AES-256-GCM, streams to buyer via balancer relay
- Maintains a **sent-files registry** (`~/.config/balancer/sent-files.json`) — `files scan` skips files already sent to the same company by default; use `--include-sent` to override; registry updated only on confirmed successful transfer

## Balancer-buyer-cli

CLI tool for buying companies. See [balancer-buyer-cli.md](./balancer-buyer-cli.md) for full spec.
See [balancer-buyer-cli-implementation-plan.md](./balancer-buyer-cli-implementation-plan.md) for implementation plan.

- Registers company via **Firebase Authentication** (Google OAuth device flow); key pair generated locally
- Queries current token price from balancer-server
- Places a data request with a **budget**, **evaluation script** (JS or Starlark file), optional message, optional expiry, and optional seller blacklist
- Discovers transfers via **heartbeat daemon** (background, configurable interval, auto-receives + system notification) or manually via `transfers list`
- Receives encrypted data stream from balancer-server via gRPC+TLS
- Receives K_buyer (session key encrypted with company's public key) from balancer
- Decrypts received files locally using derived session key
- Runs evaluation script on received files; **auto-confirms** if all files pass
- Can **initiate arbitration** by providing decryption key K to balancer if evaluation fails
- Receives refund of unspent budget after transfer completes
- Deduplication deferred to post-v1

## Sandboxed File Validator

Shared Go framework used by `balancer-seller-cli` (evaluation) and `balancer-server` (arbitration) to run buyer-provided scripts against files in a restricted sandbox.

- Two runtimes: **Goja** (JavaScript, 30 s timeout) and **Starlark** (Python-like, 60 M step limit)
- Scripts receive `FILE_PATH` / `FILE_NAME` globals; call `emit(true/false)` to pass/fail
- Safe library: `readFile`, `parseCSV`, `parseJSONL`, `filterRows`, `groupBy`, `stats` — no network, no env, no path traversal, fresh VM per file
- Plain-text allowlist only (`.csv` `.tsv` `.json` `.jsonl` `.txt` `.md` `.log` `.js` `.ts` `.go` `.py` `.rb` `.html` `.xml` `.yaml` `.yml` `.toml` `.star`) — binary files rejected immediately
- Approximate **token counting** via `ceil(bytes / 4)` — no external vocab or network deps
- PII stripping replaces detected patterns with typed tokens: `[EMAIL]`, `[ID]`, `[PHONE]`, `[ADDRESS]`, `[NAME]`
- Go API: `Analyze` runs a script against a file on disk; `AnalyzeContent` evaluates pre-loaded content (use after `Anonymise()` to hash the anonymised bytes, not the raw file); `Anonymise` strips PII then optionally runs a custom script
- Progress events: runtimes emit `ProgressEvent` at each pipeline phase (`PhaseChecking` → `PhaseHashing` → `PhaseEvaluating` for validation; `PhaseAnonymising` in the anonymisation path); pass `WithProgress(fn)` to observe them

See [sandboxed-file-validator.md](./sandboxed-file-validator.md) for full spec.

---

## Balancer-server

See [balancer-server.md](./balancer-server.md) for full spec.
See [balancer-server-implementation-plan.md](./balancer-server-implementation-plan.md) for implementation plan.

---

## Arbitration

See [balancer-arbitration.md](./balancer-arbitration.md) for the full arbitration spec.
See [balancer-arbitration-implementation-plan.md](./balancer-arbitration-implementation-plan.md) for the implementation plan.

- Only buyers can initiate arbitration; seller's obligation ends at delivery
- Buyer provides decryption key K — balancer decrypts its encrypted copy, verifies claim hashes, runs evaluation script, issues ruling
- Two verdicts: `buyer_wins` / `seller_wins`
- 48h window; auto-settlement if not initiated
- Arbitration worker is a separate Go binary (`cmd/arbitration/`), pure processor, no DB access
- Reputation: 100-point scale, -10 per loss, admin email alert below 80

---

## Live Cloud Server

The production balancer server runs on a GCP Compute Engine VM.

### Connection Details

| Item | Value |
|---|---|
| GCP Project | `ralph-83103` |
| VM name | `ralph-vm` |
| Zone | `europe-west1-b` |
| External IP | `35.240.3.216` *(see note below)* |
| gRPC port | `50051` |
| TLS | Self-signed cert pinned to the IP |

> **IP stability:** The external IP is `35.240.3.216` but **changes if the VM is stopped and started**. After any stop/start you must regenerate the TLS cert (see `balancer-server.md` → GCP Production Deployment) and redistribute it to CLI users.

### Getting the TLS Certificate

The certificate must be obtained from the VM and distributed to anyone using the CLIs:

```bash
# Copy cert to a convenient local path (requires gcloud + IAP access)
gcloud compute ssh ralph-vm \
  --tunnel-through-iap --project=ralph-83103 --zone=europe-west1-b \
  -- "sudo cp /etc/balancer/server.crt /tmp/server.crt && sudo chmod 644 /tmp/server.crt"

gcloud compute scp ralph-vm:/tmp/server.crt \
  ~/balancer-server.crt \
  --tunnel-through-iap --project=ralph-83103 --zone=europe-west1-b
```

### Connecting balancer-seller-cli to the Live Server

```bash
cd src/balancer-seller-cli
./balancer config set server_address 35.240.3.216:50051
./balancer config set cert_file ~/balancer-server.crt
# Verify — should return empty list with no error:
./balancer requests list
```

### Connecting balancer-buyer-cli to the Live Server

```bash
cd src/balancer-buyer-cli
./balancer-customer config set server_address 35.240.3.216:50051
./balancer-customer config set cert_file ~/balancer-server.crt
# Verify — should return empty list with no error:
./balancer-customer requests list
```

### Running E2E Tests Against the Live Server

```bash
cd tests/e2e

BALANCER_E2E_SERVER=35.240.3.216:50051 \
BALANCER_E2E_CERT=~/balancer-server.crt \
go test ./... -p 1 -v -count=1
```

`-p 1` is required — slices share server state and must run serially in remote mode. `TestSlice5_BanEnforcement` is always skipped in remote mode (requires direct DB access).

---


- Go + SQLite + gRPC/TLS + GCP Compute Engine
- **TLS (pre-launch):** self-signed cert pinned to the server's static IP, distributed with CLIs as the trusted root — **must be replaced with a real domain + Let's Encrypt cert before onboarding real users**
- Pure relay — never reads file contents, routes encrypted streams
- Token-based pricing (approximate token count, `ceil(bytes / 4)`), Stripe Connect payments (Accounts v2)
- Evaluation script registry (hashes stored as source of truth for arbitration)
- Temporary encrypted file storage per transaction (blind relay by default; decrypted only during arbitration)
- Arbitration: buyer provides decryption key, balancer runs evaluation script, issues ruling
- Seller and buyer reputation scoring (based on evaluation outcomes)
- Admin role for token price management and seller moderation
