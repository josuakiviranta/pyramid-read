# Balancer Arbitration Spec

## Overview

Arbitration is the dispute resolution mechanism for Balancer transfers. It allows buyers to challenge
a completed transfer if the received files fail their evaluation script. The arbitration worker is a
separate Go binary that acts as a pure sandbox processor — it has no database access and communicates
with the main server via internal gRPC.

---

## Who Can Initiate

Only buyers can initiate arbitration. Sellers have no dispute mechanism — their obligation ends at
delivery.

---

## Initiation Window

Buyer has **48 hours** from transfer completion to initiate arbitration. If no arbitration is
initiated within that window, the transfer auto-settles: seller is paid in full, temp copy is
deleted, event logged to audit log. No arbitration record is created for auto-settled transfers.

---

## Initiation Flow

```
1. Buyer calls InitiateArbitration(api_key, transfer_id, decryption_key K)
2. Main server creates arbitrations row with status = queued
3. Main server holds K in memory for worker pickup
4. Worker polls PollJob, receives: encrypted file bytes, file_infos[] (each: claim_hash + file_name), evaluation_script,
   evaluation_script_runtime, K
5. Main server sets status = in_progress, started_at = now
6. Worker processes arbitration (see Process below)
7. Worker submits verdict via SubmitVerdict
8. Main server records verdict, triggers payment, cleans up
```

Arbitration is all-or-nothing — a buyer cannot dispute a subset of files from a transfer.

Once initiated, arbitration cannot be cancelled or withdrawn by the buyer.

---

## Process (Worker)

```
1. Decrypt file bytes using K (AES-256-GCM)
   → If decryption fails (wrong key or garbage output): submit seller_wins immediately
2. SHA-256 each decrypted file; compare against file_infos[i].claim_hash (paired by index)
   → If any hash mismatches: submit buyer_wins immediately (seller swapped files)
3. Run evaluation_script in Goja/Starlark sandbox (runtime selected by evaluation_script_runtime)
   → If evaluation fails: submit buyer_wins
   → If evaluation passes: submit seller_wins
```

---

## Verdicts

| Verdict | Meaning | Outcome |
|---|---|---|
| `buyer_wins` | Files failed evaluation, seller swapped files, or temp copy missing (system error) | Buyer refunded from escrow; seller reputation -10 (not applied if temp copy was missing due to server-side storage failure) |
| `seller_wins` | Files passed evaluation, or buyer provided wrong decryption key | Seller paid in full; buyer reputation -10 |

No other verdict states. Hash mismatch and wrong-key cases are folded into `buyer_wins` and
`seller_wins` respectively.

---

## Reputation Scoring

- Both sellers and buyers start at **100 points**
- Each arbitration loss deducts **10 points**
- An **admin alert** is queued in `admin_alerts` when any seller's or buyer's score drops below **80 points**; consumed by admin heartbeat daemon via `AdminService.ListAlerts`
- Admin bans manually — no automatic banning in MVP
- Reputation scores stored on `sellers` and `companies` tables

---

## Missing Temp Copy (System Error)

If the temp encrypted copy is missing when the worker attempts to decrypt (e.g. storage failure):

- Auto-rule `buyer_wins`; buyer refunded in full
- An **admin alert** of type `missing_temp_copy` is queued in `admin_alerts` immediately
- Logged to audit log as a system error event

The seller is not penalised for a server-side storage failure.

---

## Worker Architecture

Arbitration runs as a **separate Go binary** (`cmd/arbitration/`) on the same VM as the main server.

- Worker has **no database access** — all DB reads/writes handled by main server
- Worker communicates with main server via internal `ArbitrationService` gRPC
- Worker is a pure processor: decrypt → verify hashes → run sandbox → submit verdict
- Processes **one arbitration at a time**, FIFO by `created_at`
- Same VM for MVP; trivial to migrate to a separate VM without architectural changes

### Queue

- Arbitration requests queued in `arbitrations` table (`status = queued`)
- Worker polls `PollJob`; main server delivers next queued job
- Main server sets `status = in_progress` when picked up
- Main server sets `status = ruled` on verdict receipt

---

## Worker Crash & Retry

If the worker crashes or restarts mid-arbitration:

- The job remains at `status = in_progress` in the database
- On worker restart, it re-polls and the main server resets the job to `status = queued` and
  redelivers it
- Worker retries from the beginning
- An **admin alert** of type `worker_crash` is queued in `admin_alerts` on worker crash/restart

---

## Concurrent Arbitrations

A buyer may have multiple active arbitrations simultaneously (across different transfers). Each is
queued independently and processed FIFO by the worker.

---

## Verdict Delivery to Buyer

Buyer discovers the verdict via:
- **Heartbeat daemon** — background polling detects status change on the transfer
- **Manual polling** — `transfers show <transfer_id>` or `audit list`

No push notification.

---

## Post-Ruling Cleanup

On verdict:
1. Payment triggered (see Payment Flow in `balancer-server.md`)
2. K deleted from main server memory immediately
3. Temp encrypted copy deleted immediately
4. Arbitration verdict logged to audit log

---

## Admin Role

Admin can call `ReviewArbitration(admin_key, arbitration_id)` to retrieve the full audit trail for
a case. Admin role is **read-only** — verdicts cannot be overridden.

---

## Internal gRPC — ArbitrationService

### `PollJob() → ArbitrationJob`
Worker polls for the next queued arbitration. Main server returns:
- `transfer_id`
- `encrypted_file_bytes`
- `file_infos[]` — each entry has `claim_hash` (SHA-256 hex) and `file_name` (base filename, e.g. `"report.csv"`)
- `evaluation_script` (source text)
- `evaluation_script_runtime` (`js` or `star`)
- `decryption_key` K

### `SubmitVerdict(transfer_id, verdict, reason) → ok`
Worker returns ruling to main server. `reason` is one of:
- `decryption_failed`
- `hash_mismatch`
- `evaluation_failed`
- `evaluation_passed`
- `missing_temp_copy`

---

## Arbitration Table Schema

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `transfer_id` | uuid | FK → transfers |
| `initiated_by_company_id` | uuid | FK → companies |
| `status` | enum | `queued` / `in_progress` / `ruled` |
| `verdict` | enum | `buyer_wins` / `seller_wins` / `pending` |
| `reason` | string | worker-provided reason code |
| `created_at` | timestamp | used for FIFO ordering |
| `started_at` | timestamp | set when worker picks up job |
| `ruled_at` | timestamp | set on verdict |

---

## Out of Scope (v1)

- Seller-initiated disputes
- Partial file arbitration
- Buyer appeal after ruling
- Admin verdict override
- Automatic banning based on reputation score
