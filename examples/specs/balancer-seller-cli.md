# Balancer Seller CLI Spec

## Overview

`balancer-seller-cli` is the CLI tool for data sellers (local computer users). It lets a seller
receive data requests from companies via the balancer broker, scan local folders, anonymise files,
run evaluation scripts, approve content, and transfer encrypted files. Written in Go; distributed
as a single binary.

AI-native — includes `skills/balancer-seller-cli/SKILL.md` so any AI model can drive the CLI on
the seller's behalf via shell commands.

---

## Tech Stack

| Concern | Choice |
|---|---|
| Language | Go |
| CLI framework | Cobra |
| Config | TOML (`~/.config/balancer/config.toml`) |
| gRPC | google.golang.org/grpc |
| JS sandbox | Goja (shared `sandboxed-file-validator` package) |
| Starlark sandbox | Starlark-Go (shared `sandboxed-file-validator` package) |
| Crypto | Go stdlib (`crypto/aes`, `crypto/rsa`, `crypto/sha256`) |
| Tokenization | Approximate token count: `ceil(bytes / 4)`; displayed in CLI output |
| Distribution | Single binary — GoReleaser, Homebrew, apt, curl |

---

## Auth & Onboarding

Signup is triggered automatically on first launch if no credentials are found.
The full flow runs in one `balancer signup` command (or auto-triggered):

1. **Firebase Authentication** (Google OAuth device flow) — user visits a URL, signs in, CLI receives Firebase ID token
2. **Stripe Connect onboarding (Accounts v2)** — browser opens immediately after OAuth; seller
   completes Stripe-hosted onboarding; server creates Connect Account and stores `stripe_account_id`

Both steps happen once. Auto-triggered on first launch if no credentials are found.

---

## Command Surface

```
balancer signup                                      # Google OAuth + Stripe Connect (auto on first launch)
balancer config show / set <key> <value>
balancer account status                              # Google account, Stripe connection, reputation

balancer heartbeat start / stop / status             # background daemon: polls server for pending requests

balancer requests list
balancer requests show <id>                          # company name, message, eval script body
balancer requests analyze <id>                       # side-by-side view for AI: message vs eval script
balancer requests accept <id>
balancer requests decline <id>

balancer files scan <request_id> <folder...>         # recursive; anonymise → eval → save manifest; skips files already sent to same company (--include-sent to override)

balancer transfer preview <id>                       # show files, token count, estimated payout
balancer transfer remove <id> <file...>              # remove specific files from manifest
balancer transfer start <id> --yes                   # explicit confirmation required
balancer transfer status <transfer_id>

balancer audit list                                  # transfer history, payouts, verdicts
```

All commands support `--json` for structured output (AI-parseable).

---

## Reviewing Requests

```
balancer requests list
balancer requests show <id>
balancer requests analyze <id>
balancer requests accept <id>
balancer requests decline <id>
```

When a request arrives (via heartbeat notification or manual poll):

- `requests list` — shows pending requests: company name, message preview, eval script hash
- `requests show <id>` — shows full detail: company name, company message, full evaluation script body
- `requests analyze <id>` — outputs company message and eval script body side-by-side for AI
  comparison; lets an AI agent verify the script matches the stated purpose before the seller accepts
- Budget is **never shown to sellers** — confidential between balancer and buyer

---

## Scanning Files

```
balancer files scan <request_id> <folder...> [--include-sent]
```

Recursive walk through all provided folders and subfolders. Per file, in strict order:

0. **Sent-files check** — `original_hash` (SHA-256 of raw file) is checked against
   `~/.config/balancer/sent-files.json` for the request's company; files already sent to that
   company are skipped with a warning and excluded from the manifest; use `--include-sent` to
   override and include them anyway
1. **Built-in PII anonymisation** — strips emails, phones, national IDs (EU + US), addresses,
   IBANs, credit cards, crypto wallets, MAC addresses, IP addresses; implemented in
   `src/sandboxed-file-validator/sandbox/pii.go`; always runs first
2. **Seller custom anonymisation scripts** — loads `~/.config/balancer/anonymise/*.js` and `*.star`;
   each script receives already-PII-stripped content via `CONTENT` global; must call `emit(string)`
   with result
3. **Anonymised output written to ephemeral preview folder** — seller can inspect anonymised
   versions before proceeding
4. **Buyer evaluation script run** — `AnalyzeContent(filePath, anonymisedContent, script)` is
   called (not `Analyze()`) so the SHA-256 hash reflects the anonymised bytes the buyer will
   receive, not the raw file; runs in Goja (JS) or Starlark sandbox against preview folder files
   (never originals); files that fail are excluded

   Per-file progress phases are printed to stdout during scanning:
   `file validating...` → `anonymising: stripping PII...` → `evaluating...` → `hashing...`
5. **Manifest saved** — passing files recorded to `~/.config/balancer/manifests/<request_id>.json`

Manifest fields: `request_id`, `scanned_at`, `token_price_snapshot`,
`files[]{path, original_hash, sha256_anonymised, tokens, preview_path}`

- `original_hash`: SHA-256 of raw original — for seller's own deduplication tracking across requests
- `sha256_anonymised`: SHA-256 of anonymised content — becomes the claim hash sent to balancer

Token count and estimated payout displayed after scan completes.

---

## Transfer

```
balancer transfer preview <id>
balancer transfer remove <id> <file...>
balancer transfer start <id> --yes
balancer transfer status <transfer_id>
```

### Preview & removal

- `transfer preview <id>` — reads manifest; displays file paths, token count, estimated payout
- `transfer remove <id> <file...>` — removes specific files from manifest before transfer; seller
  final review gate

### Starting a transfer

`transfer start <id> --yes` requires explicit `--yes` flag. Steps executed in order:

1. **Compute SHA-256 claim hashes** of anonymised files — sent to balancer as binding integrity
   commitment; seller cannot swap file contents after this point
2. **Generate symmetric session key K** per transfer (AES-256-GCM, `crypto/rand`)
3. **Call `StartTransfer`** — sends `token_count` and `file_infos[]` (each: `claim_hash` + `file_name`) to balancer
4. **Encrypt files with K** (AES-256-GCM) and stream encrypted chunks via gRPC+TLS bidirectional
   stream through balancer to buyer
5. **Encrypt K with buyer's RSA/EC public key** → K_buyer; deliver K_buyer to balancer at stream
   close
6. **Update sent-files registry** — on confirmed stream close, append each transferred file's
   `original_hash` + `transfer_id` + `sent_at` to `~/.config/balancer/sent-files.json` under the
   company's ID; failure to write does not fail the transfer

Cancellation: seller kills the process. Partial transfers are discarded; balancer deletes temp copy.

---

## Data Flow

```
SELLER CLI                   BALANCER SERVER                  BUYER
  |                              |                              |
  |<-- GetPendingRequests -------|<-- PlaceRequest -------------|
  |    (eval_script,             |    (budget, script,          |
  |     public_key)              |     eval_script_runtime)     |
  |                              |                              |
  |-- RespondToRequest (accept)->|                              |
  |                              |                              |
  | [select folders]             |                              |
  | [built-in PII strip]         |                              |
  | [custom anon scripts]        |                              |
  | [write preview folder]       |                              |
  | [run eval script → Goja]     |                              |
  | [seller reviews & approves]  |                              |
  | [compute claim hashes]       |                              |
  | [generate K]                 |                              |
  | [encrypt files with K]       |                              |
  |                              |                              |
  |-- StartTransfer ------------>|                              |
  |   (token_count,              |-- store file_infos           |
  |    file_infos[])             |-- store encrypted copy       |
  |-- encrypted stream --------->|-- relay stream ------------->|
  |-- K_buyer ------------------>|-- deliver K_buyer ---------->|
  |                              |                              |
  |                              | [buyer decrypts, evaluates]  |
  |                              |                              |
  |                              |<-- ConfirmEvaluation --------|
  |<-- payment (Stripe) ---------|-- pay seller                 |
```

---

## Evaluation Script

The buyer-authored evaluation script runs in two places relevant to the seller:

1. **Seller-side** (before transfer): script runs in Goja sandbox on the seller's machine against
   anonymised files in the preview folder. Files that fail are not transferred.
2. **Arbitration** (if buyer disputes): balancer runs same script (Goja/Starlark, server-side) on its
   encrypted copy after buyer provides K.

The script hash stored by balancer is the source of truth — the same script runs at all points.
Seller can inspect the full script body via `requests show <id>` before accepting.

Both `.js` and `.star` (Starlark) scripts are supported. Runtime selected by file extension.

---

## Custom Anonymisation Scripts

Sellers can place personal anonymisation scripts in `~/.config/balancer/anonymise/`:

- Supported: `.js` (Goja) and `.star` (Starlark)
- Scripts run **after** built-in PII stripping, **before** buyer eval script
- Script receives already-PII-stripped content via `CONTENT` global; must call `emit(string)` with
  the result
- Use case: strip company-specific sensitive fields, remove internal metadata, normalise formats

---

## Config File

`~/.config/balancer/config.toml`

```toml
api_key                  = "..."
google_email             = "..."
stripe_account_id        = "..."
server.address           = "balancer.example.com:443"
heartbeat.poll_interval  = "24h"    # how often daemon polls for requests (e.g. 1h, 24h)
```

Additional files managed under `~/.config/balancer/`:

| File | Purpose |
|---|---|
| `manifests/<request_id>.json` | Per-scan manifest (files, hashes, token count, preview paths) |
| `sent-files.json` | Sent-files registry: tracks `original_hash` per company to prevent accidental resale |
| `anonymise/*.js`, `*.star` | Seller custom anonymisation scripts |

---

## Key Properties

- **Simplest possible UX** — seller needs only: heartbeat running, `requests show`, `files scan`,
  `transfer start`
- **Budget hidden from sellers** — balancer and buyer only; prevents price anchoring
- **Anonymisation always runs first** — PII stripped locally before eval script or transfer
- **Seller cannot alter files post-commitment** — claim hashes sent before encrypted payload;
  mismatch = seller fault in arbitration
- **AI-native** — `requests analyze` + `--json` output designed for AI agent automation
- **Heartbeat daemon** polls once per day by default; configurable; system notifications on new
  requests
- **Evaluation script is buyer-authored but balancer-hashed** — neither party can alter it
  post-submission
- **Sent-files registry** — `~/.config/balancer/sent-files.json` tracks which file hashes have
  been sent to each company; `files scan` skips already-sent files by default (`--include-sent`
  to override); registry written only on confirmed successful transfer
