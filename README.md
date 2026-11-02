# Northstar Slack Agent

A prototype communications assistant built with three n8n workflows, PostgreSQL, and a Slack direct-message bridge. The included company data is synthetic.

- `workflows/` — importable n8n workflows
- `slack-demo/` — Slack bridge and setup
- `database/` and `fixtures/` — schema and sample data
- `source/`, `artifacts/`, and `tests/` — workflow code, document service, and tests

Configure your own credentials and Slack workspace IDs before use. Drafts need human review; external delivery and automated fact verification are not fully connected.

Run JavaScript tests with `node --test tests/logic.test.cjs tests/consolidation.test.cjs`.
