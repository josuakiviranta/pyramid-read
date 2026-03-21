# pyramid-read

CLI tool for reading markdown files at configurable zoom levels. Survey a document's structure by listing headers, then expand only the sections you need.

## Install

```bash
pip install -e .
```

## Usage

**List headers by depth:**

```bash
pyramid-read file.md "#"    # all top-level headers
pyramid-read file.md "##"   # top-level and second-level headers
pyramid-read file.md "###"  # headers up to depth 3
```

**Expand a section (returns full content including subsections):**

```bash
pyramid-read file.md "## Authentication"
pyramid-read file.md "# Overview"
```

## Example

```
$ pyramid-read docs/spec.md "#"
# Balancer Server Spec

$ pyramid-read docs/spec.md "##"
# Balancer Server Spec
## Overview
## Tech Stack
## Authentication
## Request Lifecycle

$ pyramid-read docs/spec.md "## Authentication"
## Authentication

### Sellers
- Register via Firebase Authentication...

### Companies (Buyers)
- Register via Firebase Authentication...
```

## The idea

Inspired by pyramid image formats and map tiles — zoom out to survey, zoom in to read. An AI agent can enumerate hundreds of section headers cheaply, identify what's relevant, then expand only those sections. Avoids loading entire documents into context.
