# Balancer — Data Flow Reference

How data moves through the Balancer network: from a buyer placing a request to a seller delivering
encrypted files, confirming evaluation, and receiving payment. Also covers the arbitration path.

---

## Normal Flow (no dispute)

```
BUYER                        BALANCER                        SELLER
  |                              |                              |
  |-- PlaceRequest ------------->|                              |
  |   (budget, token_price,      |-- hash eval_script           |
  |    eval_script,              |   lock token_price_snapshot  |
  |    eval_script_runtime)      |   charge budget to escrow    |
  |                              |                              |
  |                              |-- GetPendingRequests ------->|
  |                              |   (eval_script,              |
  |                              |    eval_script_runtime,      |
  |                              |    public_key)               |
  |                              |                              |
  |                              |<-- RespondToRequest (accept) |
  |                              |                              |
  |                              |          [seller selects files]
  |                              |          [anonymise locally  ]
  |                              |          [run eval in Goja   ]
  |                              |          [seller approves    ]
  |                              |          [compute claim hashes]
  |                              |          [generate K         ]
  |                              |          [encrypt files with K]
  |                              |                              |
  |                              |<-- StartTransfer ------------|
  |                              |    (token_count,             |
  |                              |     file_infos[])            |
  |                              |   store claim hashes         |
  |                              |   store encrypted copy       |
  |<-- ReceiveTransfer ----------|<-- encrypted stream ---------|
  |                              |                              |
  |                              |<-- K_buyer (K enc w/ buyer   |
  |                              |    public key) --------------|
  |<-- K_buyer delivered --------|                              |
  |                              |                              |
  | [decrypt K_buyer → K]        |                              |
  | [decrypt files with K]       |                              |
  | [run eval script locally]    |                              |
  |                              |                              |
  |-- ConfirmEvaluation -------->|                              |
  |                              |-- pay seller (Stripe)        |
  |<-- refund remainder ---------|-- delete encrypted copy      |
```

---

## Arbitration Flow (buyer disputes)

```
BUYER                        BALANCER                        SELLER
  |                              |                              |
  | [eval script fails locally]  |                              |
  |                              |                              |
  |-- InitiateArbitration ------>|                              |
  |   (transfer_id, K)           |                              |
  |                              |-- decrypt encrypted copy     |
  |                              |-- verify claim hashes        |
  |                              |-- run eval script (Goja/Starlark) |
  |                              |                              |
  |                              | buyer_wins                   |
  |                              | (eval fails / hash mismatch) |
  |<-- refund ------------------|-- seller rep -10             |
  |                              |                              |
  |                              | seller_wins                  |
  |                              | (eval passes / wrong key)    |
  |   buyer rep -10 ------------|-- pay seller in full         |
  |                              |                              |
  |                              |-- delete K + encrypted copy  |
```

---

## Stage-by-Stage Description

### 1. Request Placement (Buyer → Balancer)

The buyer submits a request via `PlaceRequest` containing:
- **budget** — maximum total spend, charged to Stripe escrow immediately; never disclosed to sellers
- **token_price** — per-token rate offered to sellers; locked as `token_price_snapshot` at request placement; visible to sellers in `GetPendingRequests`
- **evaluation_script** — JS or Starlark source that defines what files qualify
- **evaluation_script_runtime** — `"js"` or `"starlark"`; runtime selected by file extension
- **company_message** _(optional)_ — human-readable description shown to sellers
- **expires_at** _(optional)_ — auto-close timestamp; no expiry if omitted
- **blocked_sellers** _(optional)_ — anonymised seller IDs to exclude from this request

Balancer SHA-256 hashes the evaluation script on receipt. The hash is the authoritative source of
truth for arbitration — neither party can alter the script after submission.

### 2. Request Broadcast (Balancer → Seller)

`GetPendingRequests` delivers open requests to sellers. Each response includes the full evaluation
script source, the evaluation script runtime, the company message, the buyer's public key, and the
offered `token_price` (per-token rate). The budget is not disclosed to sellers. When committed cost
reaches ≥ 80% of the budget, `budget_nearly_exhausted = true` is included — a signal to sellers
to act quickly; it does not reveal the budget magnitude.

### 3. Seller Pre-Transfer Pipeline (Seller's Machine)

After accepting a request, the seller runs the full pipeline locally before anything leaves:

0. **Sent-files check** — `original_hash` (SHA-256 of raw file) checked against
   `~/.config/balancer/sent-files.json` for the request's company; files already sent to that
   company are skipped; use `--include-sent` to override
1. **Built-in PII anonymisation** — strips emails, phone numbers, national IDs, IBANs, credit cards,
   crypto wallets, MAC/IP addresses; replaced with tokens (`[EMAIL]`, `[PHONE]`, etc.)
2. **Custom anonymisation scripts** — seller's own `.js`/`.star` scripts in
   `~/.config/balancer/anonymise/` run sequentially against the PII-stripped content
3. **Anonymised output written to ephemeral preview folder** — seller can inspect anonymised
   versions before proceeding
4. **Evaluation script** — buyer's script runs in Goja/Starlark sandbox against anonymised content
   in preview folder; files that fail are excluded
5. **Manifest saved** — passing files recorded to `~/.config/balancer/manifests/<request_id>.json`

### 4. Encryption & Key Design (Seller's Machine)

After approval, the seller prepares the payload:

- **Session key K** — random AES-256-GCM key generated per transfer
- **Claim hashes** — SHA-256 of each anonymised file computed *before* encryption; these are the
  binding commitment sent to balancer ahead of the payload
- **File encryption** — each anonymised file encrypted with K (AES-256-GCM)
- **K_buyer** — K encrypted with the buyer's RSA/EC public key; delivered to buyer via balancer at
  stream close; balancer forwards K_buyer but never holds K itself

### 5. Transfer Relay (Seller → Balancer → Buyer)

`StartTransfer` opens a bidirectional gRPC+TLS stream. The seller sends `token_count` and
`file_infos[]` (each: `claim_hash` + `file_name`) first; balancer stores these before the payload arrives. Balancer then:

- Relays encrypted chunks to the buyer's open `ReceiveTransfer` stream in real time (never buffers
  the full file)
- Simultaneously writes the same encrypted bytes to temporary disk storage (used only if arbitration
  is initiated)
- Delivers K_buyer to the buyer in stream completion metadata

Multiple sellers can stream to the same buyer simultaneously; each relay runs in its own goroutine.

### 6. Buyer-Side Decryption & Evaluation

The buyer:

1. Receives K_buyer from stream metadata
2. Persists K_buyer bytes atomically to `<output_dir>/<transfer_id>/.kbuyer` before proceeding —
   enables retry if step 5 fails due to network or process crash; deleted on success
3. Decrypts K_buyer with their private RSA/EC key → session key K
4. Decrypts all received files with K (AES-256-GCM)
5. Runs the same evaluation script locally against the decrypted files

If all files pass → `ConfirmEvaluation` is called automatically.
If any files fail → `InitiateArbitration` is triggered automatically (buyer provides K to balancer).

### 7. Payment Settlement

On `ConfirmEvaluation`:
- `cost = tokens_delivered × token_price_snapshot`
- Stripe Connect payout to seller for `cost`
- Stripe refund to buyer for `budget − cost`
- Temporary encrypted copy deleted immediately

Temp copy TTL: deleted after buyer confirmation, arbitration ruling, or 72-hour expiry — whichever comes first.

### 8. Arbitration

Only the buyer can open arbitration, and only by providing K. Without K, balancer cannot decrypt its
copy and cannot investigate.

See [balancer-arbitration.md](./balancer-arbitration.md) for the full arbitration spec.

Process:
1. Buyer calls `InitiateArbitration(transfer_id, K)`
2. Balancer decrypts temporary copy using K
3. Balancer verifies claim hashes — SHA-256 each decrypted file against `transfers.file_infos[i].claim_hash`
4. If hashes match, balancer runs the evaluation script (Goja/Starlark) against the decrypted files
5. Ruling issued; K deleted from memory immediately; encrypted copy deleted

Outcomes:
- **`buyer_wins`** — eval fails, seller swapped files (hash mismatch), or temp copy missing;
  buyer refunded in full; seller reputation -10
- **`seller_wins`** — eval passes (buyer lied) or buyer provided wrong key;
  seller paid in full; buyer reputation -10
- **48h non-cooperation** — buyer did not initiate; auto-settled; seller paid in full

---

## Key Properties

- **Blind relay by default** — balancer holds an encrypted copy but has no key outside arbitration
- **Buyer must provide K to open arbitration** — incentivises honest reporting
- **Seller commits via claim hashes before payload** — cannot swap files after streaming begins
- **PII stripped on seller's machine** — anonymised content never contains raw personal data
- **Evaluation script is buyer-authored but balancer-hashed** — neither party can alter it post-submission
- **Same sandbox on all three sides** — Goja JS / Starlark on seller-cli, buyer-cli, and server
  guarantees consistent evaluation results
- **Payment trigger is buyer confirmation** — not token count matching; token count is recorded for
  cost calculation only
