# pyramid-read

CLI tool for reading markdown files at configurable zoom levels. Survey a document's structure by listing headers, then expand only the sections you need.

## Requirements

- Python 3.8+

## Install

```bash
git clone https://github.com/josuakiviranta/pyramid-read.git
cd pyramid-read
pip install .
```

## Usage

**List all headers in a file:**

```bash
pyramid-read file.md
```

**Expand a section (returns full content including subsections):**

```bash
pyramid-read file.md "## Authentication"
pyramid-read file.md "# Overview"
```

**Survey a folder (each .md file with headers at depth ≤ 2):**

```bash
pyramid-read docs/
```

## Example

```
$ pyramid-read docs/spec.md
# Document name
## Overview
## Tech Stack
## Authentication
### Users
### Admins
## Request Lifecycle

$ pyramid-read docs/spec.md "## Authentication"
## Authentication

### Users
- Register via Firebase Authentication...

### Admins
- Register via Firebase Authentication...

$ pyramid-read docs/
docs/spec.md

# Document name
## Overview
## Tech Stack
## Authentication
## Request Lifecycle

docs/other.md

# Other Doc
## Setup
```

## The idea

Inspired by pyramid image formats and map tiles — zoom out to survey, zoom in to read. An AI agent can enumerate hundreds of section headers cheaply, identify what's relevant, then expand only those sections. Avoids loading entire documents into context.
