# pyramid-read

CLI tool for reading markdown files at configurable zoom levels. Survey a document's structure by listing headers, then expand only the sections you need.

## Install

```bash
pip install -e .
```

## Usage

**List all headers:**

```bash
pyramid-read file.md "#"    # all headers at every depth
```

**Expand a section (returns full content including subsections):**

```bash
pyramid-read file.md "## Authentication"
pyramid-read file.md "# Overview"
```

## Example

```
$ pyramid-read docs/spec.md "#"
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
```

## The idea

Inspired by pyramid image formats and map tiles — zoom out to survey, zoom in to read. An AI agent can enumerate hundreds of section headers cheaply, identify what's relevant, then expand only those sections. Avoids loading entire documents into context.
