# Balancer — Secure Data Flow Reference

> **Status:** Validated reference. Claims verified 2026-03-12 across 7 domains.
> **Source:** Distilled from `specs/secure-data-flow-thoughts.md` with independent validation.
> **Next step:** Use as basis for implementation plan in a future session.
> **Validation notes:** See Appendix for corrections to the original document.

---

## 1. Scheme Overview

The Shamir SSS scheme addresses one gap in the current K_buyer scheme: protection against a
compromised or malicious Balancer operator. Under K_buyer, a rogue Balancer that logs every K
value provided during arbitration accumulates decryption keys for all past transfers. Under Shamir
SSS, Balancer's share[1] alone is cryptographically useless — no K can be recovered without the
buyer's share[0].

The scheme involves three parties: **Alice** (Seller), **Shane** (Balancer), and **Bob** (Buyer).

**Normal flow:** Alice generates an AES-256-GCM session key K and Shamir-splits it into three
shares: share[0] for Bob, share[1] for Shane (held in escrow), and share[2] for Alice (offline
backup). Alice encrypts the files with K, encrypts K with Bob's public key as K_buyer (for
decryption), and encrypts share[0] with Bob's public key for separate delivery. Shane stores
share[1] and the encrypted file copy. Bob receives K_buyer and share[0], decrypts K, decrypts
files, runs the evaluation script, and calls ConfirmEvaluation if files pass. Shane pays Alice and
deletes the escrow on confirmation.

**Arbitration flow:** If Bob's evaluation fails, Bob calls `InitiateArbitration(transfer_id,
share[0])`. Shane combines share[0] (from Bob) with share[1] (from escrow) to reconstruct K.
Shane decrypts the stored copy, verifies claim hashes, runs the evaluation script, and issues a
ruling. K is deleted from memory immediately after ruling; the encrypted copy is deleted after the
ruling regardless of outcome.

---

## 2. Trust Model

### What each party can and cannot do

| Party | Can do | Cannot do |
|-------|--------|-----------|
| Seller (Alice) | Encrypt files; generate K; split K; keep share[2] offline | Alter files after claim hashes are committed; know Bob's identity |
| Balancer (Shane) | Hold share[1] + encrypted copy; reconstruct K during arbitration (with Bob's cooperation); run eval script | Reconstruct K without Bob's share[0]; read stored transfers without buyer cooperation |
| Buyer (Bob) | Decrypt files; initiate arbitration; sabotage by providing wrong share[0] | Alter the evaluation script after request submission; prevent arbitration if Bob acts in bad faith (wrong share → seller_wins) |

### Trust assumption

Balancer is a **trusted arbitrator**, not an adversary. This is the opposite of Signal's threat
model, where the server is treated as honest-but-curious and all protocols are designed so the
server cannot read content even with full compromise. Balancer's core function requires a trusted
party to hold escrow and adjudicate disputes. Signal's architecture cannot be borrowed for this
purpose — the escrow role is deliberately excluded from Signal's design.

### "Balancer alone cannot decrypt" — cryptographic basis

This property is **information-theoretic**, not computational. For a 2-of-3 Shamir SSS over
GF(2^8), the polynomial is degree 1 (a line). A single share is one point on that line. Given
only one point, all possible secrets are equally probable — even an adversary with unlimited
computation learns nothing about f(0). This holds regardless of how powerful the attacker is.
This is stronger than computational security (e.g., RSA hardness), which could theoretically be
broken given sufficient compute.

---

## 3. Data Flow

### Normal Transfer

1. Seller generates a random 256-bit AES-256-GCM session key K.
2. K is Shamir-split (2-of-3): share[0] → Buyer, share[1] → Balancer (escrow), share[2] → Seller (offline).
3. Seller computes SHA-256 claim hashes for each anonymised file and sends them to Balancer ahead of the payload (binding commitment; cannot be changed after streaming begins).
4. Seller encrypts each file with K (AES-256-GCM, fresh random 96-bit nonce per file; wire format: nonce ‖ ciphertext ‖ tag).
5. Seller encrypts K with Buyer's public key (X25519 ECDH + HKDF-SHA256, or RSA-OAEP) → K_buyer; delivered to Buyer via Balancer at stream close.
6. Seller encrypts share[0] with Buyer's public key → delivered with K_buyer.
7. Balancer stores share[1] and a temporary encrypted copy of the files.
8. Buyer receives K_buyer and encrypted share[0]; atomically persists K_buyer to `<output_dir>/<transfer_id>/.kbuyer` before proceeding (enables retry on crash).
9. Buyer decrypts K_buyer → K; decrypts share[0] → share[0] plaintext; decrypts files; runs evaluation script.
10. If evaluation passes: Buyer calls `ConfirmEvaluation`. Balancer pays Seller (Stripe), refunds Buyer remainder, deletes encrypted copy and share[1].

### Arbitration

1. Buyer calls `InitiateArbitration(transfer_id, share[0])`.
2. Balancer retrieves share[1] from escrow; combines share[0] + share[1] via Lagrange interpolation over GF(2^8) → reconstructs K.
3. Balancer decrypts stored encrypted copy with K.
4. Balancer verifies each file's SHA-256 hash against stored claim hashes.
5. If hashes match, Balancer runs the evaluation script (Goja/Starlark) against decrypted files.
6. Ruling issued. K is deleted from memory; encrypted copy and escrow deleted.

**Outcomes:**
- `buyer_wins` — eval fails, hash mismatch, or temp copy missing: Buyer refunded; Seller reputation -10.
- `seller_wins` — eval passes (Buyer lied) or wrong share[0] provided: Seller paid in full; Buyer reputation -10.
- 48h non-cooperation: Buyer did not initiate; auto-settled; Seller paid in full.

---

## 4. Cryptographic Primitives

### AES-256-GCM

- **Recommended:** AES-256-GCM with 96-bit random nonce per encryption.
- **Rationale:** Provides authenticated encryption (confidentiality + integrity) in a single pass. NIST SP 800-38D-specified mode; standard for symmetric file encryption.
- **FIPS 140-3:** Approved (AES: FIPS 197; GCM: SP 800-38D).
- **Go implementation:** `crypto/aes` + `crypto/cipher`; `gcm.Seal(nonce, nonce, plaintext, nil)` (nonce-prepend wire format).
- **Note:** With per-transfer fresh keys, nonce collision risk is negligible (NIST SP 800-38D §8.3: concern arises only after 2^32 encryptions with the same key). Key reuse across transfers must be prevented.

### Key Exchange — X25519

- **Recommended:** X25519 (Diffie-Hellman on Curve25519) with HKDF-SHA256 key derivation.
- **Rationale:** 50–500× faster than RSA-4096 for the key exchange operation. ECDH output is not uniformly random; HKDF derivation after X25519 is mandatory (NIST SP 800-56C Rev 2). Signal uses X25519 exclusively for all key exchanges, validated at production scale.
- **FIPS 140-3:** Approved since February 2023 (NIST SP 800-186). Not approved before 2023.
- **Go implementation:** `golang.org/x/crypto/curve25519`; API: `curve25519.X25519(scalar, point []byte) ([]byte, error)`. Pass 32 random bytes as scalar directly — internal clamping (RFC 7748 §5) applies. `ScalarMult` and `ScalarBaseMult` are deprecated with security warnings; use only `X25519`.
- **Note:** X25519 provides ~128-bit security ≈ RSA-3072 (not RSA-4096; see Appendix correction #1). Both exceed the 112-bit minimum; the practical difference is negligible.

### Key Derivation — HKDF-SHA256

- **Recommended:** HKDF-SHA256 (RFC 5869) applied to the raw X25519 shared secret.
- **Rationale:** Raw ECDH output is not uniformly random and must not be used directly as an AES key (anti-pattern). HKDF-Extract+Expand is the standard derivation step (NIST SP 800-56C Rev 2). Signal uses HKDF-SHA256 for every key derivation step without exception.
- **FIPS 140-3:** Approved (SHA-256: FIPS 180-4; HKDF: SP 800-56C).
- **Go implementation:** `golang.org/x/crypto/hkdf`; constructor: `hkdf.New(sha256.New, sharedSecret, salt, info) io.Reader`; extraction: `io.ReadFull(reader, keyBuf)`. Both `nil` and `[]byte{}` are valid for salt.
- **Note:** nil salt is documented as valid; do not pass the empty string as a non-nil slice unnecessarily.

### Signing — Ed25519

- **Recommended:** Ed25519.
- **Rationale:** 2–10× faster than ECDSA P-256 (no per-operation random scalar; faster field arithmetic). Used by Signal for all identity key signatures. In Go stdlib since 1.13.
- **FIPS 140-3:** Approved since February 2023 (FIPS 186-5). Not approved before February 2023.
- **Go implementation:** `crypto/ed25519` (stdlib ≥1.13); `ed25519.GenerateKey(rand.Reader)`, `ed25519.Sign(privKey, msg) []byte` (no error return), `ed25519.Verify(pubKey, msg, sig) bool`. `golang.org/x/crypto/ed25519` is a compatibility shim for pre-1.13 only; stdlib is preferred.

### Key Wrapping — RSA-OAEP SHA-256

- **Recommended:** RSA-OAEP with SHA-256 (if RSA is retained; X25519 ECDH is preferred for new code).
- **Rationale:** For key transport (wrapping K_buyer). RSA-OAEP is semantically secure. SHA-256 vs SHA-512 in OAEP does not affect security in any practically meaningful way — security is governed by RSA key size, not the hash function (NIST SP 800-56B). SHA-512 OAEP adds overhead with no security benefit.
- **FIPS 140-3:** Approved (RSA ≥2048: NIST SP 800-57; OAEP: SP 800-56B).
- **Go implementation:** `crypto/rsa`; `rsa.EncryptOAEP(sha256.New(), rand.Reader, pub, key, label)`.
- **Note:** The hash function in OAEP affects only message capacity and overhead, not the encryption security. The doc's "SHA-512 is stronger" framing is misleading (see Appendix correction #2).

### Secret Sharing — Shamir 2-of-3 over GF(2^8)

- **Recommended:** Shamir SSS, t=2, n=3, field GF(2^8) with AES irreducible polynomial (reduction constant `0x1b`).
- **Rationale:** Any 2 of 3 shares reconstruct the secret via Lagrange interpolation at x=0. A single share is information-theoretically zero information about the secret. The GF(2^8) reduction constant `0x1b` (x^4+x^3+x+1, low-order byte of AES polynomial x^8+x^4+x^3+x+1) is correct. Horner's method for polynomial evaluation is correct.
- **FIPS 140-3:** Not directly specified; GF arithmetic is standard. Use HashiCorp Vault library (lookup-table implementation, constant-time) rather than custom GF multiplication.
- **Go implementation:** `github.com/hashicorp/vault/shamir`; `shamir.Split(secret, 3, 2) ([][]byte, error)`, `shamir.Combine(shares) ([]byte, error)`. This is the same library used for Vault's unseal mechanism — production quality confirmed.
- **Note:** Custom GF(2^8) multiplication using peasant's algorithm is not constant-time (timing side-channel; see Section 7, M1). The HashiCorp library uses lookup tables. Do not replace it with custom Shamir code.

### Message Authentication — HMAC-SHA256

- **Recommended:** HMAC-SHA256 with `subtle.ConstantTimeCompare` for tag verification.
- **Rationale:** Shamir shares have no self-authenticating structure; Lagrange interpolation over GF(2^8) is fail-open (corrupted share produces wrong key with no error). HMAC-SHA256 provides share integrity. `subtle.ConstantTimeCompare` prevents timing side-channels on tag comparison.
- **FIPS 140-3:** Approved (SHA-256: FIPS 180-4; HMAC: FIPS 198-1).
- **Go implementation:** `crypto/hmac` + `crypto/sha256`; `hmac.New(sha256.New, macKey)`.
- **Note:** The MAC key must be encrypted for Balancer only — not for the Buyer. If Buyer learns the MAC key, Buyer can forge a valid-HMAC'd tampered share and cause a false arbitration outcome (see Section 7, vulnerability #9 and M2).

---

## 5. Library Recommendations

| Purpose | Import Path | Version | Notes |
|---------|------------|---------|-------|
| Shamir SSS | `github.com/hashicorp/vault/shamir` | v1.21.4 | Production-quality; Vault unseal mechanism; MPL-2.0 |
| CMS / PKCS#7 | `go.mozilla.org/pkcs7` | v0.9.0 | **Must set AES algorithm explicitly** (see below) |
| X25519 key exchange | `golang.org/x/crypto/curve25519` | latest | Use `X25519()` only; `ScalarMult`/`ScalarBaseMult` are deprecated |
| Ed25519 signing | `crypto/ed25519` | Go stdlib ≥1.13 | Prefer stdlib over `golang.org/x/crypto/ed25519` shim |
| HKDF | `golang.org/x/crypto/hkdf` | latest | nil salt is valid |
| SQLite at-rest encryption | `github.com/thinkgos/go-sqlcipher` | latest | Maintained fork of mutecomm; CGO required; fix connection string (see below) |

### Critical Notes

**`pkcs7.Encrypt` defaults to DES-CBC.** The default content encryption algorithm is legacy
DES-CBC, not AES. Any code using `pkcs7.Encrypt` without explicitly setting the algorithm will
produce DES-encrypted output — a critical security regression. Before calling `pkcs7.Encrypt`,
set:

```go
pkcs7.ContentEncryptionAlgorithm = pkcs7.EncryptionAlgorithmAES128GCM
```

or another AES variant. The source document does not mention this default; using the library as
shown in the original doc would produce insecure output.

**go-sqlcipher connection string.** The connection string shown in the source document (`_key=your-encryption-key`) is wrong. The correct SQLCipher parameter format is:

```
_pragma_key=x'<64-hex-chars>'&_pragma_cipher_page_size=4096
```

The original `github.com/mutecomm/go-sqlcipher/v4` is stale (last release December 2020). Use the maintained fork `github.com/thinkgos/go-sqlcipher` (active as of April 2025).

---

## 6. Security Properties

### Balancer-alone-cannot-decrypt
**Mechanism:** Information-theoretic Shamir SSS (t=2, n=3). Balancer holds only share[1]; a single GF(2^8) share is statistically independent of the secret.
**Caveat:** This property is specific to the Shamir SSS scheme. Under the current K_buyer scheme, Balancer cannot decrypt in normal operation but can accumulate keys if K values are logged during arbitration.

### Buyer-must-cooperate-for-arbitration
**Mechanism:** Balancer holds only share[1]. Without Buyer's share[0], Balancer cannot reconstruct K and cannot decrypt the stored copy. The `InitiateArbitration` call requires share[0].
**Caveat:** A dishonest Buyer can provide wrong share[0], causing reconstruction to produce the wrong K. Outcome: AES decryption fails → `seller_wins`. This is a feature, not a bug — sabotage by the Buyer triggers the same outcome as the Buyer lying about evaluation failure.

### Seller-commits-via-claim-hashes-before-payload
**Mechanism:** Seller sends SHA-256 claim hashes to Balancer before the encrypted payload stream begins. Balancer stores these. During arbitration, Balancer recomputes hashes after decryption and compares. A Seller who substitutes different files during streaming will have a hash mismatch.
**Caveat:** This property exists in the current K_buyer scheme as well; it is not new to Shamir SSS.

### Share-integrity (HMAC-SHA256)
**Mechanism:** Each share is HMAC-SHA256 authenticated. `subtle.ConstantTimeCompare` used for tag verification to prevent timing side-channels.
**Caveat:** The MAC key must be encrypted for Balancer only. If the Buyer learns the MAC key, Buyer can forge valid-HMAC'd shares during arbitration (see Section 7, vulnerability #9 and M2). The source document's implementation has this flaw.

### Routing-attestation (Balancer signs forwarded packages)
**Mechanism:** Balancer (Shane) signs each forwarded package with its Ed25519 private key. This creates an audit trail proving Balancer forwarded the package unmodified between the Alice→Shane and Shane→Bob relay legs.
**Caveat:** TLS between all parties already prevents in-transit modification. The signature's primary value is non-repudiation and audit, not MITM prevention. The source document's stated rationale ("MITM could modify the package") is partially mitigated by TLS; the fix is still correct but for a different reason.

---

## 7. Known Vulnerabilities & Mitigations

### Vulnerabilities from source document

| # | Vulnerability | Severity | Is Fix Correct? | Correct Mitigation |
|---|--------------|----------|-----------------|--------------------|
| 1 | Bob's share exposed to Shane (share[0] sent plaintext in EncryptedPackage) | CRITICAL | Partial | Encrypt share[0] with Bob's public key on normal delivery path. On the arbitration path, Bob must not send raw share[0] to Shane in cleartext — the `bobInitiateArbitration` function has a TODO comment and passes `bobShare` raw. Fix the arbitration path as well. |
| 2 | Shane has no identity — anyone can impersonate the router | CRITICAL | Yes (with bootstrapping caveat) | Shane generates Ed25519 key pair; signs routed packages. Production requires PKI or out-of-band key distribution for Alice/Bob to receive Shane's public key. The `TrustedKeys` struct simulates pre-distributed PKI — a recognized pattern. |
| 3 | Key plaintext in memory — no zeroing | CRITICAL | Partial | `defer zeroMemory(aesKey)` reduces exposure window. For production: use `clear(b)` (Go 1.21+ compiler intrinsic) + `runtime.KeepAlive(b)` + `unix.Mlock` (swap protection) + `unix.Madvise(MADV_DONTDUMP)` (core dump protection). The doc's `for i := range b { b[i] = 0 }` pattern works today but is not formally guaranteed by the Go spec and provides no swap/dump protection. |
| 4 | Replay attacks on arbitration — no nonce/timestamp | HIGH | Partial (two bugs) | Nonce approach is correct in concept. Two bugs: (1) 5-minute timestamp window is too narrow for async business arbitration with 48h initiation window — use nonce-only or multi-hour window; (2) in-memory `map[string]bool` NonceStore is cleared on restart — nonces must be persisted to the database. |
| 5 | Alice's public key unverified — self-asserted in message body | HIGH | Yes (with PKI dependency) | Pre-distributed `TrustedKeys` is correct. Production requires PKI, CA certificates, or out-of-band key exchange. |
| 6 | Shane doesn't attest routing — no Shane signature on forwarded package | HIGH | Yes (rationale wrong) | Shane signature provides non-repudiation and audit trail, not MITM prevention (TLS already handles that). The fix is correct; the stated rationale in the doc is imprecise. |
| 7 | RSA-2048 aging | MEDIUM | Partial | RSA-2048 is NIST-approved through at least 2030 (112-bit security). Upgrading to RSA-3072+ or X25519 is recommended for new systems. Note: X25519 (DH key agreement) and RSA-OAEP (key transport) serve different purposes; they are not drop-in replacements for each other. |
| 8 | No forward secrecy — long-term RSA keys for key wrapping | MEDIUM | Not implemented | The vulnerability is real. The fix (ephemeral ECDH per session) is architecturally correct. The "robust" implementation in the source document still uses long-term RSA key wrapping — forward secrecy is described as a fix but never applied in the code. |
| 9 | Unauthenticated Shamir shares (fail-open Lagrange interpolation) | MEDIUM | Structurally flawed | HMAC-SHA256 is the correct fix in concept. **Critical implementation flaw:** `ShareMACKey` is encrypted for Bob in the source document. Bob therefore learns the MAC key and can forge a valid-HMAC'd tampered share during arbitration, causing a false `seller_wins` ruling on demand. Fix: encrypt `ShareMACKey` for Shane only. |

### Missing vulnerabilities (not in source document)

| # | Vulnerability | Severity | Mitigation |
|---|--------------|----------|-----------|
| M1 | Timing side-channel in custom GF(2^8) multiplication | MEDIUM | The custom `gf256Mul` uses peasant's algorithm with a variable-iteration loop (key-derived data controls loop count). Not constant-time. The HashiCorp Vault Shamir library uses lookup tables (constant-time). Do not use custom Shamir GF arithmetic. |
| M2 | Bob controls MAC key → share forgery attack | HIGH | Root cause of the #9 flaw stated independently: since `ShareMACKey` is encrypted only for Bob, Bob fully controls the integrity check on his own share. Fix: MAC key encrypted for Shane only, or derive the MAC key in a way that only Shane can know. |
| M3 | AES-GCM random nonce birthday bound | LOW | NIST SP 800-38D §8.3: collision probability reaches 2^{-32} after 2^{32} encryptions with the same key. Per-transfer fresh K makes this a non-issue currently. Constraint: K must never be reused across transfers. |
| M4 | No secure storage guidance for Seller's offline share (share[2]) | LOW | share[2] is assigned as an "offline backup" with no storage mechanism defined. If Seller's machine is compromised, share[2] combined with Balancer's share[1] reconstructs K. Limited threat (requires machine compromise), but the gap is unaddressed. |

---

## 8. Industry Context

### Confirmed exact mappings

- **`shamirSplit()` → KMIP "Split Key" managed object** (OASIS KMIP 2.0, Section 2.2): Exact mapping. KMIP defines a "Split Key" managed object type with a `Split Key Method` attribute whose valid value is `"Shamir's Polynomial Sharing"`. This is not an analogy.

- **Split Knowledge + Dual Control pattern name**: Correct formal name. "Split Knowledge" = no single party knows the complete key. "Dual Control" = two authorized parties must cooperate to use it. This is the terminology used in PCI-DSS and NIST guidance.

- **PCI-DSS v4.0 Requirement 3.7.6**: Requires Split Knowledge and Dual Control for manual cleartext key-management operations on keys protecting cardholder data. Shamir SSS is an accepted implementation.

### Confirmed structural analogies (not exact encodings)

- **`EncryptedPackage` → CMS `EnvelopedData` (RFC 5652)**: Structural analogy. RFC 5652 `EnvelopedData` is the correct CMS type for encrypted content with per-recipient encrypted keys. The custom struct is not literally CMS-encoded.

- **`EncryptedBobShare` → CMS `OtherRecipientInfo`**: Structural analogy. `OtherRecipientInfo` is the RFC 5652 extensibility mechanism for non-standard recipient types. A real implementation would define a custom ASN.1 OID.

- **Architecture → OpenPGP pattern**: The hybrid encryption + signing pattern (session key wrapped with recipient's public key + signature) is the OpenPGP pattern, confirmed accurate. "Architecturally identical to OpenPGP" is an overstatement — wire formats, key certification model, and scope differ. "Structurally analogous" is accurate.

- **RFC 9580**: The current OpenPGP standard (published July 2024), formally obsoleting RFC 4880. Confirmed.

### FIPS 140-3 algorithm status

| Algorithm | FIPS 140-3 Status | Reference |
|-----------|-------------------|-----------|
| AES-256-GCM | Approved | FIPS 197 + SP 800-38D |
| RSA-4096 OAEP | Approved | SP 800-57 + SP 800-56B |
| ECDSA P-256 | Approved | FIPS 186-5 |
| SHA-256 / HMAC-SHA256 | Approved | FIPS 180-4 + FIPS 198-1 |
| Ed25519 | Approved since Feb 2023 | FIPS 186-5 |
| X25519 | Approved since Feb 2023 | SP 800-186 |

### Corrections to source document

- **KMIP "Key Recovery Operation" does not exist.** No KMIP operation has this name. KMIP uses `Locate` (find by attributes) and `Get` (retrieve by ID). Key reconstruction is performed client-side by combining received shares.

- **GCP Secret Manager is not an HSM.** Secret Manager is a secrets vault that encrypts data at rest via Cloud KMS. It provides no hardware-level key isolation, key-non-extractable guarantees, or FIPS 140-2 Level 3 attestation. The correct GCP HSM product is **Cloud HSM** (Cloud KMS with HSM protection level). Secret Manager remains the appropriate practical choice for Balancer's use case, but the HSM equivalence claim is factually wrong.

- **`AliceSignature → CMS SignedData` is structurally misapplied.** In CMS, `SignedData` and `EnvelopedData` are separate top-level content types — `SignedData` cannot be a field inside `EnvelopedData`. The correct CMS pattern is either `SignedData` wrapping `EnvelopedData` (sign-then-encrypt) or `EnvelopedData` wrapping `SignedData` (encrypt-then-sign). The conceptual intent (signing over encrypted content) is valid; the CMS type reference is wrong.

- **eIDAS qualified electronic signature does not apply.** The ECDSA/Ed25519 signatures in this scheme are not eIDAS qualified electronic signatures — they lack a qualified certificate from a trust service provider and a qualified signature creation device. The scheme involves cryptographic signing but is not eIDAS-compliant.

### Signal / SVR3 context

Signal uses X25519 (key exchange), Ed25519 (signing), AES-256-GCM (encryption), HMAC-SHA256 (MAC), and HKDF-SHA256 (key derivation) exclusively — no RSA. This validates the primitive recommendations at production scale in a security-critical application.

SVR3 (Signal's backup encryption system) uses a threshold OPRF-based protocol across three independent cloud providers (Intel TDX/SGX on Azure, AMD SEV-SNP on GCP, Nitro on AWS). The threshold guarantee (2-of-3 providers must cooperate) is real, but SVR3 uses OPRF-based threshold cryptography, not classic Lagrange-interpolation Shamir SSS. "Shamir-style threshold scheme across hardware" is a fair description; "literally Shamir SSS" is not.

SVR3's architecture is over-engineered for Balancer's threat model. SVR3 treats all three providers as potentially adversarial and independently operated. Balancer's model requires a trusted arbitrator. SVR3's complexity is not warranted.

---

## 9. Tradeoffs vs Current K_buyer Scheme

### Comparison

| Property | K_buyer (current) | Shamir SSS |
|----------|-------------------|------------|
| Buyer must cooperate for arbitration | Yes (provides K directly) | Yes (provides share[0]) |
| Buyer can sabotage by providing wrong credential | Yes (wrong K → seller_wins) | Yes (wrong share → same outcome) |
| Balancer alone can decrypt stored transfers | No (never holds K in normal flow) | No (share[1] alone is useless) |
| Compromised Balancer can accumulate decryption keys | Yes — by logging K values received during arbitration | No — share[1] alone cannot reconstruct K |
| Seller can verify Balancer cannot read their data | Only by trusting Balancer's code | Cryptographically provable from share design |
| Implementation complexity | Simple | Significant (Shamir split/combine, HMAC, share encryption for Bob, share escrow for Shane) |
| New attack surfaces | Minimal | HMAC key management; share[0] transmission security; share[2] offline storage |

### The one genuine security property Shamir adds

**Protection against a compromised or malicious Balancer operator.** Under K_buyer, a rogue
Balancer that logs all K values provided during arbitration accumulates decryption keys for all
past transfers. Under Shamir SSS, share[1] alone is information-theoretically useless — a
compromised Balancer cannot read stored transfers regardless of how many arbitrations it has
processed. This property is cryptographically provable, not operationally assumed.

### Honest conclusion

For v1, where Balancer is a trusted operator, Shamir SSS is over-engineering. The K_buyer scheme
is simpler, equally correct against buyer/seller fraud (the primary threat in v1), and much easier
to audit. The only attack it does not address — a malicious Balancer operator logging arbitration
keys — is outside the v1 threat model.

The Shamir SSS scheme is worth implementing if the threat model expands to include a potentially
compromised or untrustworthy Balancer operator (e.g., for regulatory compliance, enterprise
clients, or adversarial deployment environments).

### Implementation costs of Shamir SSS over K_buyer

- Shamir split at transfer time (negligible compute; `hashicorp/vault/shamir` is fast)
- Additional encryption pass for share[0] (Bob's copy, X25519 or RSA-OAEP)
- Share[1] escrow storage in Balancer database (per-transfer row)
- HMAC-SHA256 generation and verification for each share (MAC key management)
- Share[0] delivery to Buyer alongside K_buyer
- Share[0] extraction from arbitration request (instead of K extraction)
- Fix for MAC key exposure (encrypt for Shane only — different from the source doc's implementation)
- Fix for nonce store persistence (database-backed instead of in-memory)

---

## Appendix: Validation Notes

The following claims in `specs/secure-data-flow-thoughts.md` were found to be wrong or
misleading and are corrected here. Silent fixes are not made — these corrections are explicit.

1. **X25519 ≈ RSA-3072, not RSA-4096.** The doc claims X25519 provides the same security level as RSA-4096. Correct: X25519 provides ~128-bit security ≈ RSA-3072 (NIST SP 800-57 Table 2). RSA-4096 ≈ 140-bit. Both exceed the 112-bit practical minimum; the recommendation (prefer X25519) is unaffected, but the stated equivalence is factually wrong.

2. **RSA-OAEP hash function does not affect security meaningfully.** The doc implies SHA-512 OAEP is "stronger than" SHA-256 OAEP for key wrapping. Correct: the hash function in OAEP affects only message capacity and overhead; security is governed by RSA key size. NIST SP 800-56B does not prefer one over the other. The "stronger" framing is misleading.

3. **KMIP "Key Recovery Operation" does not exist by that name.** The doc maps `shaneArbitrate()` to a KMIP "Key Recovery Operation." No such operation exists in OASIS KMIP 2.0. KMIP uses `Locate` and `Get`; key reconstruction is client-side.

4. **GCP Secret Manager is not an HSM.** The doc maps GCP Secret Manager to an HSM. Correct: Secret Manager is a secrets vault. GCP Cloud HSM (part of Cloud KMS with HSM protection level) is the correct HSM product. Secret Manager remains a practical choice for Balancer's key storage, but the HSM equivalence is inaccurate.

5. **`AliceSignature → CMS SignedData` is structurally misapplied.** In CMS (RFC 5652), `SignedData` and `EnvelopedData` are separate top-level content types. They cannot be nested as fields within each other as the doc implies. The correct CMS pattern uses one wrapping the other at the top level (sign-then-encrypt or encrypt-then-sign).

6. **`pkcs7.Encrypt` defaults to DES-CBC — not AES.** The doc uses `pkcs7.Encrypt` without setting the content encryption algorithm. The default is legacy DES-CBC. Any code using the library as shown produces DES-encrypted output. `pkcs7.ContentEncryptionAlgorithm` must be explicitly set to an AES variant before calling `Encrypt`.

7. **go-sqlcipher connection string `_key=` is wrong.** The doc shows `_key=your-encryption-key` as the SQLCipher DSN parameter. The correct format is `_pragma_key=x'<64-hex-chars>'&_pragma_cipher_page_size=4096`. The original `github.com/mutecomm/go-sqlcipher/v4` is also stale; use a maintained fork.

8. **Vulnerability #9 fix is self-defeating.** The fix for unauthenticated Shamir shares encrypts `ShareMACKey` for Bob. This allows Bob to learn the MAC key and forge valid-HMAC'd tampered shares during arbitration — exactly enabling a dishonest buyer to produce a false `seller_wins` ruling on demand. The MAC key must be encrypted for Shane (Balancer) only.

9. **Forward secrecy (#8) is described as fixed but not implemented.** The source doc lists forward secrecy as a fixed vulnerability. The "robust" implementation continues to use long-term RSA key wrapping. Forward secrecy (ephemeral ECDH per session) is not applied in any code shown.

10. **5-minute timestamp window is wrong for async arbitration; in-memory NonceStore is not restart-safe.** A 5-minute freshness window is designed for synchronous auth tokens. Balancer arbitration has a 48-hour initiation window; any network delay, clock skew, or retry within that window would be incorrectly rejected. Additionally, the `map[string]bool` NonceStore is cleared on server restart — any previously-used nonce can be replayed after restart. Nonces must be persisted to the database.

11. **"Architecturally identical to OpenPGP" is too strong.** The hybrid encryption + signing pattern is structurally analogous to OpenPGP, but wire formats, key certification model, and scope differ significantly. "Structurally analogous" is accurate; "architecturally identical" is not.

12. **eIDAS qualified electronic signature does not apply to this scheme.** The cryptographic signatures in the scheme are not eIDAS qualified electronic signatures. Qualified signatures require a certificate chain from a trust service provider and a qualified signature creation device — neither of which this scheme provides.
