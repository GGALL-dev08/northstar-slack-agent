# Slack communications agent — n8n prototype

A fictional-company communications assistant using three visual n8n workflows, PostgreSQL, and an owner-restricted Slack direct-message bridge. This is a prototype for experimentation, not a production-ready or enterprise-certified system.

## What is included

- `slack-demo/`: a Socket Mode bridge, example Slack app manifest, and credential setup helper.
- `workflows/` and `all-workflows.json`: the three importable n8n workflow definitions for style fingerprints, sorting, and chat/drafting.
- `source/`: the workflow builder, logic, and routing code.
- `database/` and `fixtures/`: the PostgreSQL schema and clearly labeled fictional-company data.
- `artifacts/`: a separate PDF/PPTX generator used by document-related workflow paths.
- `tests/`: local logic and database regression tests. [NODE-GUIDE.md](NODE-GUIDE.md) explains each workflow node.

## Privacy and configuration

No Slack tokens, OpenRouter keys, database passwords, or real workspace/user/app IDs are included. The public workflow exports contain **no n8n credential bindings**. Slack IDs in the bridge are nonfunctional placeholders. Before use, a developer must supply their own restricted Slack app, workspace/user/app IDs, private credentials, n8n credential bindings, isolated database, internal bridge authentication, network, and service configuration. Review all workflow node and inter-workflow references after importing. Never commit actual credentials or real company messages.

The Slack bridge expects a pre-created, owner-only `slack-demo/private/bridge-secret` file containing a long random secret shared with the n8n webhook credential. The helper writes the Slack tokens to a local `private/config.json` with owner-only permissions; this file is not encrypted and is excluded from Git. Review the helper and deployment configuration before use. The example Compose configuration assumes a compatible local n8n Docker network and an n8n image containing the relevant Slack SDK packages; it is not a turnkey cloud deployment.

## Current scope

Only the owner-allowlisted Slack direct-message path was exercised locally. Ordinary questions can use a low-cost OpenRouter model when explicitly enabled and budgeted. Example company drafting is a synthetic, unverified dry run; external email/LinkedIn delivery and interactive Slack approval buttons are not connected. PostgreSQL full-text and trigram search provide retrieval; semantic embeddings are not implemented. Style statistics are experimental and have not been calibrated for accuracy. Always review generated content.

## Local checks

```sh
node --test tests/logic.test.cjs tests/consolidation.test.cjs
```

The SQL tests are designed for an isolated test database; inspect them before running. Workflow exports may reference inactive placeholders and must not be activated until credentials, connections, permissions, and destination controls have been reviewed. The `source/` builder uses nonfunctional credential-ID placeholders; generated workflows need credentials rebound in the target n8n instance.
