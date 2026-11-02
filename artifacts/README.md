# Internal artifact compiler

`POST http://artifacts:8000/compile` with `Content-Type: application/json` and `X-Artifact-Token: <ARTIFACT_TOKEN>`. The token must contain at least 24 characters. Missing/incorrect authentication returns 401. `GET /health` is unauthenticated and returns only status and review requirement.

Request:

```json
{
  "artifact_id": "asset_42",
  "channel": "pptx",
  "title": "Quarterly results",
  "body": "Optional report or fallback single-slide body",
  "slides": [
    {"title": "Latency results", "body": "Verified context", "bullets": ["P99 latency improved 42% [chunk_1]"], "speaker_notes": "Evidence: chunk_1"}
  ]
}
```

For `channel: "report"`, `body` is required and the result is a PDF. Blank-line paragraphs and line breaks are retained; all source markup is escaped. Markdown syntax is treated as literal text. For `channel: "pptx"`, omit `slides` for a single slide derived from title/body, or provide 1–12 slides. Each slide requires a title; body, bullets and notes are optional. Optional `banner` accepts a nonempty single line of at most 160 characters and appears visibly on every PDF page and PPTX slide. Its safe default is `DRAFT — HUMAN REVIEW REQUIRED`; a caller cannot request an empty banner. Demo callers should supply `SYNTHETIC FIXTURE — NOT APPROVED FOR EXTERNAL USE` and unverified drafts should use `UNVERIFIED DRAFT — DO NOT SEND`.

Success (HTTP 200):

```json
{"filename":"asset_42-<16-character-content-hash>.pptx","mime_type":"application/vnd.openxmlformats-officedocument.presentationml.presentation","base64":"UEs...","sha256":"<64-character-sha256>","size_bytes":12345,"visual_review_required":true}
```

Use the response's base64 as n8n binary content, filename as the download filename, and mime_type as MIME metadata. The service persists the same bytes in `/data`; no server file paths are returned. Fetch a saved artifact using `GET /artifacts/{filename}` with the same `X-Artifact-Token`; it returns the identical JSON envelope after validating the generated filename, file type, byte limit and content-hash prefix. Filenames must be copied from compile metadata, not supplied as arbitrary paths. Symlinks, encoded paths, query strings and nested paths are rejected. `/health` is the only public endpoint. There are no external delivery endpoints. All channels remain disconnected until separately configured and authorized.

Limits: 1 MiB request, 5 MiB compiled artifact, 100 MiB total storage, one compiler operation at a time, 12 slides, 8 bullets per slide, 240 characters per bullet. Identifiers accept only ASCII letters, digits, underscore and hyphen (1–64 characters; first character alphanumeric). Title/body/notes and JSON schemas are validated. There is no URL fetching, shell execution, arbitrary path input, HTML interpretation, or external network client.

Failures return `{"error":"..."}` with 400 validation, 401 authentication, 409 persisted filename conflict, 411 missing/ambiguous Content-Length, 413 size limit, 415 content type, 500 compilation error, 503 busy or 507 storage quota. Caller retries must be bounded. This is internal service authentication; it does not authorize external distribution.

Container: mount a named volume at `/data`, set a strong `ARTIFACT_TOKEN` secret, and attach only to a Docker `internal: true` network shared with n8n. Do **not** add a `ports:` host mapping. Container listens on port 8000 and runs as UID 10001. The current local integration has already built and started this service on the existing n8n network, with authentication and no host port. A dedicated internal service network is the deployment recommendation; the current shared network is not declared `internal: true`. The delivered base-image digest is pinned.

Dependencies are pinned to published [python-pptx 1.0.2](https://pypi.org/project/python-pptx/1.0.2/) and [ReportLab 4.4.10](https://pypi.org/project/reportlab/4.4.10/) (verified 2026-10-31). ReportLab's bundled Vera font avoids a system-font installation; full CJK/emoji font coverage is not provided.

Run smoke tests from this directory with an environment containing the requirements plus the test-only PDF reader `pypdf` (available in the bundled Codex runtime):

```sh
python -m unittest -v test_server.py
```

The two synthetic examples were rendered and visually checked; see `examples/QA.md`. Automated per-artifact rendering, font substitution, text overflow/collision checks and production visual approval remain **pending**. The simple layout is a draft artifact, not a validated corporate template. The service always returns `visual_review_required: true` for both formats and makes no claim that a model has approved the facts or layout. No LibreOffice or rendering downloads are included.
