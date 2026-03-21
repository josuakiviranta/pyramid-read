# Balancer Customer CLI Spec

## Overview

`balancer-buyer-cli` is the CLI tool for buying companies. It lets a company place data
requests, receive encrypted files from sellers via the balancer broker, run evaluation scripts
locally, and confirm or dispute transfers. Written in Go; distributed as a single binary.

---

## Tech Stack

| Concern | Choice |
|---|---|
| Language | Go |
| CLI framework | Cobra |
| Config | TOML (`~/.config/balancer-customer/config.toml`) |
| gRPC | google.golang.org/grpc |
| JS sandbox | Goja (shared `sandboxed-file-validator` package) |
| Starlark sandbox | Starlark-Go (shared `sandboxed-file-validator` package) |
| Crypto | Go stdlib (`crypto/aes`, `crypto/rsa`, `crypto/sha256`) |
| Distribution | Single binary — GoReleaser, Homebrew, apt, curl |

---

## Auth & Onboarding

Signup is triggered automatically on first launch if no credentials are found.
The full flow runs in one `balancer-customer signup` command (or auto-triggered):

1. **Firebase Authentication** (Google OAuth device flow) — user visits a URL, signs in, CLI receives Firebase ID token
2. **Key pair generation** — CLI generates an RSA-2048 (or EC P-256) key pair locally;
   private key stored at `~/.config/balancer-customer/keys/private.pem` (mode 0600)
3. **Account created on balancer-server** — server returns an API key stored locally in config

All three steps happen in one flow.

---

## Command Surface

```
balancer-customer signup                               # Firebase Auth + key pair generation (auto on first launch)
balancer-customer config show / set <key> <value>
balancer-customer account status                       # Google account, API key, key pair status, reputation

balancer-customer requests place \
    --budget <amount> \
    --price <amount> \
    --script <path.js|path.star> \
    [--message "description for sellers"] \
    [--expires <duration>] \                           # e.g. 7d, 24h — default: no expiry
    [--block-seller <seller_id>...]                    # optional; multiple flags allowed
balancer-customer requests list
balancer-customer requests show <id>
balancer-customer requests close <id>                  # closes request; no more sellers can respond

balancer-customer heartbeat start / stop / status      # background daemon: polls server, auto-receives ready transfers

balancer-customer transfers list [--request <id>]      # manually poll for arrived transfers
balancer-customer transfers show <id>
balancer-customer transfers receive <id> [--out <dir>] # decrypt + eval + auto-confirm or auto-dispute

balancer-customer audit list [--request <id>]          # transfer history, payouts, verdicts
```

All commands support `--json` for structured output (AI/pipeline-parseable).

---

## Placing a Request

```
balancer-customer requests place \
    --budget 50.00 \
    --price 0.001 \
    --script ./eval/filter-sales-data.js \
    --message "We are looking for retail sales records from 2023–2024." \
    --expires 7d \
    --block-seller seller_abc123
```

**Fields:**

| Field | Required | Description |
|---|---|---|
| `--budget` | Yes | Maximum total spend (EUR). Charged to buyer's Stripe balance at submission; remainder refunded after transfer. Never disclosed to sellers. |
| `--price` | Yes | Per-token rate offered to sellers (EUR per token). Public offer rate visible to sellers. Locked as `token_price_snapshot` at request placement. |
| `--script` | Yes | Path to JS (`.js`) or Starlark (`.star`) evaluation script. Script is uploaded to server; server hashes it — the hash is the authoritative source of truth for arbitration. |
| `--message` | No | Human-readable description shown to sellers. Helps sellers assess relevance before accepting. |
| `--expires` | No | Duration until request auto-closes (e.g. `7d`, `48h`). No expiry if omitted. |
| `--block-seller` | No | One or more seller IDs to exclude from this request. Repeatable. |

The server returns a `request_id` on success.

---

## Receiving Data

There are two ways to discover and receive incoming transfers: a background heartbeat daemon
(recommended for active buyers) and manual polling (good for CI pipelines or one-off checks).
Both methods trigger the same `transfers receive` logic when a ready transfer is found.

### Heartbeat daemon

```
balancer-customer heartbeat start
balancer-customer heartbeat stop
balancer-customer heartbeat status
```

Runs as a background process. Polls balancer-server on a configurable interval (default: 1 hour;
set `poll_interval` in config). When a transfer with status `ready` is found:
1. Runs `transfers receive` automatically for each ready transfer
2. Emits a system notification (macOS / Linux / Windows) with the transfer ID and outcome
3. Logs results to `~/.config/balancer-customer/heartbeat.log`

### Manual polling

```
balancer-customer transfers list
balancer-customer transfers list --request req_abc123
```

Output shows `transfer_id`, `status` (pending / ready / received / disputed), token count, seller ID (anonymised), and estimated cost.
Use `transfers receive <id>` to process a specific transfer.

### Receive command

```
balancer-customer transfers receive <transfer_id> [--out ./data/received/]
```

Steps executed in order:

1. **Open `ReceiveTransfer` stream** — gRPC+TLS stream delivers encrypted file chunks; `K_buyer` arrives in stream completion metadata
2. **Persist `K_buyer` bytes** atomically to `<output_dir>/<transfer_id>/.kbuyer` before decryption begins — enables retry if step 6 fails; deleted on success
3. **Decrypt `K_buyer` → K** using buyer's private key (`~/.config/balancer-customer/keys/private.pem`)
4. **Decrypt files** with K (AES-256-GCM) and write to output directory
5. **Run evaluation script** — script source read from `TransferSummary.evaluation_script` (returned by `ListTransfers`; server is source of truth); runtime selected by `evaluation_script_runtime`; run in Goja/Starlark sandbox per file
6. **Evaluate results — fully automatic:**
   - All files pass → send `ConfirmEvaluation` to server → triggers Stripe payment to seller; budget remainder refunded; `.kbuyer` deleted
   - Any files fail → send `InitiateArbitration(K)` to server automatically; `.kbuyer` deleted on success

Output directory resolution:
- Default: value of `output_dir` in `~/.config/balancer-customer/config.toml`
- Override: `--out <dir>` flag (takes precedence for that invocation)
- Files are written to `<output_dir>/<transfer_id>/`

### Arbitration

If evaluation fails, `InitiateArbitration(K)` is called automatically — no manual command needed.
Balancer decrypts its encrypted copy, verifies claim hashes, runs the evaluation script
(Goja/Starlark), and issues a ruling.

See [balancer-arbitration.md](./balancer-arbitration.md) for the full arbitration spec — verdicts,
reputation scoring, 48h window, and edge cases.

---

## Data Flow

```
BUYER CLI                    BALANCER SERVER                  SELLER
  |                              |                              |
  |-- PlaceRequest ------------->|                              |
  |   (budget, token_price,      |-- hash eval_script           |
  |    evaluation_script,        |   lock token_price_snapshot  |
  |    eval_script_runtime,      |   charge budget to escrow    |
  |    message, expiry,          |                              |
  |    blocked_sellers[])        |-- forward to eligible ------>|
  |<-- request_id ---------------|   sellers (excluding blocked)|
  |                              |                              |
  |                    [seller accepts, scans, evaluates,       |
  |                     approves, generates K, hashes,          |
  |                     encrypts, streams to balancer]          |
  |                              |                              |
  |-- transfers list ----------->|                              |
  |<-- [transfer ready] ---------|                              |
  |                              |                              |
  |-- transfers receive <id> --->|                              |
  |<-- K_buyer ------------------|                              |
  |<-- encrypted file stream ----|                              |
  |                              |                              |
  | [decrypt K_buyer → K]        |                              |
  | [decrypt files with K]       |                              |
  | [write to output dir]        |                              |
  | [run eval script from        |                              |
  |  TransferSummary fields]     |                              |
  |                              |                              |
  |  if all pass:                |                              |
  |-- ConfirmEvaluation -------->|                              |
  |                              |-- pay seller (Stripe) ------>|
  |<-- budget remainder refunded-|                              |
  |                              |                              |
  |  if any fail (auto):           |                              |
  |-- InitiateArbitration(K) --->|                              |
  |                              |-- decrypt + verify hashes    |
  |                              |-- run eval (Goja/Starlark)   |
  |                              |-- issue ruling               |
```

---

## Evaluation Script

The same script uploaded with the request is run in two places:

1. **Seller-side** (before transfer): buyer-authored script runs in Goja sandbox on the seller's
   machine (via balancer-seller-cli) against anonymised files. Files that fail are not transferred.
2. **Buyer-side** (after receipt): same script runs locally on decrypted files. If it fails,
   the buyer can dispute.
3. **Arbitration** (if disputed): balancer runs same script (Goja/Starlark, server-side) on its encrypted
   copy after buyer provides K.

The script hash stored by balancer is the source of truth — the same script runs at all three points.

Both `.js` and `.star` (Starlark) scripts are supported. The runtime is selected by file extension.

### emit() contract

Scripts must call `emit(true)` / `emit(false)` (JS) or `emit(True)` / `emit(False)` (Starlark) to
signal pass or fail. If the script errors or never calls `emit`, the file is marked FAIL.

### Available library functions

| JS | Starlark | Description |
|---|---|---|
| `readFile(name)` | `read_file(name)` | Read a file from the same directory as the validated file |
| `parseCSV(content)` | `parse_csv(content)` | Parse CSV/TSV into rows (array of dicts) |
| `parseJSONL(content)` | `parse_jsonl(content)` | Parse JSONL into rows |
| `filterRows(rows, fn)` | `filter_rows(rows, fn)` | Filter rows with a predicate |
| `groupBy(rows, col)` | `group_by(rows, col)` | Group rows by column value |
| `stats(rows, col)` | `stats(rows, col)` | Compute count/sum/mean/min/max/stddev |

Scripts cannot access the network, environment variables, or files outside the validated file's directory.

### Resource limits and determinism

Goja (JS) scripts have a **30 s timeout**; Starlark scripts have a **60 M step limit**. `Math.random`
and `Date` are stripped from the Goja VM — scripts must be deterministic (required for arbitration
correctness). Starlark is deterministic by design.

### File type allowlist

Evaluation scripts only run against plain-text files. Allowed extensions: `.csv` `.tsv` `.json`
`.jsonl` `.txt` `.md` `.log` `.js` `.ts` `.go` `.py` `.rb` `.html` `.xml` `.yaml` `.yml` `.toml`
`.star`. Binary files are rejected before the VM starts.

See [sandboxed-file-validator.md](./sandboxed-file-validator.md) for the full sandbox reference.

---

## Config File

`~/.config/balancer-customer/config.toml`

```toml
api_key        = "..."
server.address = "balancer.example.com:443"
output_dir     = "~/balancer-received"    # default output for received transfers
poll_interval  = "1h"                     # heartbeat daemon poll interval (e.g. 30m, 1h, 6h)
```

---

## Audit

```
balancer-customer audit list [--request <id>]
```

Calls `CompanyService.GetAuditLog` and displays one row per transfer. Fields shown:

| Field | Description |
|---|---|
| `transfer_id` | |
| `request_id` | |
| `anonymised_seller_id` | Stable pseudonym — never exposes real seller identity |
| `transfer_status` | `completed` / `cancelled` / `arbitrated` |
| `tokens_delivered` | |
| `token_price_snapshot` | Price per token locked at request placement |
| `cost` | `tokens_delivered × token_price_snapshot` |
| `budget` | Original budget placed |
| `refund` | `budget − cost`; zero if arbitration ruled seller_wins |
| `evaluation_outcome` | `passed` / `failed` |
| `arbitration_verdict` | `buyer_wins` / `seller_wins` / `n/a` |
| `completed_at` | When transfer stream closed |
| `confirmed_at` | When ConfirmEvaluation was sent; null if arbitrated |
| `arbitration_ruled_at` | When ruling was issued; null if n/a |

`--request <id>` filters entries to a single request. `--json` outputs the full `BuyerAuditEntry` array.

See `balancer-server.md` — Audit Log → BuyerAuditEntry for the full field definitions.

---

## Seller Blacklist

Buyers can exclude specific sellers from their requests via `--block-seller <id>`. Seller IDs are
anonymised (balancer does not expose real identity to buyers), but buyers can note the anonymised
ID shown in transfer history and block it on future requests. This is the v1 mechanism for avoiding
sellers who previously delivered bad data.

---

## Key Properties

- **Two polling modes** — heartbeat daemon (background, configurable interval, system notifications) or manual `transfers list` + `transfers receive`; both trigger the same receive logic
- **Fully automatic on receipt** — eval passes → `ConfirmEvaluation` sent automatically; eval fails → `InitiateArbitration(K)` triggered automatically; no manual gate in either direction
- **K_buyer persisted for recovery** — `.kbuyer` bytes written to `<output_dir>/<transfer_id>/.kbuyer` before decryption; deleted after successful confirm or arbitration initiation; allows retry within 48h window if network fails
- **Arbitration requires K** — buyer provides K when arbitration is triggered; without K balancer cannot decrypt its copy and cannot investigate
- **Multiple active requests** — a company can have many open requests simultaneously, each with
  its own script, budget, and lifecycle
- **Deduplication** — deferred to post-v1; buyers are responsible via eval script for now
- **Script is buyer-authored but balancer-hashed** — neither party can alter it after submission
