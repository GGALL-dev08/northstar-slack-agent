# Northstar Relay: how the three n8n workflows work

This is a guided tour of every node in the three **cloud setup snapshots** of the fictional Northstar Relay prototype. The node inventory is based on the saved `knowledge-db.json`, `backend-db.json`, and `main-db.json` cloud import files. A live canvas can be changed after these snapshots; compare disabled indicators and connections in n8n before presenting a later version.

## First, the whole picture

Think of the system as a small communications team with a shared filing cabinet:

1. **Fingerprint & knowledge** is the style editor. It takes approved examples of messages the company actually sent, measures writing patterns for each medium, and stores a versioned profile. The demonstration examples are synthetic.
2. **Sorting & backend** is the mailroom. It receives a structured event, decides what it is, excludes internal material from the external style corpus, and saves the event without duplicating it. It also contains a review-outbox lane for later delivery.
3. **Main chat & work** is the assistant. It receives a request, checks who is asking, decides whether it is a drafting job or conversation, fetches available company evidence and style, and prepares an answer for review. Extra lanes for model verification, correction, and packaging are laid out here.

**PostgreSQL/Neon is the filing cabinet.** It stores company evidence, approved examples, style versions, jobs, drafts, and spending records. **n8n is the coordinator:** each visible node carries out a step, and the lines connect steps. OpenRouter is an external model provider, and Slack may use a separate bridge; neither is the database. For cloud use, every external integration must be configured and reachable independently.

### What was actually tested

As of the recorded November 2 cloud setup, the three workflows were **unpublished drafts** using a restricted Neon database login. Manual tests built five synthetic style profiles, ingested a synthetic event, and created an unverified, blocked synthetic email draft with a held review record. These tests did not establish an end-to-end cloud assistant, fact-checking accuracy, automatic delivery, or semantic embeddings. The local Slack direct-message prototype previously replied to a user through a **separate Socket Mode bridge**; that is not proof of an always-on cloud Slack connection. The cloud OpenRouter credential was saved, but the cloud model HTTP nodes in these snapshots were disabled. The website-to-agent connection was still unfinished at that point.

**Important distinction:** a database-backed dry run can demonstrate data flow without demonstrating that a language model wrote or verified the output. Style profiles measure 14 text statistics; they are not embeddings. Retrieval in this version uses PostgreSQL text/trigram search, not semantic vector search. A human must review drafts; placeholders for copy buttons, file saving and external sending are not proof those actions work.

## How to read an n8n canvas

- A **workflow** is a graph of connected steps. A **node** is one step. An **item** is a data record flowing between nodes, usually JSON; the text after a line is not automatically visible to every later node unless it is passed or referenced.
- A **trigger** starts a run. A manual trigger requires someone to click it. A webhook waits for a request only when properly configured and published. A schedule is a timer, not background magic: a disabled schedule does nothing.
- A **Code** node runs JavaScript to transform, validate, or format data. It is not automatically an AI model. A **PostgreSQL** node runs a query or database function. An **IF** node selects a branch: “true” means the condition passed; “false” means it did not.
- An **HTTP Request** node calls an outside service such as OpenRouter or a document service. An **Execute Workflow** node calls another workflow and needs the right target and working configuration. An **error** connection is the route used when a supported operation fails; it is not the normal branch.
- A **pass-through** node is a labeled handoff. A **sticky note** is explanatory canvas text and performs no processing. **Disabled** means the node is intentionally turned off in the cloud snapshot. An enabled node can still be unreachable, unconfigured, or untested.
- A **job** is an item of work saved for processing. A **lease** temporarily claims it so workers do not process the same job simultaneously. **Idempotent** means a repeated request can be recognized instead of creating duplicates. An **outbox** holds outputs for later review or delivery. A **dead letter** is a job set aside after retries fail.
- A **fingerprint** is a stored summary of writing characteristics; a **candidate** is a possible example or draft still subject to checks. **RAG** means retrieving selected evidence and providing it as context to a generator; retrieval and a citation screen do not guarantee that every claim is true.

## Trace three practical examples

**1. Update a style profile.** A person selects eligible sent examples → the style lane checks approvals → PostgreSQL loads approved examples for the requested medium → the Code node measures style features → PostgreSQL saves and activates a new version. In the cloud setup snapshot, the call from the main workflow to this workflow is disabled, so the successful cloud test used a manual path. A button shown in generated Slack card data is not a working interactive button by itself.

**2. Sort a forwarded message.** A real future adapter or the manual example supplies an event → normalization identifies the medium, audience, and direction → the database inserts or deduplicates it → the receipt returns. Incoming and internal messages must not become approved external sent examples automatically. The email, Slack-source, and LinkedIn-source adapters are disabled in the cloud snapshot.

**3. Ask for an email draft.** The main workflow obtains the request and operator policy → the parser recognizes a writing request → the database queues and claims a job → retrieval loads eligible facts and a style profile → the configured mode determines whether a model or a synthetic fixture creates a candidate → checks run → the result is saved with a held review record. In the verified cloud test this was a dry-run fixture, not a live verified model draft. The live generator and verifier nodes were disabled in the saved cloud import.

## Presenting the system

Start with the three-workflow overview above, then follow the three examples. In each table, **Next** is the visible connection in the saved design; a listed destination may be disabled, so a connection is not proof an execution can pass through it. Error routes and conditional outputs are explicitly labeled where present. Sticky notes are listed after the processing nodes in each workflow.

## Workflow 1 · Fingerprints & Knowledge

**28 functional nodes**, 1 disabled in this cloud snapshot; 4 sticky notes.

| Node and type | Purpose | Next |
|---|---|---|
| **Seed · Manual test** (Manual trigger) | Manual starting point for explicitly seeding the fictional company; this is not an automatic trigger. | then: Seed · explicit bootstrap entry |
| **Style · Manual test** (Manual trigger) | Manual starting point for the style/fingerprint lane. | then: Style · Demo: compile approved email examples |
| **Seed · Load clearly marked synthetic fixture** (Code) | Loads the bundled fictional company facts and sample outbound communications, marked as synthetic. | then: Seed · Seed approved facts + sent example candidates |
| **Seed · Seed approved facts + sent example candidates** (PostgreSQL) | Calls the database seed function to write the fictional facts and example-message records. | then: Seed · Explicit DEMO approval — fixture examples only |
| **Seed · Explicit DEMO approval — fixture examples only** (PostgreSQL) | Approves eligible synthetic gold examples for the demo, checking their source, sent status, external audience, and content hash; this is not approval of real company messages. | then: Seed · Build five versioned medium profiles |
| **Seed · Build five versioned medium profiles** (Code) | Creates five requests: global, email, LinkedIn message, LinkedIn post, and report. | then: Style · Preview pending sent examples? |
| **Seed · Replay mixed inbox events** (Code) | Emits a mixed set of synthetic incoming, sent, internal, and adversarial test events. | then: Seed · Classify + deduplicate test inbox · set operation |
| **Seed · Classify + deduplicate test inbox** (Call workflow, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. This planned call would send each synthetic fixture event to Workflow 2 for normalization and idempotent persistence. | then: Seed · Demo ready — next open Slack Concierge |
| **Seed · Demo ready — next open Slack Concierge** (Code) | Returns a synthetic setup receipt. Its hard-coded disconnected-channel list predates the later DM-only Slack bridge. | — |
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
| **Seed · explicit bootstrap entry** (Pass-through) | Pass-through marker that identifies a bootstrap run; a later condition checks whether this node ran. | then: Seed · Load clearly marked synthetic fixture |
| **Seed · continue only after all profiles stored** (IF) | Continues to fixture inbox replay only when the current execution came through the explicit bootstrap entry. | true: Seed · Replay mixed inbox events |
| **Seed · Classify + deduplicate test inbox · set operation** (Code) | Adds the capture operation to each fixture item before calling the backend workflow. | then: Seed · Classify + deduplicate test inbox |
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route fingerprint |
| **Internal · route fingerprint** (IF) | If the operation is fingerprint, enter the style path; otherwise check for demo bootstrap. | true: Style · Preview pending sent examples?; false: Internal · route bootstrap |
| **Internal · route bootstrap** (IF) | If the operation is bootstrap, enter the synthetic setup lane; otherwise reject it. | true: Seed · explicit bootstrap entry; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |

### Canvas notes

These labels help orient you; they do not execute code.

- **Guide · fingerprints:** FINGERPRINTS · APPROVE → MEASURE → STORE Approved external sent examples only. Profiles are versioned; incoming or internal messages never train them. Embeddings remain deferred.
- **Guide · bootstrap:** SYNTHETIC DEMO · MANUAL SETUP Use this lane only to seed the fictional company. The five profiles complete before inbox fixtures are replayed.
- **Visual overview · CommsVoiceKB2026:** MAIN PATH Select examples → Approve → Measure → Save fingerprint The synthetic demo is a separate setup lane.
- **Visual lane · DEMO REPLAY:** DEMO REPLAY

## Workflow 2 · Sorting & Backend

**31 functional nodes**, 11 disabled in this cloud snapshot; 5 sticky notes.

| Node and type | Purpose | Next |
|---|---|---|
| **Capture · Manual test** (Manual trigger) | Manually starts a capture demonstration. | then: Capture · Example forwarded customer email |
| **Outbox · Manual test** (Manual trigger) | Manually starts an outbox review reconstruction. | then: Outbox · Tenant-scoped review configuration |
| **Capture · Example forwarded customer email** (Code) | Creates a fictional forwarded-email event for local testing. | then: Capture · Normalize · exclude internal · detect sent |
| **Capture · Normalize · exclude internal · detect sent** (Code) | Normalizes event fields, marks internal content as excluded, and identifies genuinely confirmed outbound messages as style candidates. | then: Capture · Persist idempotent inbox + style candidate |
| **Capture · Persist idempotent inbox + style candidate** (PostgreSQL) | Calls the database ingestion function, which stores or deduplicates the normalized event and any eligible style candidate. | then: Capture · Capture receipt — no heavy generation |
| **Capture · Capture receipt — no heavy generation** (Code) | Returns the ingest result without invoking a large drafting model. | — |
| **Capture · Slack source adapter — DISCONNECTED** (Slack trigger, disabled) | Disabled placeholder for ingesting Slack as a data source; it is distinct from the working, restricted DM demo bridge. | — |
| **Capture · Forwarded email adapter — DISCONNECTED** (Email trigger, disabled) | Disabled placeholder for a future authenticated forwarded-email intake. | — |
| **Capture · LinkedIn approved export adapter — DISCONNECTED** (Webhook, disabled) | Disabled placeholder for a future approved LinkedIn import adapter. | — |
| **Outbox · Tenant-scoped review configuration** (Code) | Selects the tenant and checks that a non-demo request identifies an operator. | then: Outbox · Read held notifications and explicit actions |
| **Outbox · Read held notifications and explicit actions** (PostgreSQL) | Fetches held notifications and staged actions for the tenant through the database. | then: Outbox · Expand review items |
| **Outbox · Expand review items** (Code) | Converts the returned list into one item per review record, or creates an empty-result marker. | then: Outbox · Pending draft/action exists? |
| **Outbox · Pending draft/action exists?** (IF) | Continues only when the returned outbox contains a pending item. | true: Outbox · Fetch draft and complete artifact metadata |
| **Outbox · Fetch draft and complete artifact metadata** (PostgreSQL) | Loads the immutable draft and metadata needed to reconstruct its review output. | then: Outbox · Stored document exists? |
| **Outbox · Build Slack review blocks + copyable text** (Code) | Formats the draft, proposed Block Kit card, and copyable text and marks the item held and not delivered. The active bridge currently sends plain text rather than these buttons. | — |
| **Outbox · Every minute recovery — DISABLED until deployment** (Schedule, disabled) | Disabled schedule placeholder for future outbox recovery; it does not run on its own. | then: Outbox · Tenant-scoped review configuration |
| **Outbox · Post review to Slack — DISCONNECTED** (Slack, disabled) | Disabled planned Slack delivery node for the durable outbox. The separate demo bridge can still reply to the operator by DM. | — |
| **Outbox · Send approved email — DISCONNECTED** (Email send, disabled) | Disabled placeholder; it does not send email. | — |
| **Outbox · Save approved file to folder — DISCONNECTED** (HTTP request, disabled) | Disabled placeholder; it does not upload files to a cloud folder. | — |
| **Outbox · LinkedIn post / DM export — DISCONNECTED** (Pass-through, disabled) | Disabled placeholder for a future LinkedIn export/posting capability. | — |
| **Outbox · Stored document exists?** (IF) | If the draft has a stored artifact, retrieve it; otherwise build the review text directly. | true: Outbox · Retrieve exact persisted artifact; false: Outbox · Build Slack review blocks + copyable text |
| **Outbox · Retrieve exact persisted artifact** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. This planned HTTP request would retrieve a previously persisted document from a reachable, authenticated artifact service. | then: Outbox · Reattach verified document bytes |
| **Outbox · Reattach verified document bytes** (Code) | Checks the returned file checksum against saved metadata, then attaches the verified bytes to the item. | then: Outbox · Build Slack review blocks + copyable text |
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route capture |
| **Internal · route capture** (IF) | If the operation is capture, normalize the event; otherwise check for an outbox request. | true: Capture · Normalize · exclude internal · detect sent; false: Internal · route outbox |
| **Internal · route outbox** (IF) | If the operation is outbox, load review items; otherwise reject the request. | true: Outbox · Tenant-scoped review configuration; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |
| **Recovery · queued jobs every minute — DISABLED** (Schedule, disabled) | Disabled timer for future queued-job recovery; no background recovery runs from this placeholder. | then: Recovery · wake main worker |
| **Recovery · wake main worker** (Code) | Constructs a trusted internal work operation for the main workflow. | then: Recovery · independent main execution |
| **Recovery · independent main execution** (Call workflow, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. This planned call would invoke Workflow 3 as a recovery worker after a properly enabled timer. | — |

### Canvas notes

These labels help orient you; they do not execute code.

- **Guide · capture:** INBOX · COLLECT → CLASSIFY → STORE Trusted sources feed this lane. Internal chatter is excluded and provider events are deduplicated.
- **Guide · outbox:** OUTBOX · PREPARE REVIEW & FILES Held records and exact document bytes are reconstructed here. External delivery and schedules are disconnected.
- **Visual overview · CommsBackend2026:** MAIN PATH Collect → Classify → Store | Review outbox → Retrieve files Disabled integrations and recovery schedules are grouped below.
- **Visual lane · JOB RECOVERY · DISABLED:** JOB RECOVERY · DISABLED
- **Visual lane · FUTURE CONNECTIONS · DISCONNECTED:** FUTURE CONNECTIONS · DISCONNECTED

## Workflow 3 · Main Chat & Work

**76 functional nodes**, 9 disabled in this cloud snapshot; 11 sticky notes.

| Node and type | Purpose | Next |
|---|---|---|
| **Chat · Manual test** (Manual trigger) | Manual entry point for running a synthetic request in the n8n editor. | then: Chat · Edit this demo Slack request |
| **Chat · Authenticated Slack command envelope** (Pass-through) | Pass-through entry point for a trusted internal chat envelope or the restricted local Slack bridge. | then: Chat · Load trusted tenant policy |
| **Chat · Edit this demo Slack request** (Code) | Supplies an editable fictional request envelope for the manual test. | then: Chat · Load trusted tenant policy |
| **Chat · Load trusted tenant policy** (PostgreSQL) | Loads the tenant configuration, including demo settings and allowed operators, from PostgreSQL. | then: Chat · Authenticate operator + parse explicit command |
| **Chat · Authenticate operator + parse explicit command** (Code) | Checks the operator and demo/transport conditions, then routes recognizable requests, natural conversation, greetings, or explicit actions. Its rules are useful but do not understand every intent perfectly. | then: Chat · Draft or report requested? |
| **Chat · Draft or report requested?** (IF) | Routes recognized writing and company-report requests into the durable drafting job path. | true: Chat · Queue request exactly once; false: Chat · Explicit save or send? |
| **Chat · Queue request exactly once** (PostgreSQL) | Uses the request ID to enqueue the draft job idempotently rather than creating duplicate work on a replay. | then: Work · Claim durable job + lease |
| **Chat · Explicit save or send?** (IF) | Checks whether the parsed request is a staged save/send action rather than a draft or conversation. | true: Chat · Validate exact revision + stage action; false: Chat · Fingerprint command? |
| **Chat · Validate exact revision + stage action** (PostgreSQL) | Asks the database to validate the exact draft revision and stage the requested action. It does not itself send email, post to LinkedIn, or save to a cloud folder. | then: Chat · Return local Slack response preview |
| **Chat · Fingerprint command?** (IF) | Routes explicit fingerprint requests to Workflow 1; other input proceeds to natural-conversation routing. | true: Chat · Review / update style fingerprint · set operation; false: Chat · General conversation? |
| **Chat · Review / update style fingerprint** (Call workflow, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. This planned call would invoke Workflow 1 to preview candidates or update a profile. | then: Chat · Return local Slack response preview |
| **Chat · Show command help** (Code) | Returns the parser’s friendly help, greeting, or clarification and indicates that no external action happened. | — |
| **Chat · Return local Slack response preview** (Code) | Wraps the result as staged-only output. The separate Slack bridge converts suitable results into a DM; the node’s static slack_connected=false field reflects the earlier disconnected design. | — |
| **Chat · Slack bot command trigger — DISCONNECTED** (Slack trigger, disabled) | Disabled native Slack Trigger placeholder. The working demo enters through the authenticated bridge webhook instead. | — |
| **Work · Claim durable job + lease** (PostgreSQL) | Claims the exact requested job for an interactive request, or an eligible queued job for a trusted worker, and obtains a lease. | then: Work · A job is available? |
| **Work · A job is available?** (IF) | Branches on whether a job was successfully claimed; the idle path does not call a model. | true: Work · Retrieve current public facts + style; false: Work · No queued work — zero tokens |
| **Work · Retrieve current public facts + style** (PostgreSQL) | Fetches eligible approved company facts and the relevant style profile, applying database filters for tenant and evidence scope. | then: Work · Load worker policy; error: Work · Capture failure for durable retry |
| **Work · Load worker policy** (PostgreSQL) | Loads tenant settings used by the drafting worker. | then: Work · Prepare draft context; error: Work · Capture failure for durable retry |
| **Work · Prepare draft context** (Code) | Limits facts, messages, and style examples; builds the model instructions and request. It treats inbox text as untrusted and requires a style profile and available evidence. | then: Work · Live models enabled?; error: Work · Capture failure for durable retry |
| **Work · Live models enabled?** (IF) | Uses the paid drafting path only if live_models is true AND dry_run is false. The last validated demo configuration kept dry_run true. | true: Work · Reserve bounded job budget — 3 cents maximum; false: Work · DRY RUN — evidence-only fixture draft |
| **Work · Reserve bounded job budget — 3 cents maximum** (PostgreSQL) | Asks the database to reserve up to $0.03 for a drafting execution under the tenant’s daily cap. | then: Work · Budget permits this execution? |
| **Work · Budget permits this execution?** (IF) | Only a fresh reservation with call_permitted true can proceed to a paid drafting call. | true: Work · Generation call context; false: Work · Capture failure for durable retry |
| **Work · Generation call context** (Code) | Combines the prepared draft context with the reservation record. | then: Work · OpenRouter — economical structured draft |
| **Work · OpenRouter — economical structured draft** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. Sends the bounded structured generation request to the configured OpenRouter model when the live path is enabled; the error output goes to durable failure handling. | then: Work · Parse draft and preserve evidence; error: Work · Capture failure for durable retry |
| **Work · Parse draft and preserve evidence** (Code) | Parses the returned structured draft and retains the source context, request ID, model-call ID, and usage metadata. | then: Work · Deterministic citation / number / language gate; error: Work · Capture failure for durable retry |
| **Work · DRY RUN — evidence-only fixture draft** (Code) | Builds a clearly unverified synthetic draft from retrieved fixtures without making a paid drafting-model call. | then: Work · Deterministic citation / number / language gate |
| **Work · Deterministic citation / number / language gate** (Code) | Screens the draft for allowed citations, literal numbers, and policy/language patterns. This deterministic screen is not semantic proof of factual accuracy. | then: Work · Live draft passes deterministic gate?; error: Work · Capture failure for durable retry |
| **Work · Live draft passes deterministic gate?** (IF) | A live candidate passing the screen enters the model-verification lane; other candidates go to rewrite/review handling. | true: Work · Joey veto + Mammoth evidence/style check; false: Work · One bounded rewrite needed? |
| **Work · Joey veto + Mammoth evidence/style check** (Pass-through) | Pass-through marker that connects a draft to the visible System 1 verification lane. | then: Verify · One bounded candidate with approved sources |
| **Work · One bounded rewrite needed?** (IF) | Allows at most one corrective rewrite for a failed live candidate; otherwise continues to settlement and review. | true: Work · Surgical rewrite — once only; false: Work · Candidate has a model reservation? |
| **Work · Surgical rewrite — once only** (Code) | Prepares one targeted correction using the same evidence and the recorded failure feedback. | then: Work · OpenRouter — single corrective rewrite |
| **Work · OpenRouter — single corrective rewrite** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. Calls the drafting model once for that bounded corrective rewrite. | then: Work · Parse corrective draft; error: Work · Capture failure for durable retry |
| **Work · Parse corrective draft** (Code) | Parses the rewritten draft, records the new attempt, and returns it to the deterministic gate. | then: Work · Deterministic citation / number / language gate; error: Work · Capture failure for durable retry |
| **Work · Keep budget conservative when cost is uncertain** (PostgreSQL) | Settles the reservation only with complete proven usage; otherwise retains an uncertain reservation rather than assuming a refund. | then: Work · Restore final reviewed candidate |
| **Work · Restore final reviewed candidate** (Code) | Restores the candidate and evidence after the budget-settlement database node. | then: Work · Create a report or PowerPoint file? |
| **Work · Create a report or PowerPoint file?** (IF) | If the requested medium is report or PPTX, prepares a document; otherwise proceeds with text. | true: Work · Compile document request; false: Work · Persistable final artifact + evidence audit |
| **Work · Compile document request** (Code) | Builds a request for the internal artifact service, including an unverified or human-review banner. | then: Work · Compile PDF / PPTX — internal service; error: Work · Capture failure for durable retry |
| **Work · Compile PDF / PPTX — internal service** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. Calls the separate local document service to produce a PDF report or PowerPoint file. | then: Work · Attach document + keep audit metadata; error: Work · Capture failure for durable retry |
| **Work · Attach document + keep audit metadata** (Code) | Checks that a generated artifact is present and attaches its bytes, checksum, file name, and review metadata. | then: Work · Persistable final artifact + evidence audit; error: Work · Capture failure for durable retry |
| **Work · Persistable final artifact + evidence audit** (Code) | Builds the final database record with the draft, citations, evidence, profile versions, verification details, model usage, and artifact metadata. | then: Work · Transaction — draft + review outbox + completed job; error: Work · Capture failure for durable retry |
| **Work · Transaction — draft + review outbox + completed job** (PostgreSQL) | Atomically stores the draft and held review record and completes the claimed job through the database function. | then: Work · Load immutable draft for review |
| **Work · Load immutable draft for review** (PostgreSQL) | Reads the saved draft revision so the review output refers to the persisted version. | then: Work · Slack review card — copy / save / explicit send |
| **Work · Slack review card — copy / save / explicit send** (Code) | Constructs review text and a proposed card for the saved draft. Buttons represent staged functionality; the current DM bridge does not expose interactive save/send buttons. | then: Chat · Return local Slack response preview |
| **Work · No queued work — zero tokens** (Code) | Returns an idle status without using a model when no job is claimable. | then: Chat · Return local Slack response preview |
| **Work · Capture failure for durable retry** (Code) | Captures the claimed job ID, lease, tenant, and bounded error text for retry handling. | then: Work · Backoff / retry / dead letter |
| **Work · Backoff / retry / dead letter** (PostgreSQL) | Calls the database failure function to schedule bounded retries or move exhausted jobs to a dead-letter state. | then: Chat · Return local Slack response preview |
| **Work · Candidate has a model reservation?** (IF) | Checks whether the candidate incurred a model budget reservation that needs settlement. | true: Work · Keep budget conservative when cost is uncertain; false: Work · Create a report or PowerPoint file? |
| **Verify · One bounded candidate with approved sources** (Pass-through) | Pass-through entry point for the current candidate and evidence; it is also used to restore context if verification fails. | then: Verify · Compile Joey typed veto |
| **Verify · Compile Joey typed veto** (Code) | Builds a bounded typed-decision request for the quick Joey check. | then: Verify · OpenRouter Decisions — Joey; error: Verify · Evaluator error — fail closed |
| **Verify · OpenRouter Decisions — Joey** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. Calls the configured Joey decision model through OpenRouter on the live verification path. | then: Verify · Validate Joey answer — never approval; error: Verify · Evaluator error — fail closed |
| **Verify · Validate Joey answer — never approval** (Code) | Validates and parses Joey’s typed response. A pass is only a veto check, not approval to send. | then: Verify · Joey has not vetoed?; error: Verify · Evaluator error — fail closed |
| **Verify · Joey has not vetoed?** (IF) | If Joey passes, continue to Mammoth; otherwise preserve a veto and send the candidate to rewrite/review handling. | true: Verify · Compile Mammoth fact + voice rubric; false: Verify · Veto — route to bounded rewrite or review |
| **Verify · Compile Mammoth fact + voice rubric** (Code) | Builds the deeper factual-support and voice-evaluation request for Mammoth. | then: Verify · OpenRouter Decisions — Mammoth; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · OpenRouter Decisions — Mammoth** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. Calls the configured Mammoth decision model through OpenRouter on the live verification path. | then: Verify · Strict answer validation + thresholds; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · Strict answer validation + thresholds** (Code) | Validates Mammoth’s response and applies configured factual/voice thresholds together with earlier checks. Thresholds are uncalibrated and human review remains required. | then: Work · One bounded rewrite needed?; error: Verify · Mammoth error — keep current attempt and spend |
| **Verify · Veto — route to bounded rewrite or review** (Code) | Marks the candidate as vetoed and routes it to the bounded rewrite/review decision. | then: Work · One bounded rewrite needed? |
| **Verify · Evaluator error — fail closed** (Code) | If Joey evaluation fails, preserves the candidate, marks it unverified, and treats the model budget as uncertain. | then: Work · One bounded rewrite needed? |
| **Chat · Review / update style fingerprint · set operation** (Code) | Adds the fingerprint operation to an approved fingerprint request. | then: Chat · Review / update style fingerprint |
| **Verify · Mammoth error — keep current attempt and spend** (Code) | On Mammoth failure, retains the current candidate and accumulated spend while marking the result unverified and budget uncertain. | then: Work · One bounded rewrite needed? |
| **Internal · operation request** (Workflow entry) | Entry point when another n8n workflow calls this workflow with an operation envelope. | then: Internal · validate operation |
| **Internal · validate operation** (Code) | Requires exactly one item and checks that the requested operation is one this workflow supports. | then: Internal · route chat |
| **Internal · route chat** (IF) | If the operation is chat, enter the chat path; otherwise check for a worker request. | true: Chat · Authenticated Slack command envelope; false: Internal · route work |
| **Internal · route work** (IF) | If the operation is work, claim a queued job; otherwise reject the request. | true: Work · Claim durable job + lease; false: Internal · reject unknown operation |
| **Internal · reject unknown operation** (Code) | Stops execution with an error for an unsupported operation. | — |
| **Slack demo · authenticated bridge** (Webhook, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. In the separate local demo this header-authenticated webhook accepts requests from a local Slack Socket Mode bridge; it is not itself a direct Slack Socket Mode connection. | then: Slack demo · allowlisted operator |
| **Slack demo · allowlisted operator** (Code) | Checks the expected workspace, user, DM-channel format, event ID, and length before constructing a synthetic-tenant request. The webhook feeding it is disabled in this cloud setup snapshot. | then: Chat · Authenticated Slack command envelope |
| **Chat · General conversation?** (IF) | Separates an open-ended question from a greeting or clarification; only the former proceeds to the conversational model path. | true: Chat · Reserve conversation budget; false: Chat · Show command help |
| **Chat · Reserve conversation budget** (PostgreSQL) | Reserves up to $0.005 for a general conversation request under the existing tenant/day cap. | then: Chat · Conversation budget available? |
| **Chat · Conversation budget available?** (IF) | Only a fresh, permitted reservation can invoke the general-chat model; otherwise return an availability message. | true: Chat · Prepare general answer; false: Chat · Conversation unavailable |
| **Chat · Prepare general answer** (Code) | Builds a bounded general-assistant prompt and model request; it instructs the model not to invent company facts or claim external actions. | then: Chat · OpenRouter general answer |
| **Chat · OpenRouter general answer** (HTTP request, disabled in cloud snapshot) | Disabled in the cloud setup snapshot. When configured and enabled, this calls OpenRouter for a general answer; general answers are not independently checked against company evidence. | then: Chat · Capture answer and usage; error: Chat · Conversation error, retain budget |
| **Chat · Capture answer and usage** (Code) | Extracts the answer and records whether the provider call ID and cost are sufficient for a proven settlement. | then: Chat · Record conversation spend; error: Chat · Conversation error, retain budget |
| **Chat · Conversation error, retain budget** (Code) | Returns a courteous failure message and marks the reservation uncertain when a conversation model call or parse fails. | then: Chat · Record conversation spend |
| **Chat · Record conversation spend** (PostgreSQL) | Calls the budget settlement function and preserves the reply for delivery. | then: Chat · Return general answer |
| **Chat · Return general answer** (Code) | Formats the generated answer for the response path, noting that no external business action occurred. | — |
| **Chat · Conversation unavailable** (Code) | Returns a plain-language response when live conversation is disabled, budget is exhausted, or reservation is not permitted. | — |

### Canvas notes

These labels help orient you; they do not execute code.

- **Guide · chat:** 1 · REQUEST & ROUTE Slack requests are authenticated and routed to draft, fingerprint, save or send approval.
- **Guide · drafting:** 2 · RETRIEVE & DRAFT Claim the correct job, load public facts and the style profile, reserve budget, and create a draft or dry-run fixture.
- **Guide · decisions:** 3 · VERIFY & RECOVER Deterministic screen → Joey veto → Mammoth fact/voice check. Errors fail closed; one bounded rewrite is allowed.
- **Visual overview · CommsMain2026:** MAIN PATH Request → Retrieve → Draft → Verify → Review Follow the numbered lanes. Error, retry and disconnected nodes are grouped separately.
- **Visual lane · 4 · REWRITE:** 4 · REWRITE
- **Visual lane · 5 · PACKAGE:** 5 · PACKAGE
- **Visual lane · 6 · REVIEW & SAVE:** 6 · REVIEW & SAVE
- **Visual lane · IDLE / RETRY:** IDLE / RETRY
- **Visual lane · SLACK TRIGGER · DISCONNECTED:** SLACK TRIGGER · DISCONNECTED
- **Guide · Slack demo bridge:** SLACK DEMO · YOUR DIRECT MESSAGES ONLY Socket Mode bridge → authenticated local webhook → workspace + user allowlist → existing chat workflow. No real outbound company sending.
- **Guide · natural conversation:** GENERAL CONVERSATION · ON DEMAND Natural requests use one budget-reserved model call. Company-specific questions and writing requests continue through the evidence and style workflow. Nothing is sent externally.

## What is intentionally unfinished or needs proof

- Cloud HTTP model nodes, document-service calls, source connectors, schedules, bridge webhook, and inter-workflow calls were disabled in the saved setup snapshots. A credential saved in n8n alone does not activate them.
- Automatic recovery needs a working enabled schedule, reachable workflow calls, correct permissions, and failure testing. A designed retry path is not proof of 24/7 durability.
- Joey and Mammoth are intended live checks, not a demonstrated accuracy guarantee. Thresholds need calibration and independent evaluation; deterministic number/citation checks cannot establish truth by themselves.
- Slack interactive buttons, external email/LinkedIn sending, and cloud-folder saving require separately connected and tested adapters. A proposed card or staged action is not delivery.
- New message sources need an authenticated adapter and normalization into the same event contract. A new output medium needs a medium identifier, examples and policy, generation/packaging support, and validation. Do not insert internal company chatter into external style profiles.

Use this guide to navigate the system and then open a node to examine its actual configuration. Treat a dated snapshot as a map, and the active n8n canvas and its execution records as the source of truth for current deployment state.

## Appendix: ten proposed website gateway nodes

These ten nodes describe a **separate local candidate**, not the original three workflow snapshots listed above. They were designed for a separate cloud test copy, and their design and deployment may change. They are not proof that a public website, authentication, live model, or end-to-end agent is working. Do not enable the candidate as-is: it needs a configured authentication credential, private server-to-server connection, deployment checks, and security testing. Its disabled webhook is the front door; an enabled downstream node alone does not make the path available.

| Candidate node | Purpose and next step |
|---|---|
| **Web · Authenticated ingress** (Webhook, disabled in candidate) | Proposed receiving point for a server-to-server request after the web service authenticates the visitor. The n8n webhook must have a correctly configured credential; it leads to Gate request. |
| **Web · Gate request** (Code) | Checks the incoming request shape, action and limits, and decides whether it is a health check, allowed message or blocked request. It leads to Health request?. |
| **Web · Health request?** (IF) | Routes a health check to the database check; other requests go to Blocked request?. A health check is a connectivity check, not proof of a working model or draft. |
| **Web · Confirm demo database** (PostgreSQL) | Queries the synthetic demo configuration to see if the database is reachable. It leads to Health response. |
| **Web · Health response** (Code) | Formats a small health result for the website. It does not verify factual accuracy, model availability, or outbound integrations. |
| **Web · Blocked request?** (IF) | Routes invalid or disallowed requests to Blocked response; accepted chat requests go to Fixed demo envelope. |
| **Web · Blocked response** (Code) | Formats a rejection without passing a blocked request into the main assistant. |
| **Web · Fixed demo envelope** (Code) | Creates a fixed synthetic-tenant request with a bounded, permitted action; it enters the existing authenticated chat-envelope lane. The web visitor cannot choose an internal database actor by changing the request body. |
| **Web · Post-parser route guard** (Code) | Checks the route chosen by the existing parser a second time, preventing a web request from becoming a save, send, fingerprint update or other disallowed action. It then leads to Draft or report requested?. |
| **Web · Response adapter** (Code) | Converts selected web outcomes to the website's expected reply and draft shape while leaving suitable non-web responses unchanged. It does not turn an unverified draft into a verified one. |

The candidate uses native header authentication in its proposed server-to-server boundary; that is not HMAC verification or replay protection. Public access needs a carefully tested visitor-facing boundary, rate limits, cost controls and abuse protection. A separate provider or website layer must not expose the n8n credential in browser code.
