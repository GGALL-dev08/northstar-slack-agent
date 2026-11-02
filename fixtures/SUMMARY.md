# Corpus summary

Created a hand-authored fictional communications fixture for Northstar Relay / RelayGrid. No external dataset text, Enron mail, real customer names, account setup, browser interaction, or paid model calls were used. The sample content is written directly as synthetic fixtures; it is not actual human-authored evaluation data.

- 100 approved outbound reference samples: 25 each email, LinkedIn message, LinkedIn post, and report.
- 20 mixed stream events covering inbound prompt injection/spoofing, unapproved internal pricing, a false certification claim, duplicate delivery, a draft edited after approval, an expired metric, and safe evaluation guidance.
- 12 RAG chunks with `public_approved`, `client_approved`, and `internal_only` classification, audience restrictions, tenant ID, validity dates, and explicit external-sharing boundaries.
- All records use `tenant_id=northstar_demo`. Gold timestamps are normalized to September–October 2026, before the fixture date of 2026-10-31. Each gold record carries `synthetic`, `confirmed_sent`, and `human_approved` scenario labels; these are not real sends or human review. The company facts and sample limits are in `README.md`.

## Suitability search

Public web searches queried:

1. `fictional company email Slack dataset synthetic open license dataset communications benchmark`
2. `open licensed synthetic email Slack dataset company communications dataset GitHub`
3. `LinkedIn posts email Slack dataset synthetic fictional company training`

The results surfaced candidates such as [jie311/synth-data](https://github.com/jie311/synth-data) (synthetic email/chat e-discovery generator), [teamshift-io/smb-sandbox](https://github.com/teamshift-io/smb-sandbox) (fictional business inbox and agent simulator), and [peterzat/OrgSmith](https://github.com/peterzat/OrgSmith) (synthetic company files and email). Search snippets did not establish a directly reusable, openly licensed set spanning all requested outbound media, with approval metadata and audience/validity controls. These candidates were therefore not imported. The [Sinabis synthetic email collection](https://huggingface.co/datasets/sinabis-group/sinabis-10m-synthetic-emails) surfaced as email-focused and did not establish coverage of the required LinkedIn/report media or approval labels.

Firecrawl CLI was unauthenticated. Agent-reach `doctor` reported no active LinkedIn backend and identified Jina Reader as the available public web reader; read-only Jina requests to the candidate pages returned no content in this environment. No accounts or browser session were accessed. This was a quick suitability scan, not an exhaustive dataset/license audit.

Schema details, fixed facts, provenance, and CC0 dedication are in `README.md`.
