# Northstar Relay demo — every n8n node explained

> This guide describes the saved workflow definitions and the last verified demo configuration. It is a walkthrough, not proof that every branch has passed a live end-to-end test.

## A two-minute explanation

Northstar Relay is a fictional B2B company. Its communication assistant has three n8n workflows. Workflow 1 builds versioned style profiles from eligible approved sent examples. Workflow 2 classifies and stores input and prepares held review output. Workflow 3 handles Slack requests, retrieves approved evidence and style, produces drafts, and contains the optional model-verification path.

The Slack demo is not a native n8n Slack Trigger: a separate local Socket Mode bridge receives only the allowlisted user’s DM, then calls an authenticated webhook in Workflow 3. PostgreSQL stores facts, profiles, drafts, jobs, and budget records; a separate local artifact service creates PDFs and PPTX files. All of these are local Docker components, not an always-on cloud deployment.

In the last verified configuration, general conversation can use a paid OpenRouter model under a $0.05/day cap, with a $0.005 reservation per conversation. The drafting workflow remains in dry-run mode, so its synthetic drafts are unverified. Baseten Joey/Mammoth verification is a configured live path; a complete live approval pass and calibrated brand accuracy have not been established. General chat does not use the same fact-verification gate or long-term conversation memory.

**Terminology:** A node is one visible step. An item is the data passed between nodes, usually JSON. A Code node transforms/checks items; PostgreSQL nodes call durable database functions; IF nodes choose a path; HTTP Request nodes call a service; Execute Workflow nodes call one of the three workflows. A pass-through node is a visual handoff. “Disabled” means it will not run until deliberately configured and enabled. Sticky notes provide explanations and are not processing steps. A node being enabled does not mean every path through it has been tested.

**Safety and limits:** The present bridge supports text DM replies, not interactive Slack buttons or live outbound email/LinkedIn delivery. Save/send entries stage work for later; the provider adapters are disconnected. Internal Slack is excluded from the external style corpus. RAG here uses PostgreSQL full-text/trigram retrieval with evidence filters; semantic vector embeddings are deferred. A generated draft needs human review, and references to verified facts still require scrutiny.

## How to walk the group through it

1. In Slack, send a greeting or an ordinary general question. Point out that the response goes from the separate bridge through the authenticated webhook to Workflow 3. A general question may consume a small amount of OpenRouter credit.
2. Ask for an email about the fictional routing-v2 pilot. Show that the response is labeled synthetic and unverified. Explain that actual drafting is still a dry-run fixture rather than a proven live writing model.
3. Open Workflow 1 and trace approval → approved examples → 14 measured statistics → versioned profile. The synthetic bootstrap is a demo-only setup lane.
4. Open Workflow 2 and trace normalization → internal/external classification → idempotent persistence. Show disabled real-source and delivery placeholders.
5. Open Workflow 3 and trace request routing → durable job → evidence/style retrieval → dry-run draft → deterministic gate → saved review. Show Joey/Mammoth as the configured live verification path, not a verified live pass.

## Reading the node lists

Each list below covers every functional node in the saved definition, including disabled placeholders. Names match the labels in n8n. “Next” describes visible connections: for IF nodes, output 0 is the true branch and output 1 is the false branch. For nodes with an error output, output 1 is the error path. A dash means there is no outgoing node in that lane. Rows are roughly in canvas order; long connections may jump between lanes.

## Workflow 1 · Fingerprints & Knowledge

**28 functional nodes**, including 0 disabled placeholders; 4 additional sticky notes explain the layout.

| Node | What it does | Next |
|---|---|---|
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route fingerprint |
| **Internal · route fingerprint** (IF) | If the operation is fingerprint, enter the style path; otherwise check for demo bootstrap. | true: Style · Preview pending sent examples?; false: Internal · route bootstrap |
| **Internal · route bootstrap** (IF) | If the operation is bootstrap, enter the synthetic setup lane; otherwise reject it. | true: Seed · explicit bootstrap entry; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |
| **Seed · Manual test** (Manual trigger) | Manual starting point for explicitly seeding the fictional company; this is not an automatic trigger. | then: Seed · explicit bootstrap entry |
| **Seed · explicit bootstrap entry** (Pass-through) | Pass-through marker that identifies a bootstrap run; a later condition checks whether this node ran. | then: Seed · Load clearly marked synthetic fixture |
| **Seed · Load clearly marked synthetic fixture** (Code) | Loads the bundled fictional company facts and sample outbound communications, marked as synthetic. | then: Seed · Seed approved facts + sent example candidates |
| **Seed · Seed approved facts + sent example candidates** (PostgreSQL) | Calls the database seed function to write the fictional facts and example-message records. | then: Seed · Explicit DEMO approval — fixture examples only |
| **Seed · Explicit DEMO approval — fixture examples only** (PostgreSQL) | Approves eligible synthetic gold examples for the demo, checking their source, sent status, external audience, and content hash; this is not approval of real company messages. | then: Seed · Build five versioned medium profiles |
| **Seed · Build five versioned medium profiles** (Code) | Creates five requests: global, email, LinkedIn message, LinkedIn post, and report. | then: Style · Preview pending sent examples? |
| **Style · Manual test** (Manual trigger) | Manual starting point for the style/fingerprint lane. | then: Style · Demo: compile approved email examples |
| **Style · Demo: compile approved email examples** (Code) | Creates a demo request to compile the approved email samples. | then: Style · Preview pending sent examples? |
| **Style · Preview pending sent examples?** (IF) | Checks whether the user requested a preview; the preview branch does not approve or train on anything. | true: Style · Pending-sent folder — no automatic learning; false: Style · Explicit candidate IDs to approve? |
| **Style · Pending-sent folder — no automatic learning** (PostgreSQL) | Checks operator access and retrieves eligible pending sent examples for review. | then: Style · Slack folder card — one-click fingerprint update |
| **Style · Slack folder card — one-click fingerprint update** (Code) | Builds a proposed Slack review card with candidate examples and update actions. The present text-only Slack bridge does not deliver these interactive buttons. | — |
| **Style · Explicit candidate IDs to approve?** (IF) | Only the update branch with selected example IDs goes to explicit approval; otherwise it loads previously approved examples. | true: Style · Approve only selected current sent examples; false: Style · Load approved current examples — medium scoped |
| **Style · Approve only selected current sent examples** (PostgreSQL) | Calls the database approval function for the selected candidate IDs, with current eligibility checks. | then: Style · Preserve fingerprint request |
| **Style · Preserve fingerprint request** (Code) | Restores the original fingerprint request after the approval database call. | then: Style · Load approved current examples — medium scoped |
| **Style · Load approved current examples — medium scoped** (PostgreSQL) | Loads approved, current examples scoped to the requested company and medium. | then: Style · Extract 14 measurable style statistics |
| **Style · Extract 14 measurable style statistics** (Code) | Measures 14 text features from approved examples, including sentence, paragraph, punctuation, and vocabulary characteristics; this is a statistical profile, not a vector embedding. | then: Style · Store immutable version + activate profile |
| **Style · Store immutable version + activate profile** (PostgreSQL) | Stores a new fingerprint version and activates it while retaining previous versions. | then: Style · Fingerprint update receipt |
| **Style · Fingerprint update receipt** (Code) | Returns the medium, version, sample size, and uncalibrated status for the new profile. | then: Seed · continue only after all profiles stored |
| **Seed · continue only after all profiles stored** (IF) | Continues to fixture inbox replay only when the current execution came through the explicit bootstrap entry. | true: Seed · Replay mixed inbox events |
| **Seed · Replay mixed inbox events** (Code) | Emits a mixed set of synthetic incoming, sent, internal, and adversarial test events. | then: Seed · Classify + deduplicate test inbox · set operation |
| **Seed · Classify + deduplicate test inbox · set operation** (Code) | Adds the capture operation to each fixture item before calling the backend workflow. | then: Seed · Classify + deduplicate test inbox |
| **Seed · Classify + deduplicate test inbox** (Call workflow) | Calls Workflow 2 for each fixture event to normalize and persist it idempotently. | then: Seed · Demo ready — next open Slack Concierge |
| **Seed · Demo ready — next open Slack Concierge** (Code) | Returns a synthetic setup receipt. Its hard-coded disconnected-channel list predates the later DM-only Slack bridge. | — |

## Workflow 2 · Sorting & Backend

**31 functional nodes**, including 9 disabled placeholders; 5 additional sticky notes explain the layout.

| Node | What it does | Next |
|---|---|---|
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route capture |
| **Internal · route capture** (IF) | If the operation is capture, normalize the event; otherwise check for an outbox request. | true: Capture · Normalize · exclude internal · detect sent; false: Internal · route outbox |
| **Internal · route outbox** (IF) | If the operation is outbox, load review items; otherwise reject the request. | true: Outbox · Tenant-scoped review configuration; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |
| **Capture · Manual test** (Manual trigger) | Manually starts a capture demonstration. | then: Capture · Example forwarded customer email |
| **Capture · Example forwarded customer email** (Code) | Creates a fictional forwarded-email event for local testing. | then: Capture · Normalize · exclude internal · detect sent |
| **Capture · Normalize · exclude internal · detect sent** (Code) | Normalizes event fields, marks internal content as excluded, and identifies genuinely confirmed outbound messages as style candidates. | then: Capture · Persist idempotent inbox + style candidate |
| **Capture · Persist idempotent inbox + style candidate** (PostgreSQL) | Calls the database ingestion function, which stores or deduplicates the normalized event and any eligible style candidate. | then: Capture · Capture receipt — no heavy generation |
| **Capture · Capture receipt — no heavy generation** (Code) | Returns the ingest result without invoking a large drafting model. | — |
| **Outbox · Manual test** (Manual trigger) | Manually starts an outbox review reconstruction. | then: Outbox · Tenant-scoped review configuration |
| **Outbox · Every minute recovery — DISABLED until deployment** (Schedule, disabled) | Disabled schedule placeholder for future outbox recovery; it does not run on its own. | then: Outbox · Tenant-scoped review configuration |
| **Outbox · Tenant-scoped review configuration** (Code) | Selects the tenant and checks that a non-demo request identifies an operator. | then: Outbox · Read held notifications and explicit actions |
| **Outbox · Read held notifications and explicit actions** (PostgreSQL) | Fetches held notifications and staged actions for the tenant through the database. | then: Outbox · Expand review items |
| **Outbox · Expand review items** (Code) | Converts the returned list into one item per review record, or creates an empty-result marker. | then: Outbox · Pending draft/action exists? |
| **Outbox · Pending draft/action exists?** (IF) | Continues only when the returned outbox contains a pending item. | true: Outbox · Fetch draft and complete artifact metadata |
| **Outbox · Fetch draft and complete artifact metadata** (PostgreSQL) | Loads the immutable draft and metadata needed to reconstruct its review output. | then: Outbox · Stored document exists? |
| **Outbox · Stored document exists?** (IF) | If the draft has a stored artifact, retrieve it; otherwise build the review text directly. | true: Outbox · Retrieve exact persisted artifact; false: Outbox · Build Slack review blocks + copyable text |
| **Outbox · Build Slack review blocks + copyable text** (Code) | Formats the draft, proposed Block Kit card, and copyable text and marks the item held and not delivered. The active bridge currently sends plain text rather than these buttons. | — |
| **Outbox · Retrieve exact persisted artifact** (HTTP request) | Calls the internal document service for the previously stored file. Reads are serialized and have bounded retries. | then: Outbox · Reattach verified document bytes |
| **Outbox · Reattach verified document bytes** (Code) | Checks the returned file checksum against saved metadata, then attaches the verified bytes to the item. | then: Outbox · Build Slack review blocks + copyable text |
| **Recovery · queued jobs every minute — DISABLED** (Schedule, disabled) | Disabled timer for future queued-job recovery; no background recovery runs from this placeholder. | then: Recovery · wake main worker |
| **Recovery · wake main worker** (Code) | Constructs a trusted internal work operation for the main workflow. | then: Recovery · independent main execution |
| **Recovery · independent main execution** (Call workflow) | Calls Workflow 3 as an independent worker execution when the recovery lane is explicitly enabled. | — |
| **Capture · Slack source adapter — DISCONNECTED** (Slack trigger, disabled) | Disabled placeholder for ingesting Slack as a data source; it is distinct from the working, restricted DM demo bridge. | — |
| **Capture · Forwarded email adapter — DISCONNECTED** (Email trigger, disabled) | Disabled placeholder for a future authenticated forwarded-email intake. | — |
| **Capture · LinkedIn approved export adapter — DISCONNECTED** (Webhook, disabled) | Disabled placeholder for a future approved LinkedIn import adapter. | — |
| **Outbox · Post review to Slack — DISCONNECTED** (Slack, disabled) | Disabled planned Slack delivery node for the durable outbox. The separate demo bridge can still reply to the operator by DM. | — |
| **Outbox · Send approved email — DISCONNECTED** (Email send, disabled) | Disabled placeholder; it does not send email. | — |
| **Outbox · Save approved file to folder — DISCONNECTED** (HTTP request, disabled) | Disabled placeholder; it does not upload files to a cloud folder. | — |
| **Outbox · LinkedIn post / DM export — DISCONNECTED** (Pass-through, disabled) | Disabled placeholder for a future LinkedIn export/posting capability. | — |

## Workflow 3 · Main Chat & Work

**76 functional nodes**, including 1 disabled placeholders; 11 additional sticky notes explain the layout.

| Node | What it does | Next |
|---|---|---|
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route chat |
| **Internal · route chat** (IF) | If the operation is chat, enter the chat path; otherwise check for a worker request. | true: Chat · Authenticated Slack command envelope; false: Internal · route work |
| **Internal · route work** (IF) | If the operation is work, claim a queued job; otherwise reject the request. | true: Work · Claim durable job + lease; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |
| **Chat · Manual test** (Manual trigger) | Manual entry point for running a synthetic request in the n8n editor. | then: Chat · Edit this demo Slack request |
| **Chat · Edit this demo Slack request** (Code) | Supplies an editable fictional request envelope for the manual test. | then: Chat · Load trusted tenant policy |
| **Chat · Authenticated Slack command envelope** (Pass-through) | Pass-through entry point for a trusted internal chat envelope or the restricted local Slack bridge. | then: Chat · Load trusted tenant policy |
| **Chat · Load trusted tenant policy** (PostgreSQL) | Loads the tenant configuration, including demo settings and allowed operators, from PostgreSQL. | then: Chat · Authenticate operator + parse explicit command |
| **Chat · Authenticate operator + parse explicit command** (Code) | Checks the operator and demo/transport conditions, then routes recognizable requests, natural conversation, greetings, or explicit actions. Its rules are useful but do not understand every intent perfectly. | then: Chat · Draft or report requested? |
| **Chat · Draft or report requested?** (IF) | Routes recognized writing and company-report requests into the durable drafting job path. | true: Chat · Queue request exactly once; false: Chat · Explicit save or send? |
| **Chat · Queue request exactly once** (PostgreSQL) | Uses the request ID to enqueue the draft job idempotently rather than creating duplicate work on a replay. | then: Work · Claim durable job + lease |
| **Chat · Explicit save or send?** (IF) | Checks whether the parsed request is a staged save/send action rather than a draft or conversation. | true: Chat · Validate exact revision + stage action; false: Chat · Fingerprint command? |
| **Chat · Validate exact revision + stage action** (PostgreSQL) | Asks the database to validate the exact draft revision and stage the requested action. It does not itself send email, post to LinkedIn, or save to a cloud folder. | then: Chat · Return local Slack response preview |
| **Chat · Review / update style fingerprint · set operation** (Code) | Adds the fingerprint operation to an approved fingerprint request. | then: Chat · Review / update style fingerprint |
| **Chat · Review / update style fingerprint** (Call workflow) | Calls Workflow 1 to preview candidates or update a fingerprint according to the request. | then: Chat · Return local Slack response preview |
| **Chat · Fingerprint command?** (IF) | Routes explicit fingerprint requests to Workflow 1; other input proceeds to natural-conversation routing. | true: Chat · Review / update style fingerprint · set operation; false: Chat · General conversation? |
| **Chat · Show command help** (Code) | Returns the parser’s friendly help, greeting, or clarification and indicates that no external action happened. | — |
| **Chat · General conversation?** (IF) | Separates an open-ended question from a greeting or clarification; only the former proceeds to the conversational model path. | true: Chat · Reserve conversation budget; false: Chat · Show command help |
| **Work · Claim durable job + lease** (PostgreSQL) | Claims the exact requested job for an interactive request, or an eligible queued job for a trusted worker, and obtains a lease. | then: Work · A job is available? |
| **Work · A job is available?** (IF) | Branches on whether a job was successfully claimed; the idle path does not call a model. | true: Work · Retrieve current public facts + style; false: Work · No queued work — zero tokens |
| **Work · Retrieve current public facts + style** (PostgreSQL) | Fetches eligible approved company facts and the relevant style profile, applying database filters for tenant and evidence scope. | then: Work · Load worker policy; error: Work · Capture failure for durable retry |
| **Work · Load worker policy** (PostgreSQL) | Loads tenant settings used by the drafting worker. | then: Work · Prepare draft context; error: Work · Capture failure for durable retry |
| **Work · Prepare draft context** (Code) | Limits facts, messages, and style examples; builds the model instructions and request. It treats inbox text as untrusted and requires a style profile and available evidence. | then: Work · Live models enabled?; error: Work · Capture failure for durable retry |
| **Work · Live models enabled?** (IF) | Uses the paid drafting path only if live_models is true AND dry_run is false. The last validated demo configuration kept dry_run true. | true: Work · Reserve bounded job budget — 3 cents maximum; false: Work · DRY RUN — evidence-only fixture draft |
| **Work · Reserve bounded job budget — 3 cents maximum** (PostgreSQL) | Asks the database to reserve up to $0.03 for a drafting execution under the tenant’s daily cap. | then: Work · Budget permits this execution? |
| **Work · Budget permits this execution?** (IF) | Only a fresh reservation with call_permitted true can proceed to a paid drafting call. | true: Work · Generation call context; false: Work · Capture failure for durable retry |
| **Work · Generation call context** (Code) | Combines the prepared draft context with the reservation record. | then: Work · OpenRouter — economical structured draft |
| **Work · OpenRouter — economical structured draft** (HTTP request) | Sends the bounded structured generation request to the configured OpenRouter model when the live path is enabled; the error output goes to durable failure handling. | then: Work · Parse draft and preserve evidence; error: Work · Capture failure for durable retry |
| **Work · Parse draft and preserve evidence** (Code) | Parses the returned structured draft and retains the source context, request ID, model-call ID, and usage metadata. | then: Work · Deterministic citation / number / language gate; error: Work · Capture failure for durable retry |
| **Work · Deterministic citation / number / language gate** (Code) | Screens the draft for allowed citations, literal numbers, and policy/language patterns. This deterministic screen is not semantic proof of factual accuracy. | then: Work · Live draft passes deterministic gate?; error: Work · Capture failure for durable retry |
| **Work · Live draft passes deterministic gate?** (IF) | A live candidate passing the screen enters the model-verification lane; other candidates go to rewrite/review handling. | true: Work · Joey veto + Mammoth evidence/style check; false: Work · One bounded rewrite needed? |
| **Work · Joey veto + Mammoth evidence/style check** (Pass-through) | Pass-through marker that connects a draft to the visible System 1 verification lane. | then: Verify · One bounded candidate with approved sources |
| **Work · DRY RUN — evidence-only fixture draft** (Code) | Builds a clearly unverified synthetic draft from retrieved fixtures without making a paid drafting-model call. | then: Work · Deterministic citation / number / language gate |
| **Verify · One bounded candidate with approved sources** (Pass-through) | Pass-through entry point for the current candidate and evidence; it is also used to restore context if verification fails. | then: Verify · Compile Joey typed veto |
| **Verify · Compile Joey typed veto** (Code) | Builds a bounded typed-decision request for the quick Joey check. | then: Verify · OpenRouter Decisions — Joey; error: Verify · Evaluator error — fail closed |
| **Verify · OpenRouter Decisions — Joey** (HTTP request) | Calls the configured Joey decision model through OpenRouter on the live verification path. | then: Verify · Validate Joey answer — never approval; error: Verify · Evaluator error — fail closed |
| **Verify · Validate Joey answer — never approval** (Code) | Validates and parses Joey’s typed response. A pass is only a veto check, not approval to send. | then: Verify · Joey has not vetoed?; error: Verify · Evaluator error — fail closed |
| **Verify · Joey has not vetoed?** (IF) | If Joey passes, continue to Mammoth; otherwise preserve a veto and send the candidate to rewrite/review handling. | true: Verify · Compile Mammoth fact + voice rubric; false: Verify · Veto — route to bounded rewrite or review |
| **Verify · Compile Mammoth fact + voice rubric** (Code) | Builds the deeper factual-support and voice-evaluation request for Mammoth. | then: Verify · OpenRouter Decisions — Mammoth; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · OpenRouter Decisions — Mammoth** (HTTP request) | Calls the configured Mammoth decision model through OpenRouter on the live verification path. | then: Verify · Strict answer validation + thresholds; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · Strict answer validation + thresholds** (Code) | Validates Mammoth’s response and applies configured factual/voice thresholds together with earlier checks. Thresholds are uncalibrated and human review remains required. | then: Work · One bounded rewrite needed?; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · Veto — route to bounded rewrite or review** (Code) | Marks the candidate as vetoed and routes it to the bounded rewrite/review decision. | then: Work · One bounded rewrite needed? |
| **Verify · Evaluator error — fail closed** (Code) | If Joey evaluation fails, preserves the candidate, marks it unverified, and treats the model budget as uncertain. | then: Work · One bounded rewrite needed? |
| **Work · One bounded rewrite needed?** (IF) | Allows at most one corrective rewrite for a failed live candidate; otherwise continues to settlement and review. | true: Work · Surgical rewrite — once only; false: Work · Candidate has a model reservation? |
| **Work · Surgical rewrite — once only** (Code) | Prepares one targeted correction using the same evidence and the recorded failure feedback. | then: Work · OpenRouter — single corrective rewrite |
| **Work · OpenRouter — single corrective rewrite** (HTTP request) | Calls the drafting model once for that bounded corrective rewrite. | then: Work · Parse corrective draft; error: Work · Capture failure for durable retry |
| **Work · Parse corrective draft** (Code) | Parses the rewritten draft, records the new attempt, and returns it to the deterministic gate. | then: Work · Deterministic citation / number / language gate; error: Work · Capture failure for durable retry |
| **Verify · Mammoth error — keep current attempt and spend** (Code) | On Mammoth failure, retains the current candidate and accumulated spend while marking the result unverified and budget uncertain. | then: Work · One bounded rewrite needed? |
| **Work · Candidate has a model reservation?** (IF) | Checks whether the candidate incurred a model budget reservation that needs settlement. | true: Work · Keep budget conservative when cost is uncertain; false: Work · Create a report or PowerPoint file? |
| **Work · Keep budget conservative when cost is uncertain** (PostgreSQL) | Settles the reservation only with complete proven usage; otherwise retains an uncertain reservation rather than assuming a refund. | then: Work · Restore final reviewed candidate |
| **Work · Restore final reviewed candidate** (Code) | Restores the candidate and evidence after the budget-settlement database node. | then: Work · Create a report or PowerPoint file? |
| **Work · Compile document request** (Code) | Builds a request for the internal artifact service, including an unverified or human-review banner. | then: Work · Compile PDF / PPTX — internal service; error: Work · Capture failure for durable retry |
| **Work · Compile PDF / PPTX — internal service** (HTTP request) | Calls the separate local document service to produce a PDF report or PowerPoint file. | then: Work · Attach document + keep audit metadata; error: Work · Capture failure for durable retry |
| **Work · Attach document + keep audit metadata** (Code) | Checks that a generated artifact is present and attaches its bytes, checksum, file name, and review metadata. | then: Work · Persistable final artifact + evidence audit; error: Work · Capture failure for durable retry |
| **Work · Create a report or PowerPoint file?** (IF) | If the requested medium is report or PPTX, prepares a document; otherwise proceeds with text. | true: Work · Compile document request; false: Work · Persistable final artifact + evidence audit |
| **Work · Persistable final artifact + evidence audit** (Code) | Builds the final database record with the draft, citations, evidence, profile versions, verification details, model usage, and artifact metadata. | then: Work · Transaction — draft + review outbox + completed job; error: Work · Capture failure for durable retry |
| **Work · Transaction — draft + review outbox + completed job** (PostgreSQL) | Atomically stores the draft and held review record and completes the claimed job through the database function. | then: Work · Load immutable draft for review |
| **Work · Load immutable draft for review** (PostgreSQL) | Reads the saved draft revision so the review output refers to the persisted version. | then: Work · Slack review card — copy / save / explicit send |
| **Work · Slack review card — copy / save / explicit send** (Code) | Constructs review text and a proposed card for the saved draft. Buttons represent staged functionality; the current DM bridge does not expose interactive save/send buttons. | then: Chat · Return local Slack response preview |
| **Chat · Return local Slack response preview** (Code) | Wraps the result as staged-only output. The separate Slack bridge converts suitable results into a DM; the node’s static slack_connected=false field reflects the earlier disconnected design. | — |
| **Work · No queued work — zero tokens** (Code) | Returns an idle status without using a model when no job is claimable. | then: Chat · Return local Slack response preview |
| **Work · Capture failure for durable retry** (Code) | Captures the claimed job ID, lease, tenant, and bounded error text for retry handling. | then: Work · Backoff / retry / dead letter |
| **Work · Backoff / retry / dead letter** (PostgreSQL) | Calls the database failure function to schedule bounded retries or move exhausted jobs to a dead-letter state. | then: Chat · Return local Slack response preview |
| **Chat · Slack bot command trigger — DISCONNECTED** (Slack trigger, disabled) | Disabled native Slack Trigger placeholder. The working demo enters through the authenticated bridge webhook instead. | — |
| **Slack demo · authenticated bridge** (Webhook) | Active n8n webhook secured by a header credential. It accepts calls from the separate local Slack bridge; it is not a direct Slack Socket Mode node. | then: Slack demo · allowlisted operator |
| **Slack demo · allowlisted operator** (Code) | Checks the expected workspace, user, direct-message channel format, event ID, and text length, then builds a fixed synthetic-tenant/operator chat envelope. | then: Chat · Authenticated Slack command envelope |
| **Chat · Reserve conversation budget** (PostgreSQL) | Reserves up to $0.005 for a general conversation request under the existing tenant/day cap. | then: Chat · Conversation budget available? |
| **Chat · Conversation budget available?** (IF) | Only a fresh, permitted reservation can invoke the general-chat model; otherwise return an availability message. | true: Chat · Prepare general answer; false: Chat · Conversation unavailable |
| **Chat · Prepare general answer** (Code) | Builds a bounded general-assistant prompt and model request; it instructs the model not to invent company facts or claim external actions. | then: Chat · OpenRouter general answer |
| **Chat · OpenRouter general answer** (HTTP request) | Calls the configured OpenRouter model for an open-ended question. This general answer is not independently fact-verified. | then: Chat · Capture answer and usage; error: Chat · Conversation error, retain budget |
| **Chat · Capture answer and usage** (Code) | Extracts the answer and records whether the provider call ID and cost are sufficient for a proven settlement. | then: Chat · Record conversation spend; error: Chat · Conversation error, retain budget |
| **Chat · Record conversation spend** (PostgreSQL) | Calls the budget settlement function and preserves the reply for delivery. | then: Chat · Return general answer |
| **Chat · Return general answer** (Code) | Formats the generated answer for the response path, noting that no external business action occurred. | — |
| **Chat · Conversation unavailable** (Code) | Returns a plain-language response when live conversation is disabled, budget is exhausted, or reservation is not permitted. | — |
| **Chat · Conversation error, retain budget** (Code) | Returns a courteous failure message and marks the reservation uncertain when a conversation model call or parse fails. | then: Chat · Record conversation spend |

## Good demo language

- Say “configured to check” for Joey and Mammoth; do not say the system has proven enterprise accuracy or completed a successful live approval pass.
- Say “statistical fingerprint” for the 14 measured features; semantic embeddings are a future enhancement.
- Say “staged for review” for save/send requests; external provider dispatch is not connected.
- Say “local demo” for the current Slack integration. It runs only while the Mac, Docker, n8n, and bridge are running.
- Say “general model answer” for open-ended questions. It can help broadly, but is not automatically checked against company evidence and does not remember earlier turns.
