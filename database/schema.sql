-- PostgreSQL 16. The application role must not expose direct table writes to clients.
-- Every API payload is trusted only after its Slack/webhook adapter authenticates it.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS comms;

CREATE TABLE comms.tenants (
 tenant_id text PRIMARY KEY,
 config jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(config)='object'),
 created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO comms.tenants VALUES ('northstar_demo', '{"demo":true,"internal_domains":["northstarrelay.example"],"operators":["ops@northstarrelay.example","demo_operator"],"dry_run":true,"live_models":false,"daily_budget_usd":0.05,"max_drafts":1,"automatic_send":false,"slack_adapter_verified":false}', now());

CREATE TABLE comms.messages (
 message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 source text NOT NULL, source_id text NOT NULL, revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 body text NOT NULL CHECK(length(body)<=100000), direction text NOT NULL CHECK(direction IN ('inbound','outbound','internal')),
 audience_class text NOT NULL DEFAULT 'internal' CHECK(audience_class IN ('external','internal')),
 channel text NOT NULL, occurred_at timestamptz NOT NULL, confirmed_sent boolean NOT NULL DEFAULT false,
 human_approved boolean NOT NULL DEFAULT false, synthetic boolean NOT NULL DEFAULT false,
 classification text NOT NULL DEFAULT 'untrusted', provenance jsonb NOT NULL DEFAULT '{}',
 updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id,source,source_id), UNIQUE(tenant_id,message_id)
);
CREATE TABLE comms.rag_chunks (
 tenant_id text NOT NULL REFERENCES comms.tenants, chunk_id text NOT NULL, title text NOT NULL DEFAULT '', content text NOT NULL,
 visibility_scope text NOT NULL DEFAULT 'internal' CHECK(visibility_scope IN ('public','internal','restricted')),
 allowed_audiences jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(allowed_audiences)='array'),
 approved boolean NOT NULL DEFAULT false, active boolean NOT NULL DEFAULT true,
 valid_from timestamptz NOT NULL DEFAULT '-infinity', valid_until timestamptz NOT NULL DEFAULT 'infinity',
 source_provenance jsonb NOT NULL DEFAULT '{}', synthetic boolean NOT NULL DEFAULT false,
 search_document tsvector GENERATED ALWAYS AS (to_tsvector('english',coalesce(title,'') || ' ' || content)) STORED,
 PRIMARY KEY(tenant_id,chunk_id), CHECK(valid_until>valid_from), CHECK(length(content)<=30000)
);
CREATE INDEX rag_search ON comms.rag_chunks USING gin(search_document);
CREATE INDEX rag_trigram ON comms.rag_chunks USING gin(content gin_trgm_ops);
CREATE TABLE comms.style_examples (
 example_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 message_id uuid NOT NULL, source text NOT NULL, source_ref text NOT NULL, content_hash text NOT NULL,
 channel text NOT NULL, content text NOT NULL, synthetic boolean NOT NULL DEFAULT false,
 approved boolean NOT NULL DEFAULT false, approved_by text, approved_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,message_id) REFERENCES comms.messages(tenant_id,message_id),
 UNIQUE(tenant_id,source,source_ref,content_hash), UNIQUE(tenant_id,example_id),
 CHECK(NOT approved OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE TABLE comms.fingerprints (
 fingerprint_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 channel text NOT NULL DEFAULT 'global', version integer NOT NULL, profile jsonb NOT NULL CHECK(jsonb_typeof(profile)='object'),
 anchors jsonb NOT NULL CHECK(jsonb_typeof(anchors)='array'), example_ids jsonb NOT NULL,
 provenance text NOT NULL CHECK(provenance IN ('approved_human_examples','synthetic_fixture')),
 approved_by text NOT NULL, approved_at timestamptz NOT NULL DEFAULT now(), active boolean NOT NULL DEFAULT true,
 UNIQUE(tenant_id,channel,version)
);
CREATE UNIQUE INDEX fingerprint_active ON comms.fingerprints(tenant_id,channel) WHERE active;
CREATE TABLE comms.jobs (
 job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 request_id text NOT NULL, channel text NOT NULL DEFAULT 'email', audience_class text NOT NULL DEFAULT 'external',
 input jsonb NOT NULL, status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','retry','completed','dead_letter')),
 attempts integer NOT NULL DEFAULT 0, max_attempts integer NOT NULL DEFAULT 3 CHECK(max_attempts BETWEEN 1 AND 5),
 available_at timestamptz NOT NULL DEFAULT now(), lease_until timestamptz, lease_token uuid, worker_id text,
 last_error text, created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
 UNIQUE(tenant_id,request_id), UNIQUE(tenant_id,job_id)
);
CREATE INDEX jobs_ready ON comms.jobs(status,available_at,created_at);
CREATE TABLE comms.drafts (
 draft_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 job_id uuid NOT NULL UNIQUE, body text NOT NULL, channel text NOT NULL, revision integer NOT NULL DEFAULT 1,
 revision_hash text NOT NULL, status text NOT NULL DEFAULT 'human_review' CHECK(status IN ('human_review','approved','blocked')),
 verification jsonb NOT NULL DEFAULT '{"passed":false}', metadata jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(tenant_id,job_id) REFERENCES comms.jobs(tenant_id,job_id), UNIQUE(tenant_id,draft_id)
);
CREATE TABLE comms.action_requests (
 action_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 request_id text NOT NULL, actor_id text NOT NULL, action text NOT NULL CHECK(action IN ('send','save','approve_examples')),
 draft_id uuid, revision_hash text, payload jsonb NOT NULL, status text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id,request_id),
 FOREIGN KEY(tenant_id,draft_id) REFERENCES comms.drafts(tenant_id,draft_id)
);
CREATE TABLE comms.outbox (
 outbox_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 draft_id uuid NOT NULL, action_id uuid UNIQUE REFERENCES comms.action_requests,
 kind text NOT NULL CHECK(kind IN ('draft_notification','send','save_artifact')),
 status text NOT NULL DEFAULT 'held' CHECK(status IN ('held','disconnected','saved','dispatched')),
 payload jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,draft_id) REFERENCES comms.drafts(tenant_id,draft_id)
);
CREATE UNIQUE INDEX one_draft_notification ON comms.outbox(draft_id) WHERE kind='draft_notification';
CREATE TABLE comms.budget_reservations (
 reservation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 request_id text NOT NULL, budget_day date NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')::date,
 max_cost_usd numeric(12,8) NOT NULL CHECK(max_cost_usd>0), actual_cost_usd numeric(12,8),
 status text NOT NULL DEFAULT 'reserved' CHECK(status IN ('reserved','uncertain','settled')),
 created_at timestamptz NOT NULL DEFAULT now(), settled_at timestamptz, UNIQUE(tenant_id,request_id), UNIQUE(tenant_id,reservation_id)
);
CREATE TABLE comms.model_spend (
 spend_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id text NOT NULL REFERENCES comms.tenants,
 reservation_id uuid NOT NULL UNIQUE, cost_usd numeric(12,8) NOT NULL CHECK(cost_usd>=0),
 provider_call_id text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,reservation_id) REFERENCES comms.budget_reservations(tenant_id,reservation_id),
 UNIQUE(tenant_id,provider_call_id)
);

CREATE FUNCTION comms.tenant_config(t text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE c jsonb;
BEGIN SELECT config INTO c FROM comms.tenants WHERE tenant_id=t; IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant'; END IF; RETURN c; END $$;
CREATE FUNCTION comms.require_operator(t text, actor text) RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN IF actor IS NULL OR NOT (comms.tenant_config(t)->'operators' ? actor) THEN RAISE EXCEPTION 'unauthorized operator'; END IF; END $$;

CREATE FUNCTION comms.ingest_event(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; c jsonb:=comms.tenant_config(t); m comms.messages; old comms.messages;
 src text:=coalesce(payload->>'source',payload->>'channel','unknown'); ref text:=coalesce(payload->>'source_id',payload->>'id');
 dir text:=CASE payload->>'direction' WHEN 'incoming' THEN 'inbound' ELSE coalesce(payload->>'direction','inbound') END;
 aud text:=coalesce(payload->>'audience_class',CASE WHEN (payload->>'external')::boolean IS TRUE THEN 'external' ELSE 'internal' END);
 synth boolean:=coalesce((payload->>'synthetic')::boolean,false); eid uuid; inserted boolean;
BEGIN
 IF coalesce(payload->>'channel','email') NOT IN ('email','email_forward','slack','linkedin_message','linkedin_post','report','pptx') THEN RAISE EXCEPTION 'unsupported channel'; END IF;
 IF ref IS NULL OR payload->>'body' IS NULL THEN RAISE EXCEPTION 'source_id and body required'; END IF;
 IF synth AND NOT(t='northstar_demo' AND coalesce((c->>'demo')::boolean,false)) THEN RAISE EXCEPTION 'synthetic source forbidden'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(t||':'||src||':'||ref,0));
 SELECT * INTO old FROM comms.messages WHERE tenant_id=t AND source=src AND source_id=ref;
 inserted:=NOT FOUND;
 IF inserted THEN
  INSERT INTO comms.messages(tenant_id,source,source_id,body,direction,audience_class,channel,occurred_at,confirmed_sent,human_approved,synthetic,classification,provenance)
  VALUES(t,src,ref,payload->>'body',dir,aud,coalesce(payload->>'channel','email'),coalesce((payload->>'occurred_at')::timestamptz,now()),coalesce((payload->>'confirmed_sent')::boolean,false),coalesce((payload->>'human_approved')::boolean,false),synth,coalesce(payload->>'classification','untrusted'),coalesce(payload->'provenance','{}')) RETURNING * INTO m;
 ELSE
  -- A replay is harmless. A changed event must declare a newer upstream revision.
  m:=old;
  IF coalesce((payload->>'revision')::integer,1)>old.revision THEN
   UPDATE comms.messages SET revision=(payload->>'revision')::integer,body=payload->>'body',direction=dir,audience_class=aud,
    confirmed_sent=coalesce((payload->>'confirmed_sent')::boolean,false),human_approved=coalesce((payload->>'human_approved')::boolean,false),
    synthetic=synth,classification=coalesce(payload->>'classification','untrusted'),channel=coalesce(payload->>'channel','email'),
    occurred_at=coalesce((payload->>'occurred_at')::timestamptz,old.occurred_at),provenance=coalesce(payload->'provenance','{}'),updated_at=now()
   WHERE message_id=old.message_id RETURNING * INTO m;
  END IF;
 END IF;
 IF m.direction='outbound' AND m.audience_class='external' AND m.confirmed_sent THEN
  INSERT INTO comms.style_examples(tenant_id,message_id,source,source_ref,content_hash,channel,content,synthetic)
  VALUES(t,m.message_id,m.source,m.source_id,encode(public.digest(m.body,'sha256'),'hex'),m.channel,m.body,m.synthetic)
  ON CONFLICT(tenant_id,source,source_ref,content_hash) DO NOTHING;
  SELECT example_id INTO eid FROM comms.style_examples WHERE tenant_id=t AND source=m.source AND source_ref=m.source_id AND content_hash=encode(public.digest(m.body,'sha256'),'hex');
 END IF;
 -- A source edit/reclassification invalidates active profiles that depended on it.
 UPDATE comms.fingerprints f SET active=false WHERE f.tenant_id=t AND f.active AND EXISTS(
  SELECT 1 FROM comms.style_examples e WHERE e.tenant_id=t AND e.message_id=m.message_id AND f.example_ids ? e.example_id::text
   AND (NOT e.approved OR m.direction<>'outbound' OR m.audience_class<>'external' OR NOT m.confirmed_sent OR e.content_hash<>encode(public.digest(m.body,'sha256'),'hex'))
 );
 RETURN jsonb_build_object('message_id',m.message_id,'candidate_id',eid,'inserted',inserted,'revision',m.revision);
END $$;

CREATE FUNCTION comms.seed_fixture(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=coalesce(payload->>'tenant_id','northstar_demo'); c jsonb:=comms.tenant_config(t); x jsonb; n integer:=0; r integer:=0; g integer:=0;
BEGIN
 IF t<>'northstar_demo' OR NOT coalesce((c->>'demo')::boolean,false) THEN RAISE EXCEPTION 'fixtures only in demo tenant'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(coalesce(payload->'rag_chunks','[]')) LOOP
  IF x ? 'tenant_id' AND x->>'tenant_id'<>t THEN RAISE EXCEPTION 'tenant mismatch'; END IF;
  INSERT INTO comms.rag_chunks(tenant_id,chunk_id,title,content,visibility_scope,allowed_audiences,approved,active,valid_from,valid_until,source_provenance,synthetic)
  VALUES(t,coalesce(x->>'chunk_id',x->>'id'),coalesce(x->>'title',''),coalesce(x->>'content',x->>'body'),
   CASE WHEN x->>'classification'='public_approved' AND (x->>'external_allowed')::boolean IS TRUE THEN 'public' ELSE coalesce(x->>'visibility_scope','internal') END,
   coalesce(x->'allowed_audiences',x->'audience_restrictions','[]'),coalesce((x->>'approved')::boolean,x->>'approval_status'='approved',false),coalesce((x->>'active')::boolean,true),
   coalesce((x->>'valid_from')::timestamptz,'-infinity'),coalesce((x->>'valid_until')::timestamptz,'infinity'),jsonb_build_object('fixture',true,'source',x->'provenance','source_type',x->'source_type'),true)
  ON CONFLICT(tenant_id,chunk_id) DO NOTHING; r:=r+1;
 END LOOP;
 FOR x IN SELECT value FROM jsonb_array_elements(coalesce(payload->'outbound_gold','[]')) LOOP
  IF x ? 'tenant_id' AND x->>'tenant_id'<>t THEN RAISE EXCEPTION 'tenant mismatch'; END IF;
  PERFORM comms.ingest_event(x || jsonb_build_object('tenant_id',t,'source','fixture_gold','source_id',coalesce(x->>'source_id',x->>'id'),'synthetic',true,'confirmed_sent',true,'human_approved',false)); g:=g+1;
 END LOOP;
 FOR x IN SELECT value FROM jsonb_array_elements(coalesce(payload->'events','[]')) LOOP
  IF x ? 'tenant_id' AND x->>'tenant_id'<>t THEN RAISE EXCEPTION 'tenant mismatch'; END IF;
  PERFORM comms.ingest_event(x || jsonb_build_object('tenant_id',t,'source','fixture_event','source_id',coalesce(x->>'source_id',x->>'id'),'synthetic',true)); n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('tenant_id',t,'rag_processed',r,'gold_processed',g,'events_processed',n,'synthetic',true);
END $$;

CREATE FUNCTION comms.enqueue_job(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; c jsonb:=comms.tenant_config(t); j comms.jobs;
BEGIN
 IF coalesce(payload->>'channel','email') NOT IN ('email','slack','linkedin_message','linkedin_post','report','pptx') THEN RAISE EXCEPTION 'unsupported channel'; END IF;
 IF nullif(payload->>'request_id','') IS NULL THEN RAISE EXCEPTION 'request_id required'; END IF;
 INSERT INTO comms.jobs(tenant_id,request_id,channel,audience_class,input)
 VALUES(t,payload->>'request_id',coalesce(payload->>'channel','email'),coalesce(payload->>'audience_class','external'),coalesce(payload->'input',payload))
 ON CONFLICT(tenant_id,request_id) DO NOTHING;
 SELECT * INTO j FROM comms.jobs WHERE tenant_id=t AND request_id=payload->>'request_id';
 IF j.input IS DISTINCT FROM coalesce(payload->'input',payload) OR j.channel<>coalesce(payload->>'channel','email') OR j.audience_class<>coalesce(payload->>'audience_class','external') THEN RAISE EXCEPTION 'request_id reused for different job'; END IF;
 RETURN to_jsonb(j);
END $$;
CREATE FUNCTION comms.claim_job(worker_id text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE j comms.jobs;
BEGIN
 IF nullif(worker_id,'') IS NULL THEN RAISE EXCEPTION 'worker_id required'; END IF;
 -- Expired leases at the retry bound become dead letters; others are reclaimed.
 UPDATE comms.jobs SET status='dead_letter',lease_until=NULL,lease_token=NULL,last_error='lease expired at retry bound'
 WHERE status='running' AND lease_until<now() AND attempts>=max_attempts;
 SELECT * INTO j FROM comms.jobs WHERE ((status IN ('queued','retry') AND available_at<=now()) OR (status='running' AND lease_until<now()))
 AND attempts<max_attempts ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN '{"claimed":false}'; END IF;
 UPDATE comms.jobs SET status='running',attempts=attempts+1,worker_id=claim_job.worker_id,lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes'
 WHERE job_id=j.job_id RETURNING * INTO j;
 RETURN to_jsonb(j)||'{"claimed":true}';
END $$;

CREATE FUNCTION comms.claim_requested_job(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; actor text:=payload->>'actor_id'; j comms.jobs;
BEGIN
 PERFORM comms.require_operator(t,actor);
 IF nullif(payload->>'worker_id','') IS NULL THEN RAISE EXCEPTION 'worker_id required'; END IF;
 SELECT * INTO j FROM comms.jobs WHERE tenant_id=t AND job_id=(payload->>'job_id')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant job'; END IF;
 IF nullif(j.input->>'requested_by','') IS NOT NULL AND j.input->>'requested_by'<>actor THEN RAISE EXCEPTION 'unauthorized job owner'; END IF;
 IF j.status IN ('completed','dead_letter') THEN
  RETURN jsonb_build_object('claimed',false,'reason',j.status,'tenant_id',t,'job_id',j.job_id,'status',j.status);
 END IF;
 IF j.status='running' AND j.lease_until>now() THEN
  RETURN jsonb_build_object('claimed',false,'reason','already_running','tenant_id',t,'job_id',j.job_id,'status',j.status);
 END IF;
 IF j.attempts>=j.max_attempts THEN
  UPDATE comms.jobs SET status='dead_letter',lease_until=NULL,lease_token=NULL,last_error=coalesce(last_error,'requested job reached retry bound')
  WHERE job_id=j.job_id RETURNING * INTO j;
  RETURN jsonb_build_object('claimed',false,'reason','dead_letter','tenant_id',t,'job_id',j.job_id,'status',j.status);
 END IF;
 IF j.status IN ('queued','retry') AND j.available_at>now() THEN
  RETURN jsonb_build_object('claimed',false,'reason','not_ready','tenant_id',t,'job_id',j.job_id,'status',j.status);
 END IF;
 IF j.status NOT IN ('queued','retry','running') THEN RAISE EXCEPTION 'requested job is ineligible'; END IF;
 UPDATE comms.jobs SET status='running',attempts=attempts+1,worker_id=payload->>'worker_id',
  lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes'
 WHERE job_id=j.job_id RETURNING * INTO j;
 RETURN to_jsonb(j)||jsonb_build_object('claimed',true);
END $$;

CREATE FUNCTION comms.retrieve_context(job jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE j comms.jobs; cfg jsonb; q text; query tsquery; facts jsonb; inbox jsonb; fps jsonb; anchors jsonb; context text;
BEGIN
 SELECT * INTO j FROM comms.jobs WHERE job_id=(job->>'job_id')::uuid AND tenant_id=job->>'tenant_id';
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant job'; END IF; cfg:=comms.tenant_config(j.tenant_id);
 q:=left(coalesce(j.input->>'query',j.input->>'body',j.input#>>'{message,body}',j.input->>'text',''),3000);
 query:=websearch_to_tsquery('english',q);
 SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.score DESC,a.chunk_id),'[]') INTO facts FROM (
  SELECT r.chunk_id,r.title,left(r.content,1500) AS content,r.source_provenance,
   (ts_rank_cd(r.search_document,query)+0.1*public.similarity(r.content,q))::real AS score
  FROM comms.rag_chunks r WHERE r.tenant_id=j.tenant_id AND r.visibility_scope='public' AND r.approved AND r.active
   AND r.valid_from<=now() AND now()<r.valid_until
   AND (r.allowed_audiences ? 'public' OR r.allowed_audiences ? j.audience_class OR r.allowed_audiences ? coalesce(j.input->>'audience','prospect_or_customer'))
   AND (NOT r.synthetic OR (j.tenant_id='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)))
   AND (r.search_document@@query OR (length(q)>2 AND public.similarity(r.content,q)>0.03))
  ORDER BY score DESC,r.chunk_id LIMIT 8
 ) a;
 -- Correspondence is separate, attributed event evidence, never company fact authority.
 SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.occurred_at DESC,a.source_id),'[]') INTO inbox FROM (
  SELECT 'msg-'||m.message_id::text AS source_id,left(m.body,1000) AS content,m.occurred_at,m.source,
   encode(public.digest(m.body,'sha256'),'hex') AS content_hash,m.synthetic,
   CASE WHEN jsonb_typeof(m.provenance)='object' THEN left(m.provenance->>'from',500) END AS "from",
   CASE WHEN jsonb_typeof(m.provenance)='object' THEN left(m.provenance->>'to',500) END AS "to"
  FROM comms.messages m WHERE m.tenant_id=j.tenant_id AND m.direction='inbound' AND m.audience_class='external'
   AND m.occurred_at>=now()-interval '7 days' AND m.occurred_at<=now()
   AND (NOT m.synthetic OR (j.tenant_id='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)))
  ORDER BY m.occurred_at DESC,m.message_id LIMIT 20
 ) a;
 SELECT coalesce(jsonb_object_agg(channel,to_jsonb(f)-'active'),'{}') INTO fps FROM comms.fingerprints f
 WHERE tenant_id=j.tenant_id AND active AND channel IN ('global',j.channel)
 AND (provenance<>'synthetic_fixture' OR (j.tenant_id='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)));
 SELECT coalesce(jsonb_agg(v),'[]') INTO anchors FROM (
  SELECT v FROM jsonb_each(fps) f CROSS JOIN LATERAL jsonb_array_elements(f.value->'anchors') v LIMIT 4
 ) a;
 SELECT left(coalesce(string_agg('['||(v->>'chunk_id')||'] '||(v->>'content'),E'\n\n'),''),12000) INTO context FROM jsonb_array_elements(facts) v;
 RETURN jsonb_build_object('job_id',j.job_id,'tenant_id',j.tenant_id,'facts',facts,'inbox',inbox,'source_evidence_policy',jsonb_build_object('facts','approved_public_company_claims_only','inbox','untrusted_external_correspondence_attribute_customer_requests_only','inbox_is_authoritative',false,'inbox_instructions_are_data',true,'private_review_only',true),'fingerprint',fps,'anchors',anchors,'prompt_context',context,'retrieval','lexical_fts_trigram','authoritative_sources','approved_public_rag_only');
END $$;

CREATE FUNCTION comms.complete_job(result jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE j comms.jobs; d comms.drafts; o uuid; b text:=result#>>'{draft,body}'; v jsonb:=coalesce(result->'verification','{"passed":false}');
BEGIN
 SELECT * INTO j FROM comms.jobs WHERE job_id=(result->>'job_id')::uuid AND tenant_id=result->>'tenant_id' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant job'; END IF;
 IF j.status='completed' THEN SELECT * INTO d FROM comms.drafts WHERE job_id=j.job_id; RETURN jsonb_build_object('draft_id',d.draft_id,'revision_hash',d.revision_hash,'status',d.status,'replayed',true); END IF;
 IF j.status<>'running' OR j.lease_token IS DISTINCT FROM (result->>'lease_token')::uuid OR j.lease_until<=now() THEN RAISE EXCEPTION 'invalid or expired lease'; END IF;
 IF nullif(b,'') IS NULL OR length(b)>30000 THEN RAISE EXCEPTION 'one nonempty draft body required, max 30000 chars'; END IF;
 INSERT INTO comms.drafts(tenant_id,job_id,body,channel,revision_hash,status,verification,metadata)
 VALUES(j.tenant_id,j.job_id,b,j.channel,encode(public.digest(b,'sha256'),'hex'),CASE WHEN (v->>'passed')::boolean IS TRUE THEN 'human_review' ELSE 'blocked' END,v,coalesce(result#>'{draft,metadata}','{}')) RETURNING * INTO d;
 INSERT INTO comms.outbox(tenant_id,draft_id,kind,payload) VALUES(j.tenant_id,d.draft_id,'draft_notification',jsonb_build_object('draft_id',d.draft_id,'revision_hash',d.revision_hash,'human_review',true,'dry_run',true)) RETURNING outbox_id INTO o;
 UPDATE comms.jobs SET status='completed',completed_at=now(),lease_until=NULL,lease_token=NULL WHERE job_id=j.job_id;
 RETURN jsonb_build_object('draft_id',d.draft_id,'revision_hash',d.revision_hash,'outbox_id',o,'status',d.status,'human_review',true,'automatic_send',false);
END $$;
CREATE FUNCTION comms.fail_job(result jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE j comms.jobs;
BEGIN
 SELECT * INTO j FROM comms.jobs WHERE job_id=(result->>'job_id')::uuid AND tenant_id=result->>'tenant_id' FOR UPDATE;
 IF NOT FOUND OR j.status<>'running' OR j.lease_token IS DISTINCT FROM (result->>'lease_token')::uuid OR j.lease_until<=now() THEN RAISE EXCEPTION 'invalid or expired lease'; END IF;
 UPDATE comms.jobs SET status=CASE WHEN attempts>=max_attempts THEN 'dead_letter' ELSE 'retry' END,
 available_at=now()+make_interval(secs=>least(3600,30*power(2,attempts-1))::integer),last_error=left(coalesce(result->>'error','unspecified'),2000),lease_until=NULL,lease_token=NULL
 WHERE job_id=j.job_id RETURNING * INTO j; RETURN to_jsonb(j);
END $$;

CREATE FUNCTION comms.approve_examples(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; actor text:=payload->>'actor_id'; cfg jsonb:=comms.tenant_config(t); eid text; e comms.style_examples; m comms.messages; ids jsonb:='[]';
BEGIN
 PERFORM comms.require_operator(t,actor);
 IF jsonb_typeof(payload->'example_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'example_ids')=0 THEN RAISE EXCEPTION 'explicit example_ids required'; END IF;
 FOR eid IN SELECT jsonb_array_elements_text(payload->'example_ids') LOOP
  SELECT * INTO e FROM comms.style_examples WHERE tenant_id=t AND example_id=eid::uuid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant example'; END IF;
  SELECT * INTO m FROM comms.messages WHERE tenant_id=t AND message_id=e.message_id FOR SHARE;
  IF m.direction<>'outbound' OR m.audience_class<>'external' OR NOT m.confirmed_sent OR e.content_hash<>encode(public.digest(m.body,'sha256'),'hex') THEN RAISE EXCEPTION 'example not current confirmed sent external outbound'; END IF;
  IF (e.synthetic OR m.synthetic) AND NOT(t='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)) THEN RAISE EXCEPTION 'synthetic example forbidden'; END IF;
  UPDATE comms.style_examples SET approved=true,approved_by=actor,approved_at=now() WHERE example_id=e.example_id;
  ids:=ids||jsonb_build_array(e.example_id);
 END LOOP;
 RETURN jsonb_build_object('approved_ids',ids,'actor_id',actor,'tenant_id',t);
END $$;
CREATE FUNCTION comms.freeze_fingerprint() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF (to_jsonb(NEW)-'active') IS DISTINCT FROM (to_jsonb(OLD)-'active') THEN RAISE EXCEPTION 'fingerprint versions are immutable'; END IF; RETURN NEW; END $$;
CREATE TRIGGER fingerprint_immutable BEFORE UPDATE ON comms.fingerprints FOR EACH ROW EXECUTE FUNCTION comms.freeze_fingerprint();
CREATE FUNCTION comms.no_delete_fingerprint() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'fingerprint history is immutable'; END $$;
CREATE TRIGGER fingerprint_no_delete BEFORE DELETE ON comms.fingerprints FOR EACH ROW EXECUTE FUNCTION comms.no_delete_fingerprint();
CREATE FUNCTION comms.store_fingerprint(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; actor text:=payload->>'actor_id'; ch text:=coalesce(payload->>'channel','global'); cfg jsonb:=comms.tenant_config(t);
 eid text; e comms.style_examples; m comms.messages; ids jsonb:='[]'; anchors jsonb:='[]'; synth boolean:=false; ver integer; f comms.fingerprints;
BEGIN
 IF ch NOT IN ('global','email','slack','linkedin_message','linkedin_post','report','pptx') THEN RAISE EXCEPTION 'unsupported fingerprint channel'; END IF;
 PERFORM comms.require_operator(t,actor); PERFORM pg_advisory_xact_lock(hashtextextended(t||':fingerprint:'||ch,0));
 IF jsonb_typeof(payload->'profile') IS DISTINCT FROM 'object' OR length((payload->'profile')::text)>16000 THEN RAISE EXCEPTION 'bounded profile object required'; END IF;
 IF jsonb_typeof(payload->'example_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'example_ids')=0 THEN RAISE EXCEPTION 'explicit approved example_ids required'; END IF;
 FOR eid IN SELECT DISTINCT jsonb_array_elements_text(payload->'example_ids') LOOP
  SELECT * INTO e FROM comms.style_examples WHERE tenant_id=t AND example_id=eid::uuid AND approved;
  IF NOT FOUND OR (ch<>'global' AND e.channel<>ch) THEN RAISE EXCEPTION 'unapproved, cross-tenant or wrong channel example'; END IF;
  SELECT * INTO m FROM comms.messages WHERE tenant_id=t AND message_id=e.message_id FOR SHARE;
  IF m.direction<>'outbound' OR m.audience_class<>'external' OR NOT m.confirmed_sent OR e.content_hash<>encode(public.digest(m.body,'sha256'),'hex') THEN RAISE EXCEPTION 'source no longer eligible'; END IF;
  IF (e.synthetic OR m.synthetic) AND NOT(t='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)) THEN RAISE EXCEPTION 'synthetic source forbidden'; END IF;
  ids:=ids||jsonb_build_array(e.example_id); synth:=synth OR e.synthetic OR m.synthetic;
  IF jsonb_array_length(anchors)<4 THEN anchors:=anchors||jsonb_build_array(jsonb_build_object('example_id',e.example_id,'channel',e.channel,'content',left(e.content,1800),'synthetic',e.synthetic OR m.synthetic)); END IF;
 END LOOP;
 IF jsonb_array_length(ids)<20 THEN RAISE EXCEPTION 'minimum 20 distinct eligible approved examples required'; END IF;
 SELECT coalesce(max(version),0)+1 INTO ver FROM comms.fingerprints WHERE tenant_id=t AND channel=ch;
 UPDATE comms.fingerprints SET active=false WHERE tenant_id=t AND channel=ch AND active;
 INSERT INTO comms.fingerprints(tenant_id,channel,version,profile,anchors,example_ids,provenance,approved_by)
 VALUES(t,ch,ver,payload->'profile',anchors,ids,CASE WHEN synth THEN 'synthetic_fixture' ELSE 'approved_human_examples' END,actor) RETURNING * INTO f;
 RETURN to_jsonb(f);
END $$;

CREATE FUNCTION comms.get_draft(payload jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE t text:=payload->>'tenant_id'; d comms.drafts; rows jsonb;
BEGIN
 PERFORM comms.require_operator(t,payload->>'actor_id');
 IF payload ? 'draft_id' THEN
  SELECT * INTO d FROM comms.drafts WHERE tenant_id=t AND draft_id=(payload->>'draft_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant draft'; END IF; RETURN to_jsonb(d);
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') INTO rows FROM (SELECT draft_id,channel,status,revision_hash,created_at FROM comms.drafts WHERE tenant_id=t ORDER BY created_at DESC LIMIT 25) a;
 RETURN jsonb_build_object('drafts',rows);
END $$;
CREATE FUNCTION comms.get_style_examples(payload jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE t text:=payload->>'tenant_id'; ch text:=coalesce(payload->>'channel','global'); cfg jsonb:=comms.tenant_config(t); items jsonb;
BEGIN
 IF ch NOT IN ('global','global_base','email','slack','linkedin_message','linkedin_post','report','pptx') THEN RAISE EXCEPTION 'unsupported style channel'; END IF;
 -- This is an internal worker API, not a public unauthenticated endpoint.
 SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') INTO items FROM (
  SELECT e.example_id AS id,e.content AS body,e.channel,(e.synthetic OR m.synthetic) AS synthetic,e.content_hash,e.approved_by,e.approved_at
  FROM comms.style_examples e JOIN comms.messages m ON m.tenant_id=e.tenant_id AND m.message_id=e.message_id
  WHERE e.tenant_id=t AND e.approved AND (ch IN ('global','global_base') OR e.channel=ch)
   AND m.direction='outbound' AND m.audience_class='external' AND m.confirmed_sent
   AND e.content_hash=encode(public.digest(m.body,'sha256'),'hex')
   AND (NOT(e.synthetic OR m.synthetic) OR (t='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)))
   AND (NOT(payload ? 'example_ids') OR payload->'example_ids' ? e.example_id::text)
  ORDER BY e.approved_at DESC,e.example_id LIMIT 200
 ) a;
 RETURN jsonb_build_object('tenant_id',t,'channel',ch,'examples',items,'minimum_examples',20,'count',jsonb_array_length(items));
END $$;
CREATE FUNCTION comms.prepare_outbox(payload jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE t text:=payload->>'tenant_id'; items jsonb;
BEGIN
 IF t IS NOT NULL THEN PERFORM comms.tenant_config(t); END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') INTO items FROM (
  SELECT o.* FROM comms.outbox o WHERE (t IS NULL OR o.tenant_id=t) AND o.status IN ('held','disconnected')
  ORDER BY o.created_at LIMIT 50
 ) a;
 RETURN jsonb_build_object('items',items,'dispatch_allowed',false,'adapters_connected',false);
END $$;
CREATE FUNCTION comms.request_action(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
#variable_conflict use_variable
DECLARE t text:=payload->>'tenant_id'; actor text:=payload->>'actor_id'; act text:=payload->>'action'; cfg jsonb:=comms.tenant_config(t); a comms.action_requests; d comms.drafts; j comms.jobs; oid uuid; approved jsonb;
BEGIN
 PERFORM comms.require_operator(t,actor);
 IF nullif(payload->>'request_id','') IS NULL THEN RAISE EXCEPTION 'request_id required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(t||':action:'||(payload->>'request_id'),0));
 SELECT * INTO a FROM comms.action_requests WHERE tenant_id=t AND request_id=payload->>'request_id';
 IF FOUND THEN
  IF a.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'request_id reused for different action'; END IF;
  RETURN to_jsonb(a)||jsonb_build_object('replayed',true);
 END IF;
 IF act='approve_examples' THEN approved:=comms.approve_examples(payload);
 ELSE
  IF act NOT IN ('send','save') OR act IS NULL THEN RAISE EXCEPTION 'unknown action'; END IF;
  SELECT * INTO d FROM comms.drafts WHERE tenant_id=t AND draft_id=(payload->>'draft_id')::uuid FOR UPDATE;
  IF NOT FOUND OR d.revision_hash IS DISTINCT FROM payload->>'revision_hash' THEN RAISE EXCEPTION 'unknown draft or stale revision'; END IF;
  IF act='send' AND (d.status NOT IN ('human_review','approved') OR (d.verification->>'passed')::boolean IS DISTINCT FROM true) THEN RAISE EXCEPTION 'verification failed or draft ineligible'; END IF;
  IF act='send' THEN
  SELECT * INTO j FROM comms.jobs WHERE tenant_id=t AND job_id=d.job_id;
  IF d.metadata ? 'message_evidence' THEN
   IF jsonb_typeof(d.metadata->'message_evidence') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'message evidence must be an array'; END IF;
   IF jsonb_array_length(d.metadata->'message_evidence')>20 THEN RAISE EXCEPTION 'message evidence exceeds bound'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(d.metadata->'message_evidence') e WHERE NOT EXISTS(
    SELECT 1 FROM comms.messages m WHERE m.tenant_id=t AND 'msg-'||m.message_id::text=e->>'source_id'
     AND m.direction='inbound' AND m.audience_class='external'
     AND encode(public.digest(m.body,'sha256'),'hex')=e->>'content_hash' AND left(m.body,1000)=e->>'content'
     AND (NOT m.synthetic OR (t='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)))
   )) THEN RAISE EXCEPTION 'draft message evidence is stale, internal or unavailable; regenerate'; END IF;
   IF jsonb_array_length(d.metadata->'message_evidence')>0 THEN RAISE EXCEPTION 'external correspondence recipient ACL not configured; private review only'; END IF;
  END IF;
  IF jsonb_typeof(d.metadata->'evidence') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'current evidence snapshot required'; END IF;
  IF jsonb_array_length(d.metadata->'evidence') NOT BETWEEN 1 AND 8 THEN RAISE EXCEPTION 'current evidence snapshot required'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(d.metadata->'evidence') e WHERE NOT EXISTS(
   SELECT 1 FROM comms.rag_chunks r WHERE r.tenant_id=t AND r.chunk_id=e->>'chunk_id'
    AND r.visibility_scope='public' AND r.approved AND r.active AND r.valid_from<=now() AND now()<r.valid_until
    AND left(r.content,1500)=e->>'content'
    AND (r.allowed_audiences ? 'public' OR r.allowed_audiences ? j.audience_class OR r.allowed_audiences ? coalesce(j.input->>'audience','prospect_or_customer'))
    AND (NOT r.synthetic OR (t='northstar_demo' AND coalesce((cfg->>'demo')::boolean,false)))
  )) THEN RAISE EXCEPTION 'draft evidence is stale, restricted or unavailable; regenerate'; END IF;
  END IF;
 END IF;
 INSERT INTO comms.action_requests(tenant_id,request_id,actor_id,action,draft_id,revision_hash,payload,status)
 VALUES(t,payload->>'request_id',actor,act,d.draft_id,d.revision_hash,payload,CASE WHEN act='approve_examples' THEN 'completed' ELSE 'disconnected' END) RETURNING * INTO a;
 IF act IN ('send','save') THEN
  INSERT INTO comms.outbox(tenant_id,draft_id,action_id,kind,status,payload)
  VALUES(t,d.draft_id,a.action_id,CASE WHEN act='save' THEN 'save_artifact' ELSE 'send' END,'disconnected',jsonb_build_object('draft_id',d.draft_id,'body',d.body,'revision_hash',d.revision_hash,'actor_id',actor,'explicit_approval',true,'dispatch_allowed',false,'reason','external_adapter_disconnected')) RETURNING outbox_id INTO oid;
 END IF;
 RETURN to_jsonb(a)||jsonb_build_object('outbox_id',oid,'approval',approved,'dispatch_allowed',false);
END $$;

CREATE FUNCTION comms.reserve_budget(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; cfg jsonb; r comms.budget_reservations; cap numeric; used numeric; cost numeric:=(payload->>'max_cost_usd')::numeric;
 day date:=(now() AT TIME ZONE 'UTC')::date;
BEGIN
 SELECT config INTO cfg FROM comms.tenants WHERE tenant_id=t FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant'; END IF;
 IF nullif(payload->>'request_id','') IS NULL OR cost IS NULL OR cost<=0 THEN RAISE EXCEPTION 'request_id and positive conservative maximum required'; END IF;
 SELECT * INTO r FROM comms.budget_reservations WHERE tenant_id=t AND request_id=payload->>'request_id';
 IF FOUND THEN
  IF r.max_cost_usd<>cost THEN RAISE EXCEPTION 'reservation idempotency conflict'; END IF;
  RETURN to_jsonb(r)||jsonb_build_object('reserved',r.status='reserved','replayed',true,'call_permitted',false);
 END IF;
 IF NOT coalesce((cfg->>'live_models')::boolean,false) THEN RETURN '{"reserved":false,"reason":"live_models_disabled","call_permitted":false}'; END IF;
 cap:=least(0.05,greatest(0,coalesce((cfg->>'daily_budget_usd')::numeric,0.05)));
 SELECT coalesce(sum(CASE WHEN status='settled' THEN actual_cost_usd ELSE max_cost_usd END),0) INTO used FROM comms.budget_reservations WHERE tenant_id=t AND budget_day=day;
 IF used+cost>cap THEN RETURN jsonb_build_object('reserved',false,'reason','daily_budget_cap','used_usd',used,'cap_usd',cap,'call_permitted',false); END IF;
 INSERT INTO comms.budget_reservations(tenant_id,request_id,max_cost_usd,budget_day) VALUES(t,payload->>'request_id',cost,day) RETURNING * INTO r;
 RETURN to_jsonb(r)||jsonb_build_object('reserved',true,'call_permitted',true,'remaining_usd',cap-used-cost);
END $$;
CREATE FUNCTION comms.settle_budget(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text:=payload->>'tenant_id'; cfg jsonb; r comms.budget_reservations; actual numeric:=(payload->>'actual_cost_usd')::numeric;
BEGIN
 -- Same tenant lock order as reservation prevents budget races and refunds only on proof.
 SELECT config INTO cfg FROM comms.tenants WHERE tenant_id=t FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant'; END IF;
 SELECT * INTO r FROM comms.budget_reservations WHERE tenant_id=t AND reservation_id=(payload->>'reservation_id')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown tenant reservation'; END IF;
 IF r.status='settled' THEN
  IF payload->>'status'<>'settled' OR actual IS DISTINCT FROM r.actual_cost_usd THEN RAISE EXCEPTION 'settlement idempotency conflict'; END IF;
  RETURN to_jsonb(r)||'{"replayed":true}';
 END IF;
 IF payload->>'status'='uncertain' THEN UPDATE comms.budget_reservations SET status='uncertain' WHERE reservation_id=r.reservation_id RETURNING * INTO r;
 ELSIF payload->>'status'='settled' THEN
  IF (payload->>'proven')::boolean IS DISTINCT FROM true OR nullif(payload->>'provider_call_id','') IS NULL OR actual IS NULL OR actual<0 OR actual>r.max_cost_usd THEN RAISE EXCEPTION 'proven call id and actual cost within reserved maximum required'; END IF;
  INSERT INTO comms.model_spend(tenant_id,reservation_id,cost_usd,provider_call_id) VALUES(t,r.reservation_id,actual,payload->>'provider_call_id');
  UPDATE comms.budget_reservations SET status='settled',actual_cost_usd=actual,settled_at=now() WHERE reservation_id=r.reservation_id RETURNING * INTO r;
 ELSE RAISE EXCEPTION 'status must be settled or uncertain'; END IF;
 RETURN to_jsonb(r);
END $$;
COMMIT;
