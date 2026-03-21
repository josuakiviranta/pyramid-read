# Balancer Server Spec

## Overview

Balancer server is a routing broker between data sellers (users) and data buyers (companies).
It does not read file contents — it relays encrypted streams and manages trust, payment,
and arbitration between parties.

---

## Tech Stack

| Concern        | Choice                                                                   |
|----------------|--------------------------------------------------------------------------|
| Language       | Go                                                                       |
| Database       | SQLite (MVP) → PostgreSQL (post-MVP migration)                           |
| Transfer       | gRPC with TLS bidirectional streaming                                    |
| Hosting        | GCP Compute Engine e2-micro, europe-west1                                |
| Payments       | Stripe Connect (Accounts v2)                                             |
| Tokenization   | Approximate token count: `ceil(bytes / 4)` — computed client-side by balancer-seller-cli  |
| Sandboxing     | Goja (JS) + Starlark — evaluation script execution                       |
| Deduplication  | Buyer-side responsibility (via evaluation scripts in v1; tlsh post-v1)   |

### MVP Infrastructure Notes
- SQLite file stored on GCP persistent disk — access controlled entirely by Go server (no exposed DB port)
- GCP disk encryption (Google-managed keys) handles data at rest
- e2-micro (~$6/month) is sufficient for MVP; scale up VM and migrate to Cloud SQL when needed
- TLS: use self-signed certificate for development; replace with Let's Encrypt once domain is set
- Domain name: TBD — required before Let's Encrypt certificate can be issued

---

## Actors

| Actor         | Tool                   | Role                          |
|---------------|------------------------|-------------------------------|
| Seller (user) | balancer-seller-cli           | Sells local folder data       |
| Broker        | balancer-server        | Routes, prices, pays, arbitrates |
| Buyer         | balancer-buyer-cli  | Requests and receives data    |
| Admin         | direct server access   | Manages the node              |

---

## Request Lifecycle

```
1.  Buyer writes evaluation_script; places data request + budget to balancer
2.  Balancer hashes evaluation_script, stores hash + script as source of truth
    Balancer charges buyer's budget to Stripe escrow
3.  Balancer broadcasts request (with evaluation_script) to all registered sellers
4.  balancer-seller-cli heartbeat detects pending request, notifies seller
5.  Seller reviews request; accepts or declines
6.  Seller selects candidate files in balancer-seller-cli
7.  balancer-seller-cli runs default anonymisation scripts on candidate files (PII stripped locally)
8.  balancer-seller-cli runs evaluation_script in Goja/Starlark sandbox against anonymised files in preview folder
9.  Files that pass are presented to seller; seller gives final approval
10. Seller's balancer-seller-cli generates symmetric session key K
11. balancer-seller-cli computes claim hashes (SHA-256) of approved anonymised files → sends to balancer
12. balancer-seller-cli encrypts files with K; streams encrypted payload through balancer to buyer
    → balancer holds a temporary encrypted copy during evaluation window
13. balancer-seller-cli encrypts K with buyer's public key → K_buyer; delivers K_buyer to buyer via balancer
14. Buyer decrypts K_buyer with own private key → K; decrypts received files
15. Buyer runs evaluation_script locally on received files
16a. Evaluation passes → buyer sends confirmation to balancer
    → balancer releases payment to seller, refunds remainder to buyer, deletes temp copy
16b. Evaluation fails → buyer initiates arbitration (provides K to balancer)
    → arbitration process begins (see Arbitration section)
```

---

## Authentication

### Sellers
- Register via **Firebase Authentication** (Google OAuth device flow) through balancer-seller-cli
- Receive API key on registration
- All requests authenticated with API key

### Companies (Buyers)
- Register via **Firebase Authentication** (Google OAuth device flow) through balancer-buyer-cli — same flow as sellers
- Provide **RSA/EC public key** on registration (no password)
- Receive API key on registration
- Buyer's public key is used by sellers to encrypt the session key (K_buyer)
- Note: domain TLS certificate verification dropped — `certificate_pem` not stored; company identity established via Google OAuth `google_email` only

### Admin
- Single admin role (server owner)
- Authenticated via a static admin key set in server environment config (not exposed via API)
- Goal: self-managing node requiring minimal admin intervention

---

## Notifications

**Sellers** — balancer-seller-cli runs a **background heartbeat daemon** that polls the server once per day for pending
requests. When a request is found, the daemon notifies the user (terminal alert or system notification).
User can also manually check with a CLI command.

**Buyers** — balancer-buyer-cli optionally runs a **background heartbeat daemon** (default poll: 1 hour)
that polls `ListTransfers` for ready transfers and auto-runs the receive pipeline on each. System
notification is fired on completion. Buyer can also manually poll with `transfers list` and explicitly
call `transfers receive`.

**Admin** — admin runs a local **heartbeat daemon** that polls `AdminService.ListAlerts` for new
alerts (worker crashes, reputation drops, system errors). Alerts are queued in the `admin_alerts`
table on the server and consumed by the admin daemon — no email or external notification service
required.

---

## File Transfer

- Protocol: **gRPC bidirectional streaming over TLS**
- Balancer acts as a **pure relay by default** — receives encrypted byte stream from seller, forwards to buyer
- Balancer holds a **temporary encrypted copy** during the evaluation window for arbitration purposes
- Balancer **never decrypts** file contents outside of an active arbitration ruling
- Seller's balancer-seller-cli generates a **symmetric session key K** per transfer
- Files are encrypted with K by balancer-seller-cli before entering the gRPC stream
- **Claim hashes** (SHA-256 of anonymised file contents) are submitted by seller to balancer before
  the encrypted payload arrives — this is a binding integrity commitment
- Session key K is encrypted with buyer's public key → **K_buyer**, delivered to buyer via balancer
- Balancer does **NOT hold K** — only buyer can decrypt K_buyer using their private key
- Cancellation: seller kills balancer-seller-cli; partial transfers are discarded; temp copy deleted
- Temp copy TTL: encrypted files deleted after buyer confirmation, arbitration ruling, or 72-hour expiry
  (whichever comes first)
- Multiple sellers can stream simultaneously (Go goroutines handle concurrency)

---

## Evaluation & Reputation

### Evaluation Scripts
- Buyer writes and submits an `evaluation_script` with every data request
- Balancer hashes the script on receipt — this hash is the **authoritative source of truth**
- Both seller-side (balancer-seller-cli, pre-transfer) and buyer-side (balancer-buyer-cli, post-transfer)
  run the identical script
- Scripts are written in **JavaScript** (`.js`) or **Starlark** (`.star`); buyer submits source text; balancer stores source + SHA-256 hash; runtime is selected by file extension
- Scripts execute in a sandbox (pure Go, no CGO): no filesystem access beyond provided file content,
  no network calls, must be deterministic; JS timeout 30s via `vm.Interrupt()`; Starlark step limit 60M steps
- Same runtimes used on seller side (balancer-seller-cli), buyer side (balancer-buyer-cli), and server side (arbitration) —
  identical evaluation behaviour guaranteed

### Seller Pre-Transfer Flow
Full pipeline order per candidate file:
1. **Built-in PII stripping** — emails, phones, national IDs (EU + US), IBANs, credit cards, crypto
   wallets, MAC/IP addresses stripped automatically; implemented in `sandboxed-file-validator/sandbox/pii.go`
2. **Seller custom anonymisation scripts** — JS/Starlark scripts from `~/.config/balancer/anonymise/`;
   each script receives PII-stripped content via `CONTENT` global, calls `emit(string)` with result
3. Anonymised content written to ephemeral **preview folder**
4. **Evaluation script** runs (Goja/Starlark sandbox) against files in preview folder — not originals
5. Passing files presented to seller for final approval; seller can remove individual files
6. Seller confirms → claim hashes (SHA-256) computed from preview folder files → files encrypted
Seller is never forced to send all passing files.

### Reputation Scoring
- Both sellers and buyers start at **100 points**
- Each arbitration loss deducts **10 points** from the losing party's score
- An **admin alert** is queued in `admin_alerts` when any score drops below **80 points**; consumed by admin heartbeat daemon
- Admin bans manually — no automatic banning in MVP
- Seller reputation decreases on `buyer_wins` ruling; buyer reputation decreases on `seller_wins` ruling
- Exception: seller reputation is **not** deducted if the `buyer_wins` ruling was caused by a missing temp copy (server-side storage failure) — see `balancer-arbitration.md` — Verdicts
- Deduplication is the **buyer's responsibility** — buyers track received files locally (tlsh) and
  write evaluation scripts that filter already-held files

---

## Encryption

### Per-Transfer Key Design
- Seller's balancer-seller-cli generates a random **symmetric session key K** per transfer (AES-256-GCM)
- All file contents are encrypted with K before entering the gRPC stream
- K is encrypted with buyer's RSA/EC public key → **K_buyer**
- K_buyer is delivered to buyer via balancer; buyer decrypts K_buyer with their private key to recover K
- Balancer holds the encrypted payload temporarily but holds **no copy of K**
- Balancer is a **blind relay by default** — cannot read file contents without the decryption key

### Claim Hashes
- Seller sends **SHA-256 hashes** of anonymised files to balancer **before** the encrypted payload arrives
- This creates a binding commitment: seller cannot swap file contents after hashes are submitted
- During arbitration, balancer SHA-256 hashes each decrypted file and verifies against committed hashes

### Key Lifecycle
- K_buyer delivered to buyer at transfer completion
- K is never stored persistently anywhere — buyer derives it from K_buyer on demand
- If arbitration is initiated, buyer provides K to balancer (single-use, per arbitration)
- K is deleted from balancer immediately after arbitration ruling

---

## Arbitration

See [balancer-arbitration.md](./balancer-arbitration.md) for the full arbitration spec.

Only buyers can initiate arbitration. Buyer provides decryption key K at initiation — without K
balancer cannot decrypt its copy and cannot investigate.

Two verdicts: `buyer_wins` (files failed evaluation, seller swapped files, or missing temp copy)
and `seller_wins` (files passed evaluation, or buyer provided wrong key). 48h non-cooperation
window: if buyer does not initiate within 48h of transfer completion, transfer auto-settles and
seller is paid in full.

Arbitration runs as a **separate Go binary** (`cmd/arbitration/`) on the same VM — a pure
processor with no DB access, communicating with the main server via internal `ArbitrationService`
gRPC. See [balancer-arbitration-implementation-plan.md](./balancer-arbitration-implementation-plan.md)
for the implementation plan.

---

## Tokenization & Pricing

- Files are tokenized using an **approximate token count** — `ceil(bytes / 4)` — computed client-side by balancer-seller-cli
- balancer-seller-cli tokenizes selected files, shows seller the token count + estimated payout before transfer
- Buyer sets a **token price** (per-token rate) when placing a request — this is the public offer rate, visible to sellers in `GetPendingRequests`
- Buyer sets a **budget** (max total spend) when placing a request — **never disclosed to sellers**
- Token price is **snapshotted at request time** (`token_price_snapshot`) and locked for the duration of the transaction
- Seller submits token count at transfer start (stream metadata)
- Final cost = `seller_token_count × token_price_snapshot`
- If `cost < budget` → remainder refunded to buyer after payment release
- **Budget enforcement**: at `StartTransfer`, server checks `committed_cost + (token_count × token_price_snapshot) ≤ budget`; stream open is rejected if this would exceed budget; request **auto-closes** when budget is fully committed (no new seller responses accepted)
- **Nearly exhausted signal**: when committed cost reaches ≥ 80% of budget, `budget_nearly_exhausted = true` is set on the `Request` returned by `GetPendingRequests` — warns sellers to act quickly before budget is gone; does not reveal budget magnitude
- Payment is released when buyer confirms evaluation passed (or balancer rules in seller's favour after arbitration)

---

## Payment Flow

```
Buyer places request + evaluation_script → budget charged to Stripe escrow
                         ↓
            Seller transfers encrypted files
                         ↓
          Buyer decrypts + runs evaluation_script
                         ↓
        ┌────────────────┴────────────────────┐
        │ Passes                               │ Fails
        │ Buyer sends confirmation             │ Buyer initiates arbitration + provides K
        │         ↓                            │               ↓
        │ Balancer pays seller                 │  Balancer decrypts + runs script
        │ Balancer refunds remainder           │               ↓
        │ Temp copy deleted                    │  ┌────────────┴─────────────┐
        └──────────────────────────────────────┘  │ Still fails              │ Passes
                                                   │ Buyer refunded           │ Seller paid in full
                                                   │ Seller rep hit           │ Buyer rep hit
                                                   └──────────────────────────┘
```

- Buyer budget is charged to Stripe escrow **at request placement** (before any transfer)
- Sellers onboard via Stripe Connect (Accounts v2) to receive payouts
- All payment events logged in audit log

---

## Audit Log

Per transaction, balancer stores:
- Seller ID
- Company ID
- Request ID
- Timestamp (request, transfer start, transfer end, evaluation confirmation, arbitration)
- Token count delivered
- Claim hashes (not file contents)
- Evaluation script hash (reference only — not the script body post-transfer)
- Payment amount (seller payout + buyer refund)
- Transfer status (completed / cancelled / arbitrated)
- Arbitration verdict (if applicable)

### BuyerAuditEntry

Returned by `CompanyService.GetAuditLog`. One entry per transfer.

| Field | Type | Description |
|---|---|---|
| `transfer_id` | string | |
| `request_id` | string | |
| `anonymised_seller_id` | string | Stable pseudonym — never exposes real seller identity |
| `transfer_status` | enum | `completed` / `cancelled` / `arbitrated` |
| `tokens_delivered` | int64 | |
| `token_price_snapshot` | decimal | Price per token locked at request placement |
| `cost` | decimal | `tokens_delivered × token_price_snapshot` |
| `budget` | decimal | Original budget placed at request time |
| `refund` | decimal | `budget − cost`; zero if arbitration ruled seller_wins |
| `evaluation_outcome` | enum | `passed` / `failed` |
| `arbitration_verdict` | enum | `buyer_wins` / `seller_wins` / `n/a` |
| `completed_at` | timestamp | When transfer stream closed |
| `confirmed_at` | timestamp | When buyer sent ConfirmEvaluation; null if arbitrated |
| `arbitration_ruled_at` | timestamp | When arbitration ruling was issued; null if n/a |

### SellerAuditEntry

Returned by `SellerService.GetAuditLog`. One entry per transfer.

| Field | Type | Description |
|---|---|---|
| `transfer_id` | string | |
| `request_id` | string | |
| `transfer_status` | enum | `completed` / `cancelled` / `arbitrated` |
| `tokens_delivered` | int64 | |
| `payout` | decimal | Amount paid to seller; zero if arbitration ruled buyer_wins |
| `evaluation_outcome` | enum | `passed` / `failed` |
| `arbitration_verdict` | enum | `buyer_wins` / `seller_wins` / `n/a` |
| `completed_at` | timestamp | When transfer stream closed |
| `arbitration_ruled_at` | timestamp | When arbitration ruling was issued; null if n/a |

---

## Database Schema (High Level)

| Table              | Key Fields                                                                                          |
|--------------------|-----------------------------------------------------------------------------------------------------|
| sellers            | id, firebase_uid, google_email, api_key, reputation_score, stripe_account_id, banned                              |
| companies          | id, firebase_uid, google_email, api_key, public_key_pem, stripe_customer_id, reputation_score, banned              |
| requests           | id, company_id, budget, token_price_snapshot, evaluation_script, evaluation_script_hash, evaluation_script_runtime, company_message, expires_at, blocked_sellers, status, created_at |
| request_responses  | id, request_id, seller_id, status                                                                   |
| transfers          | id, request_response_id, tokens_delivered, cost, file_infos, encrypted_copy_path, encrypted_key_buyer, evaluation_status, status, started_at, completed_at |
| arbitrations       | id, transfer_id, initiated_by_company_id, status (queued/in_progress/ruled), verdict (pending/buyer_wins/seller_wins), reason, created_at, started_at, ruled_at |
| payments           | id, transfer_id, stripe_charge_id, stripe_payout_id, stripe_refund_id, seller_payout, company_refund, created_at |
| audit_log          | id, event_type, actor_id, actor_type, metadata, created_at                                         |
| admin_alerts       | id, type, payload, created_at, read_at                                                              |

---

## API Surface (gRPC Services)

### SellerService
- `Register(firebase_id_token) → api_key`
- `GetPendingRequests(api_key) → []Request` ← heartbeat daemon; includes evaluation_script (JS source), evaluation_script_runtime, company_message, and buyer public_key_pem
- `RespondToRequest(api_key, request_id, accept bool) → ok`
- `StartTransfer(api_key, request_id, token_count, file_infos[]) → stream` ← file_infos (each: claim_hash + file_name) submitted at stream open before payload
- `GetTransferStatus(api_key, transfer_id) → TransferStatus`
- `GetAuditLog(api_key) → []SellerAuditEntry`

### CompanyService
- `Register(firebase_id_token, public_key_pem) → api_key`
- `PlaceRequest(api_key, budget, token_price, evaluation_script, evaluation_script_runtime, [company_message], [expires_at], [blocked_sellers[]]) → request_id` ← budget to escrow immediately; token_price locked as token_price_snapshot
- `ListRequests(api_key) → []Request` ← returns all requests placed by this buyer
- `CloseRequest(api_key, request_id) → ok` ← marks request closed; no new seller responses accepted; does not affect in-progress transfers
- `ListTransfers(api_key, [request_id]) → []TransferSummary` ← buyer polling; returns transfer_id, status, token_count, anonymised_seller_id, evaluation_script, evaluation_script_runtime
- `ReceiveTransfer(api_key, transfer_id) → stream` ← encrypted payload + K_buyer delivered in stream
- `ConfirmEvaluation(api_key, transfer_id) → ok` ← triggers payment release
- `InitiateArbitration(api_key, transfer_id, decryption_key) → arbitration_id`
- `GetAuditLog(api_key) → []BuyerAuditEntry`

### AdminService
- `ListSellers(admin_key) → []Seller`
- `BanSeller(admin_key, seller_id) → ok`
- `ListCompanies(admin_key) → []Company`
- `BanCompany(admin_key, company_id) → ok`
- `ReviewArbitration(admin_key, arbitration_id) → AuditEntry` ← read-only; verdicts cannot be overridden
- `ListAlerts(admin_key, since_id) → []AdminAlert` ← admin heartbeat daemon polls this; `since_id` empty returns all unread; marks returned alerts as read

---

## Proto Message Definitions

Four files in `proto/` at repo root, shared across all three codebases.
All use `package balancer` and `option go_package = "github.com/balancer/proto/balancer"`.

```
proto/
  common.proto   — FileInfo, TransferInit, TransferChunk, Request, TransferSummary
  seller.proto   — SellerService, SellerAuditEntry, per-RPC request/response messages
  company.proto  — CompanyService, BuyerAuditEntry, per-RPC request/response messages
  admin.proto    — AdminService, AuditEntry, SellerInfo, CompanyInfo, per-RPC request/response messages
```

---

### common.proto

#### FileInfo

Submitted by the seller at `StartTransfer` open — one per approved anonymised file. Constitutes a
binding integrity commitment; seller cannot swap file contents after this point.

| Field | Type | Notes |
|-------|------|-------|
| `claim_hash` | string | SHA-256 hex digest of the anonymised file content |
| `file_name` | string | Base filename (e.g. `"report.csv"`) — used for `FILE_PATH`/`FILE_NAME` globals and `parseCSV`/`parseJSONL` extension guards in evaluation scripts on the server side (arbitration) |

#### TransferChunk

Used in `StartTransfer` (seller → balancer, client-streaming) and `ReceiveTransfer` (balancer → buyer,
server-streaming). Each message carries exactly one payload via `oneof`:

| Field | Type | When | Description |
|---|---|---|---|
| `init` | TransferInit | First message of `StartTransfer` only | Transfer metadata |
| `data` | bytes | All intermediate messages | Encrypted file bytes (AES-256-GCM) |
| `k_buyer` | bytes | Last message of both `StartTransfer` and `ReceiveTransfer` | Session key K encrypted with buyer's RSA/EC public key; seller sends it to balancer at stream close, balancer relays it to buyer as the final message of `ReceiveTransfer` |

**TransferInit** (carried in the `init` field):

| Field | Type | Description |
|---|---|---|
| `api_key` | string | Seller's API key — auth for client-streaming RPC where no unary request message exists |
| `request_id` | string | |
| `token_count` | int64 | Total tokens across all files being transferred |
| `file_infos` | repeated FileInfo | One per approved file; stored by balancer before payload arrives; `claim_hash` used for integrity verification, `file_name` used for eval script globals during arbitration |

#### Request

Returned by `GetPendingRequests` (seller-facing) and `ListRequests` (buyer-facing). Fields marked
seller-only or buyer-only are omitted on the other side.

| Field | Type | Side | Description |
|---|---|---|---|
| `request_id` | string | both | |
| `evaluation_script` | string | seller | Full JS or Starlark source |
| `evaluation_script_runtime` | string | seller | `"js"` or `"starlark"` |
| `evaluation_script_hash` | string | both | SHA-256 hex; authoritative reference |
| `company_message` | string | seller | Optional message from buyer to seller |
| `public_key_pem` | string | seller | Buyer's RSA/EC public key; used by seller to encrypt K |
| `token_price` | double | seller | Per-token rate offered by buyer; public offer rate |
| `budget_nearly_exhausted` | bool | seller | `true` when committed cost ≥ 80% of budget; warns seller to act quickly; does not reveal budget magnitude |
| `status` | string | both | `"open"` / `"closed"` / `"expired"` |
| `budget` | double | buyer | Original budget; not disclosed to sellers |
| `expires_at` | int64 | both | Unix timestamp; 0 = no expiry |
| `created_at` | int64 | both | Unix timestamp |

#### TransferSummary

Returned by `CompanyService.ListTransfers`. One entry per transfer.

| Field | Type | Description |
|---|---|---|
| `transfer_id` | string | |
| `request_id` | string | |
| `status` | string | `"pending"` / `"ready"` / `"received"` / `"disputed"` |
| `token_count` | int64 | Total tokens in the transfer |
| `anonymised_seller_id` | string | Stable pseudonym — never exposes real seller identity |
| `evaluation_script` | string | Full JS or Starlark source — buyer uses this to run eval locally at receive time |
| `evaluation_script_runtime` | string | `"js"` or `"starlark"` |

---

### seller.proto

Imports `common.proto`.

```proto
service SellerService {
  rpc Register(RegisterSellerRequest)               returns (RegisterSellerResponse);
  rpc GetPendingRequests(GetPendingRequestsRequest)  returns (GetPendingRequestsResponse);
  rpc RespondToRequest(RespondToRequestRequest)      returns (RespondToRequestResponse);
  rpc StartTransfer(stream TransferChunk)            returns (StartTransferResponse);
  rpc GetTransferStatus(GetTransferStatusRequest)    returns (GetTransferStatusResponse);
  rpc GetAuditLog(GetSellerAuditLogRequest)          returns (GetSellerAuditLogResponse);
}
```

| Message | Fields |
|---|---|
| `RegisterSellerRequest` | `firebase_id_token string` |
| `RegisterSellerResponse` | `api_key string` |
| `GetPendingRequestsRequest` | `api_key string` |
| `GetPendingRequestsResponse` | `requests repeated Request` |
| `RespondToRequestRequest` | `api_key string`, `request_id string`, `accept bool` |
| `RespondToRequestResponse` | `ok bool` |
| `StartTransferResponse` | `transfer_id string` |
| `GetTransferStatusRequest` | `api_key string`, `transfer_id string` |
| `GetTransferStatusResponse` | `transfer_id string`, `status string` (`"in_progress"` / `"completed"` / `"cancelled"`) |
| `GetSellerAuditLogRequest` | `api_key string` |
| `GetSellerAuditLogResponse` | `entries repeated SellerAuditEntry` |

**SellerAuditEntry** — see [Audit Log → SellerAuditEntry](#sellerauditentry) above.

---

### company.proto

Imports `common.proto`.

```proto
service CompanyService {
  rpc Register(RegisterCompanyRequest)               returns (RegisterCompanyResponse);
  rpc PlaceRequest(PlaceRequestRequest)               returns (PlaceRequestResponse);
  rpc ListRequests(ListRequestsRequest)               returns (ListRequestsResponse);
  rpc CloseRequest(CloseRequestRequest)               returns (CloseRequestResponse);
  rpc ListTransfers(ListTransfersRequest)             returns (ListTransfersResponse);
  rpc ReceiveTransfer(ReceiveTransferRequest)         returns (stream TransferChunk);
  rpc ConfirmEvaluation(ConfirmEvaluationRequest)     returns (ConfirmEvaluationResponse);
  rpc InitiateArbitration(InitiateArbitrationRequest) returns (InitiateArbitrationResponse);
  rpc GetAuditLog(GetBuyerAuditLogRequest)            returns (GetBuyerAuditLogResponse);
}
```

| Message | Fields |
|---|---|
| `RegisterCompanyRequest` | `firebase_id_token string`, `public_key_pem string` |
| `RegisterCompanyResponse` | `api_key string` |
| `PlaceRequestRequest` | `api_key string`, `budget double`, `token_price double`, `evaluation_script string`, `evaluation_script_runtime string`, `company_message string`, `expires_at int64`, `blocked_sellers repeated string` |
| `PlaceRequestResponse` | `request_id string` |
| `ListRequestsRequest` | `api_key string` |
| `ListRequestsResponse` | `requests repeated Request` |
| `CloseRequestRequest` | `api_key string`, `request_id string` |
| `CloseRequestResponse` | `ok bool` |
| `ListTransfersRequest` | `api_key string`, `request_id string` (optional filter; empty = all) |
| `ListTransfersResponse` | `transfers repeated TransferSummary` |
| `ReceiveTransferRequest` | `api_key string`, `transfer_id string` |
| `ConfirmEvaluationRequest` | `api_key string`, `transfer_id string` |
| `ConfirmEvaluationResponse` | `ok bool` |
| `InitiateArbitrationRequest` | `api_key string`, `transfer_id string`, `decryption_key bytes` |
| `InitiateArbitrationResponse` | `arbitration_id string` |
| `GetBuyerAuditLogRequest` | `api_key string` |
| `GetBuyerAuditLogResponse` | `entries repeated BuyerAuditEntry` |

**BuyerAuditEntry** — see [Audit Log → BuyerAuditEntry](#buyerauditentry) above.

---

### admin.proto

Imports `common.proto`.

```proto
service AdminService {
  rpc ListSellers(ListSellersRequest)             returns (ListSellersResponse);
  rpc BanSeller(BanSellerRequest)                 returns (BanSellerResponse);
  rpc ListCompanies(ListCompaniesRequest)         returns (ListCompaniesResponse);
  rpc BanCompany(BanCompanyRequest)               returns (BanCompanyResponse);
  rpc ReviewArbitration(ReviewArbitrationRequest) returns (ReviewArbitrationResponse);
  rpc ListAlerts(ListAlertsRequest)               returns (ListAlertsResponse);
}
```

| Message | Fields |
|---|---|
| `ListSellersRequest` | `admin_key string` |
| `ListSellersResponse` | `sellers repeated SellerInfo` |
| `BanSellerRequest` | `admin_key string`, `seller_id string` |
| `BanSellerResponse` | `ok bool` |
| `ListCompaniesRequest` | `admin_key string` |
| `ListCompaniesResponse` | `companies repeated CompanyInfo` |
| `BanCompanyRequest` | `admin_key string`, `company_id string` |
| `BanCompanyResponse` | `ok bool` |
| `ReviewArbitrationRequest` | `admin_key string`, `arbitration_id string` |
| `ReviewArbitrationResponse` | `entry AuditEntry` |
| `ListAlertsRequest` | `admin_key string`, `since_id string` (empty = return all unread) |
| `ListAlertsResponse` | `alerts repeated AdminAlert` |

**SellerInfo:**

| Field | Type | Description |
|---|---|---|
| `seller_id` | string | |
| `google_email` | string | |
| `reputation_score` | int32 | 0–100 |
| `banned` | bool | |
| `stripe_account_id` | string | |

**CompanyInfo:**

| Field | Type | Description |
|---|---|---|
| `company_id` | string | |
| `google_email` | string | |
| `reputation_score` | int32 | 0–100 |
| `banned` | bool | |

**AuditEntry** — returned by `ReviewArbitration`. Admin-facing view of a single arbitration case;
contains real seller and company IDs (not anonymised).

| Field | Type | Description |
|---|---|---|
| `arbitration_id` | string | |
| `transfer_id` | string | |
| `request_id` | string | |
| `seller_id` | string | Real seller ID (admin-visible only) |
| `company_id` | string | |
| `verdict` | string | `"buyer_wins"` / `"seller_wins"` / `"pending"` |
| `reason` | string | Human-readable ruling reason |
| `tokens_delivered` | int64 | |
| `evaluation_script_hash` | string | SHA-256 hex of evaluation script used |
| `file_infos` | repeated FileInfo | Per-file integrity records; `claim_hash` for admin verification, `file_name` for eval script context |
| `seller_payout` | double | |
| `buyer_refund` | double | |
| `created_at` | int64 | Unix timestamp; when arbitration was initiated |
| `started_at` | int64 | Unix timestamp; when worker picked up the job; 0 if pending |
| `ruled_at` | int64 | Unix timestamp; when ruling was issued; 0 if pending |

**AdminAlert** — returned by `ListAlerts`. Queued by the server for any event requiring admin attention.

| Field | Type | Description |
|---|---|---|
| `id` | string | |
| `type` | string | `"worker_crash"` / `"reputation_below_threshold"` / `"missing_temp_copy"` |
| `payload` | string | JSON context: affected entity ID, score, transfer_id, etc. |
| `created_at` | int64 | Unix timestamp |

---

## GCP Production Deployment

The balancer server runs on a GCP Compute Engine VM. This section documents how it is set up and how to operate it.

### VM Details

| Item | Value |
|---|---|
| VM name | `ralph-vm` |
| GCP project | `ralph-83103` |
| Zone | `europe-west1-b` |
| Machine type | `e2-micro` |
| OS | Debian 12 (bookworm) |
| External IP | `35.240.3.216` *(changes on stop/start — see cert note below)* |

### SSH Access

All SSH is tunnelled through GCP IAP (no public SSH port):

```bash
gcloud compute ssh ralph-vm \
  --tunnel-through-iap --project=ralph-83103 --zone=europe-west1-b
```

### File Locations on VM

| Path | Purpose |
|---|---|
| `/usr/local/bin/balancer-server` | Main server binary |
| `/usr/local/bin/balancer-arbitration` | Arbitration worker binary |
| `/etc/balancer/env` | Environment config (TLS paths, DB path, ADMIN_KEY, listen addrs) |
| `/etc/balancer/server.crt` | TLS certificate (self-signed, IP SAN) |
| `/etc/balancer/server.key` | TLS private key |
| `/var/lib/balancer/balancer.db` | SQLite database |
| `/var/log/balancer/server.log` | Server log |
| `/var/log/balancer/arbitration.log` | Arbitration worker log |
| `/opt/balancer` | Git repository clone |

### Service Management

Both binaries run as systemd services under the `balancer` system user:

```bash
# Status
sudo systemctl status balancer-server balancer-arbitration --no-pager

# Restart
sudo systemctl restart balancer-server balancer-arbitration

# View logs
sudo tail -50 /var/log/balancer/server.log
sudo tail -50 /var/log/balancer/arbitration.log
```

Expected startup lines in `server.log`:
```
balancer-server listening on 0.0.0.0:50051
arbitration-service listening on localhost:50052
```

Expected line in `arbitration.log`:
```
arbitration-worker connected to localhost:50052
```

### Deploying Code Updates

```bash
# On the VM:
cd /opt/balancer && git pull
cd src/balancer-server

sudo env "PATH=$PATH" CGO_ENABLED=1 go build -p 1 \
  -o /usr/local/bin/balancer-server ./cmd/server

sudo env "PATH=$PATH" CGO_ENABLED=1 go build -p 1 \
  -o /usr/local/bin/balancer-arbitration ./cmd/arbitration

sudo systemctl restart balancer-server balancer-arbitration
```

> **Always use `CGO_ENABLED=1`** — `go-sqlite3` requires CGO. A binary built without it will crash immediately with `"Binary was compiled with 'CGO_ENABLED=0'"`.

> **Use `-p 1`** — limits parallelism during build to avoid OOM on the e2-micro (2 vCPU, ~1 GB RAM).

### TLS Certificate

The cert is self-signed and pinned to the VM's external IP via a Subject Alternative Name (SAN). It covers:
- `IP:35.240.3.216` (external)
- `IP:127.0.0.1` (localhost — required for arbitration worker ↔ server internal connection)
- `DNS:localhost`

**The cert must be regenerated whenever the VM's external IP changes** (which happens on every stop/start):

```bash
# On the VM — get current IP and regenerate:
VM_IP=$(curl -sf \
  "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" \
  -H "Metadata-Flavor: Google")

sudo openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
  -keyout /etc/balancer/server.key \
  -out    /etc/balancer/server.crt \
  -subj   "/CN=$VM_IP" \
  -addext "subjectAltName=IP:$VM_IP,IP:127.0.0.1,DNS:localhost"

sudo chmod 640 /etc/balancer/server.key
sudo chmod 644 /etc/balancer/server.crt
sudo chown root:balancer /etc/balancer/server.key /etc/balancer/server.crt

# Update /etc/balancer/env if the BALANCER_TLS_CERT/KEY paths changed (they don't, but verify)
sudo systemctl restart balancer-server balancer-arbitration
```

After regeneration, redistribute the new cert to all CLI users (see `specs/README.md` → Live Cloud Server).

### Environment Configuration (`/etc/balancer/env`)

```
DB_PATH=/var/lib/balancer/balancer.db
BALANCER_TLS_CERT=/etc/balancer/server.crt
BALANCER_TLS_KEY=/etc/balancer/server.key
LISTEN_ADDR=0.0.0.0:50051
ARBITRATION_LISTEN_ADDR=localhost:50052
ADMIN_KEY=<secret — stored in password manager>
ARBITRATION_SERVER_ADDR=localhost:50052
ARBITRATION_TLS_CERT=/etc/balancer/server.crt
```

File permissions: `640`, owned `root:balancer`. The `balancer` service user reads it at startup.

### VM Start/Stop

Stopping the VM resets the external IP. Restart procedure:

```bash
# Start
gcloud compute instances start ralph-vm --project=ralph-83103 --zone=europe-west1-b
# Get new IP
gcloud compute instances describe ralph-vm \
  --project=ralph-83103 --zone=europe-west1-b \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
# SSH in and regenerate cert (see above), then redistribute
```

Services are enabled for auto-start (`systemctl enable`) — they start automatically when the VM boots.

---

## Out of Scope (v1)

- No mid-transfer cancellation (kill client to cancel)
- No seller-set pricing
- No continuous sync (one-time export only)
