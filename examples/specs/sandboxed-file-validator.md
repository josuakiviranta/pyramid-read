# Sandboxed File Validator — Goja + Starlark

A Go package for running untrusted JavaScript or Starlark scripts against files in a sandboxed environment. Used by `balancer-seller-cli` (evaluation and anonymisation) and `balancer-server` (arbitration). Also ships as a standalone `file-validator` CLI for local testing.

## Project Structure

```
src/sandboxed-file-validator/
├── sandbox/                  # Core sandbox package
│   ├── types.go              #   ValidationResult, AnonymisationResult, Runtime interface, ProgressEvent, Option
│   ├── allowlist.go          #   Plain-text extension allowlist + IsAllowedExtension
│   ├── safelib.go            #   Safe file/CSV/JSONL library + HashFile
│   ├── pii.go                #   StripPII / HasPII — 6-stage regex pipeline
│   ├── goja_runtime.go       #   JavaScript sandbox (Goja)
│   └── starlark_runtime.go   #   Python-like sandbox (Starlark)
├── cmd/file-validator/       # Standalone CLI
│   └── main.go
├── examples/                 # Reference scripts to copy and modify
│   ├── revenue-check.js
│   ├── revenue-check.star
│   ├── jsonl-no-old-timestamps.js
│   └── jsonl-no-old-timestamps.star
├── data/                     # Sample data
│   ├── sales.csv
│   └── sample.jsonl
└── go.mod

```

## CLI

### Building

```bash
cd src/sandboxed-file-validator
./build-filevalidator-binary.sh
```

Sellers receive a pre-built binary — Go is not required on the seller's machine.

### Running

```bash
./file-validator [--anonymise] <script.js|script.star> <dir> [dir...]
```

Example:

```bash
./file-validator examples/revenue-check.js ./data
./file-validator examples/revenue-check.js ./data ./archive ./uploads
./file-validator --anonymise examples/revenue-check.js ./data
```

Output (without `--anonymise`):

```
/path/to/file.csv
  file validating...
  hashing...
  evaluating...
  tokens:42  PASS  sha256:a3f1c2b4d5e6...
/path/to/bad.csv
  file validating...
  hashing...
  evaluating...
  tokens:n/a  FAIL  (CSV parse error: ...)
/path/to/report.numbers
  file validating...
  tokens:n/a  FAIL  (file type not allowed: .numbers is not a supported plain-text format)

--- 3 file(s): 1 pass, 2 fail ---
```

Output (with `--anonymise`, seller-side pipeline):

```
/path/to/file.csv
  file validating...
  anonymising: stripping PII...
  evaluating...
  hashing...
  tokens:42  PASS  sha256:<hash-of-anonymised-content>

--- 1 file(s): 1 pass, 0 fail ---
```

Progress phases are printed before each pipeline step. Binary/rejected files print `file validating...` then fail immediately. The result line shows:
- **tokens** — approximate token count using `ceil(bytes / 4)`; `n/a` for any FAIL or rejected file
- **sha256** — SHA-256 of the evaluated content (raw without `--anonymise`, anonymised with); only shown on PASS

`--anonymise` activates the full seller-side pipeline: PII stripping runs before the evaluation script, and the hash reflects the anonymised content the buyer will receive. Omit this flag on the buyer side and in arbitration to avoid re-anonymising already-anonymised content (which would produce incorrect hashes).

### File type allowlist

Validators only process plain-text files. Binary and compressed formats are rejected immediately — binary content is not meaningful to evaluation scripts and produces incorrect token counts.

Allowed extensions: `.csv` `.tsv` `.json` `.jsonl` `.txt` `.md` `.log` `.js` `.ts` `.go` `.py` `.rb` `.html` `.xml` `.yaml` `.yml` `.toml` `.star`

Any other extension produces an instant `FAIL` with a descriptive error. No sha256 is shown — hashing is skipped for rejected files.

## Writing a Validation Script

Scripts receive two pre-injected globals:

| Global | Value |
|---|---|
| `FILE_PATH` | Full absolute path of the current file |
| `FILE_NAME` | Base filename only |

Scripts must call `emit(true)` / `emit(false)` (JS) or `emit(True)` / `emit(False)` (Starlark) to signal pass or fail. If the script errors or never calls `emit`, the file is marked as fail with the error message.

### JavaScript example (`validate.js`)

```javascript
var content = readFile(FILE_NAME);
var rows = parseCSV(content);

var hasRevenue = rows.length > 0 && rows[0].hasOwnProperty("revenue");
var allPositive = filterRows(rows, function(row) {
    return parseFloat(row.revenue) <= 0;
}).length === 0;

emit(hasRevenue && allPositive);
```

### Starlark example (`validate.star`)

```python
content = read_file(FILE_NAME)
rows = parse_csv(content)

has_revenue = len(rows) > 0 and "revenue" in rows[0]
all_positive = len(filter_rows(rows, lambda r: float(r["revenue"]) <= 0)) == 0

emit(has_revenue and all_positive)
```

## Available Library Functions

Both runtimes expose the same safe library — these are the **only** functions scripts can call:

| JS | Starlark | Description |
|---|---|---|
| `readFile(name)` | `read_file(name)` | Read a file from the same directory as the validated file |
| `parseCSV(content)` | `parse_csv(content)` | Parse CSV text into rows (array/list of dicts); `.csv` and `.tsv` files only — errors immediately on any other extension |
| `parseJSONL(content)` | `parse_jsonl(content)` | Parse newline-delimited JSON into rows; blank lines skipped; values coerced to string; `.jsonl` files only — errors immediately on any other extension |
| `filterRows(rows, fn)` | `filter_rows(rows, fn)` | Filter rows with a predicate function |
| `groupBy(rows, col)` | `group_by(rows, col)` | Group rows by column value |
| `stats(rows, col)` | `stats(rows, col)` | Compute `{count, sum, mean, min, max, stddev}` |
| `emit(value)` | `emit(value)` | Record the result — pass `true`/`false` to pass/fail (validation) or `string` (anonymisation) |

Anonymisation scripts also receive `CONTENT` — the pre-stripped file text after the built-in PII pass — and must call `emit(string)` with the final transformed content.

## What Scripts Cannot Do

- Read files outside the validated file's own directory
- Access the network
- Access environment variables or OS
- Run forever (30 s timeout in JS, 60 M step limit in Starlark — limits are sized to allow complex scripts processing large files; the step count is set 2 M steps/s × 30 s to keep Starlark roughly equivalent to the JS wall-clock budget)
- Import external modules
- Use non-deterministic globals — `Math.random` and `Date` are stripped from the Goja VM at initialisation; Starlark is deterministic by design

## Go API

```go
import "github.com/balancer/sandboxed-file-validator/sandbox"
```

Both runtimes implement the same interface:

```go
type Runtime interface {
    Analyze(filePath, script string) ValidationResult
    AnalyzeContent(filePath, content, script string) ValidationResult
    Anonymise(filePath, script string) AnonymisationResult
}
```

```go
js   := sandbox.NewGojaRuntime()       // JavaScript — 30 s timeout
star := sandbox.NewStarlarkRuntime()   // Starlark   — 60 M step limit

// With optional progress callback:
js = sandbox.NewGojaRuntime(sandbox.WithProgress(func(e sandbox.ProgressEvent) {
    fmt.Printf("[%s] %s\n", e.Phase, filepath.Base(e.FilePath))
}))
```

### Analyze

Run a validation script against a file:

```go
result := js.Analyze("/path/to/file.csv", scriptString)
// result.Pass   bool   — true if emit(true) was called
// result.Path   string — file path
// result.Hash   string — SHA-256 of the raw file bytes
// result.Err    string — set if the script errored or never called emit()
```

### AnalyzeContent

Evaluate pre-loaded content rather than reading from disk. Use after `Anonymise()` — the hash in the result reflects the provided content:

```go
// AnalyzeContent evaluates pre-loaded content rather than reading from disk.
// Use after Anonymise() — the hash in the result reflects the provided content.
result := js.AnalyzeContent("/path/to/file.csv", anonymisedContent, scriptString)
// result.Pass   bool   — true if emit(true) was called
// result.Path   string — file path
// result.Hash   string — SHA-256 of content (not the file on disk)
// result.Err    string — set if the script errored or never called emit()
```

#### Seller-side usage (after anonymisation)

```go
anonResult := rt.Anonymise("/home/user/data/report.csv", customScript)
evalResult := rt.AnalyzeContent("/home/user/data/report.csv", anonResult.Content, evalScript)
// Hash reflects anonymised content — same bytes the buyer will receive
```

#### Server-side usage (arbitration)

After decrypting the seller's stored encrypted copy in memory, pass the decrypted bytes directly.
Do **not** call `Analyze()` — the decrypted content is already in memory and no temp file should be written to disk.

```go
// filePath must carry the original file_name so parseCSV/parseJSONL extension guards work
// and FILE_PATH/FILE_NAME globals are meaningful to the eval script.
// Construct it from the file_infos[i].file_name stored at transfer time.
filePath := fileInfo.FileName // e.g. "report.csv"
result := rt.AnalyzeContent(filePath, string(decryptedBytes), evaluationScript)
if !result.Pass {
    // submit buyer_wins / evaluation_failed
}
```

`filePath` in this context does not need to exist on disk — it is used only for:
- `FILE_PATH` global injected into the script
- `FILE_NAME` global (basename of `filePath`)
- Extension guards on `parseCSV()` (requires `.csv`/`.tsv`) and `parseJSONL()` (requires `.jsonl`)

### Anonymise

Strip built-in PII, then optionally run a custom script to further transform the content:

```go
result := js.Anonymise("/path/to/file.csv", customScript)
// Pass customScript = "" to run PII stripping only, without starting a VM.

// result.Content      string — anonymised text, ready for evaluation/encryption
// result.OriginalHash string — SHA-256 of the raw file bytes before any transformation
// result.Path         string — file path
// result.Err          string — set on error
```

The built-in PII stripper runs in 6 stages before any custom script sees the content. It replaces detected PII with typed tokens so downstream scripts can reason about what was removed:

| Token | What it replaces |
|---|---|
| `[EMAIL]` | Email addresses |
| `[ID]` | National IDs (BSN, SSN, Codice Fiscale, DNI, NINO, etc.), credit cards, IBANs, crypto addresses, IPv4/6, MAC addresses |
| `[PHONE]` | Phone numbers |
| `[ADDRESS]` | Postal codes, street addresses |
| `[NAME]` | Title-prefixed names (Mr/Dr/…), capitalised two/three-word sequences (high false-positive risk — documented limitation) |

Custom anonymisation scripts receive the pre-stripped text as `CONTENT` and must call `emit(string)` with the final content.

### Progress Events

Runtimes emit a `ProgressEvent` at the start of each pipeline phase. Pass `WithProgress` to observe them:

```go
rt := sandbox.NewGojaRuntime(sandbox.WithProgress(func(e sandbox.ProgressEvent) {
    fmt.Printf("[%s] %s\n", e.Phase, e.FilePath)
}))
```

| Phase | Emitted before | `Message` |
|---|---|---|
| `PhaseChecking` | Extension allowlist check | `""` |
| `PhaseHashing` | SHA-256 computation (AnalyzeContent: fires after eval) | `""` |
| `PhaseAnonymising` | PII strip | `"stripping PII"` |
| `PhaseAnonymising` | Custom anonymisation script | `"running custom script"` |
| `PhaseEvaluating` | Eval script VM execution (AnalyzeContent: fires first) | `""` |

`PhaseAnonymising` fires twice in `Anonymise` when a custom script is provided — once before `StripPII` and once before the VM runs. `PhaseEvaluating` fires in both `Analyze` (after `PhaseHashing`) and `AnalyzeContent` (before `PhaseHashing`). Callers that do not need progress omit `WithProgress` entirely — no callback, no overhead.

### Allowlist check

```go
ok := sandbox.IsAllowedExtension(".csv") // true
```

Binary and non-plain-text extensions return `false` and are rejected before any VM is started.

---

## Security Model

```
Layer 1: Runtime sandbox   → only the above functions are exposed
Layer 2: Path sandboxing   → readFile() strips path traversal (../etc/passwd blocked)
Layer 3: Resource limits   → 30 s timeout (Goja) / 60 M steps (Starlark)
Layer 4: No shared state   → fresh VM per file, no state leaks between runs
Layer 5: Extension guards  → parseCSV/parseJSONL fail immediately on wrong file type
```

## Token Count Approximation

Token counts shown in CLI output are approximate. The `tokenizer/` package has been removed; the CLI now uses `ceil(byteCount / 4)` as a fast, dependency-free estimate. This avoids embedding an ~11 MB vocab file in the binary while providing a good-enough signal for cost estimation purposes.

## Goja (JS) vs Starlark

| Aspect | Goja (JS) | Starlark |
|---|---|---|
| Syntax | JavaScript | Python-like |
| Sandboxing | Manual (strip globals) | Built-in (no I/O at all) |
| Infinite loop protection | Timeout timer | Built-in step limit |
| Determinism | No (`Date`, `Math.random` exist) | Yes (fully deterministic) |
| Immutability | Mutable by default | Immutable by default |
| Module system | None by default | None by design |
