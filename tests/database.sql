-- Self-contained functional regression. All fixture/test mutations roll back.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT FAILED: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.expect_error(statement text, needle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF position(needle IN SQLERRM)>0 THEN RETURN; END IF;
  RAISE EXCEPTION 'wrong error: %, expected substring %',SQLERRM,needle;
 END;
 RAISE EXCEPTION 'expected error missing: %',needle;
END $$;

DO $$
DECLARE p jsonb; x jsonb; a jsonb; b jsonb; j jsonb; leased jsonb; ctx jsonb; ids jsonb; small jsonb; d jsonb; r jsonb;
 before_count integer; after_count integer; fp jsonb; rid uuid;
BEGIN
 INSERT INTO comms.tenants(tenant_id,config) VALUES('dbtest_other','{"operators":["demo_operator"],"live_models":true,"daily_budget_usd":0.05}');
 PERFORM pg_temp.expect_error($q$SELECT comms.ingest_event('{"tenant_id":"not_configured","id":"x","body":"x"}')$q$,'unknown tenant');
 PERFORM pg_temp.expect_error($q$SELECT comms.ingest_event('{"tenant_id":"dbtest_other","id":"x","body":"x","synthetic":true}')$q$,'synthetic source forbidden');
 PERFORM pg_temp.expect_error($q$SELECT comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"badchannel","channel":"discord"}')$q$,'unsupported channel');
 p:=jsonb_build_object('tenant_id','northstar_demo','rag_chunks',jsonb_build_array(
  jsonb_build_object('id','dbtest_public','title','Price oracle','body','dbtestneedle pricing is 149 monthly','classification','public_approved','external_allowed',true,'approval_status','approved','audience_restrictions',jsonb_build_array('public'),'valid_from',now()-interval '1 day','valid_until',now()+interval '1 day'),
  jsonb_build_object('id','dbtest_internal','body','dbtestneedle private discount 99','classification','internal_only','external_allowed',false,'approval_status','approved','audience_restrictions',jsonb_build_array('public')),
  jsonb_build_object('id','dbtest_future','body','dbtestneedle future 77','classification','public_approved','external_allowed',true,'approval_status','approved','audience_restrictions',jsonb_build_array('public'),'valid_from',now()+interval '1 hour'),
  jsonb_build_object('id','dbtest_expired','body','dbtestneedle expired 66','classification','public_approved','external_allowed',true,'approval_status','approved','audience_restrictions',jsonb_build_array('public'),'valid_until',now()-interval '1 hour'),
  jsonb_build_object('id','dbtest_unapproved','body','dbtestneedle unapproved 55','classification','public_approved','external_allowed',true,'approval_status','pending','audience_restrictions',jsonb_build_array('public')),
  jsonb_build_object('id','dbtest_restricted','body','dbtestneedle restricted 44','visibility_scope','restricted','approval_status','approved','allowed_audiences',jsonb_build_array('public')),
  jsonb_build_object('id','dbtest_wrong_audience','body','dbtestneedle secret audience 33','visibility_scope','public','approval_status','approved','allowed_audiences',jsonb_build_array('specific_customer'))
 ),'outbound_gold','[]'::jsonb,'events',jsonb_build_array(
  jsonb_build_object('id','dbtest_incoming','body','dbtestneedle malicious authoritative claim','direction','incoming','channel','email','external',true,'confirmed_sent',true),
  jsonb_build_object('id','dbtest_internal_outbound','body','internal message','direction','outbound','channel','slack','external',false,'confirmed_sent',true)
 ));
 FOR n IN 1..25 LOOP
  p:=jsonb_set(p,'{outbound_gold}',(p->'outbound_gold')||jsonb_build_array(jsonb_build_object('id','dbtest_gold_'||n,'body','Hello prospect, confirmed sent sample '||n,'direction','outbound','channel','email','external',true)));
 END LOOP;
 a:=comms.seed_fixture(p);
 SELECT count(*) INTO before_count FROM comms.style_examples WHERE source_ref LIKE 'dbtest%';
 a:=comms.seed_fixture(p);
 SELECT count(*) INTO after_count FROM comms.style_examples WHERE source_ref LIKE 'dbtest%';
 PERFORM pg_temp.assert_true(before_count=25 AND after_count=25,'fixture dedup; incoming/internal not style candidates');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM comms.style_examples WHERE source_ref LIKE 'dbtest%' AND approved),'no implicit style approval');
 INSERT INTO comms.rag_chunks(tenant_id,chunk_id,content,visibility_scope,allowed_audiences,approved) VALUES('dbtest_other','dbtest_other_fact','dbtestneedle other tenant secret','public','["public"]',true);
 j:=comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"dbtest_job","channel":"email","input":{"query":"dbtestneedle"}}');
 a:=comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"dbtest_job","channel":"email","input":{"query":"dbtestneedle"}}');
 PERFORM pg_temp.assert_true(j->>'job_id'=a->>'job_id','job dedup');
 PERFORM pg_temp.expect_error($q$SELECT comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"dbtest_job","channel":"email","input":{"query":"changed"}}')$q$,'request_id reused');
 -- Fill the recent inbox beyond its bound; internal/other-tenant/time-outside rows never leak.
 FOR n IN 1..25 LOOP
  a:=comms.ingest_event(jsonb_build_object('tenant_id','northstar_demo','source','dbtest_inbox','source_id','inbox_'||n,'body',repeat('customer request ',100)||n,'direction','inbound','audience_class','external','channel','email','occurred_at',now()-make_interval(secs=>n),'provenance',jsonb_build_object('from','customer@example.test','to','team@northstarrelay.example')));
 END LOOP;
 a:=comms.ingest_event(jsonb_build_object('tenant_id','northstar_demo','source','dbtest_internal','source_id','internal_recent','body','NEVER_IN_INBOX_INTERNAL','direction','inbound','audience_class','internal','channel','email','occurred_at',now()));
 a:=comms.ingest_event(jsonb_build_object('tenant_id','dbtest_other','source','dbtest_other_inbox','source_id','other_recent','body','NEVER_IN_INBOX_OTHER_TENANT','direction','inbound','audience_class','external','channel','email','occurred_at',now()));
 a:=comms.ingest_event(jsonb_build_object('tenant_id','northstar_demo','source','dbtest_old','source_id','old_inbox','body','NEVER_IN_INBOX_OLD','direction','inbound','audience_class','external','channel','email','occurred_at',now()-interval '8 days'));
 a:=comms.ingest_event(jsonb_build_object('tenant_id','northstar_demo','source','dbtest_future','source_id','future_inbox','body','NEVER_IN_INBOX_FUTURE','direction','inbound','audience_class','external','channel','email','occurred_at',now()+interval '1 hour'));
 ctx:=comms.retrieve_context(j);
 PERFORM pg_temp.assert_true(jsonb_array_length(ctx->'inbox')=20,'inbox capped at20');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'inbox') v WHERE length(v->>'content')>1000 OR v->>'content' LIKE 'NEVER_IN_INBOX%'),'inbox excludes internal/other tenant/outdated/future, bounds body');
 PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'inbox') v WHERE v->>'from'='customer@example.test' AND length(v->>'content_hash')=64),'inbox sender provenance and full body hash');
 PERFORM pg_temp.assert_true((ctx#>>'{source_evidence_policy,inbox_is_authoritative}')::boolean=false,'inbox never authoritative');
 PERFORM pg_temp.assert_true(jsonb_array_length(ctx->'facts')=1 AND ctx#>>'{facts,0,chunk_id}'='dbtest_public','tenant/time/approval/visibility/audience filtering');
 PERFORM pg_temp.assert_true(length(ctx->>'prompt_context')<=12000,'prompt bound');
 a:=comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"dbtest_empty","channel":"pptx","input":{"query":""}}');
 ctx:=comms.retrieve_context(a);
 PERFORM pg_temp.assert_true(jsonb_array_length(ctx->'facts')=0,'empty query never falls back to all source facts');
 PERFORM pg_temp.expect_error(format('SELECT comms.retrieve_context(%L::jsonb)',jsonb_build_object('tenant_id','dbtest_other','job_id',j->>'job_id')),'unknown tenant job');
 SELECT jsonb_agg(example_id::text ORDER BY example_id::text) INTO ids FROM comms.style_examples WHERE source_ref LIKE 'dbtest_gold_%';
 PERFORM pg_temp.expect_error(format('SELECT comms.approve_examples(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','outsider','example_ids',ids)),'unauthorized operator');
 a:=comms.approve_examples(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','example_ids',ids));
 small:=jsonb_build_array(ids->>0);
 PERFORM pg_temp.expect_error(format('SELECT comms.store_fingerprint(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','channel','global','profile','{}'::jsonb,'example_ids',small)),'minimum 20');
 fp:=comms.store_fingerprint(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','channel','global','profile',jsonb_build_object('tone','clear'),'example_ids',ids));
 PERFORM pg_temp.assert_true(fp->>'provenance'='synthetic_fixture','synthetic fingerprint provenance');
 PERFORM pg_temp.expect_error(format('UPDATE comms.fingerprints SET profile=%L::jsonb WHERE fingerprint_id=%L::uuid','{"changed":true}',fp->>'fingerprint_id'),'immutable');
 PERFORM pg_temp.expect_error(format('DELETE FROM comms.fingerprints WHERE fingerprint_id=%L::uuid',fp->>'fingerprint_id'),'immutable');
 a:=comms.ingest_event('{"tenant_id":"northstar_demo","source":"fixture_gold","source_id":"dbtest_gold_1","body":"edited current body","direction":"outbound","audience_class":"external","channel":"email","confirmed_sent":true,"synthetic":true,"revision":2}');
 a:=comms.get_style_examples('{"tenant_id":"northstar_demo","channel":"email"}');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a->'examples') e WHERE e->>'body'='Hello prospect, confirmed sent sample 1'),'edited revision stale approved hash excluded');
 ctx:=comms.retrieve_context(j);
 PERFORM pg_temp.assert_true(NOT(ctx->'fingerprint' ? 'global'),'source edit invalidates dependent active fingerprint');
 PERFORM pg_temp.expect_error(format('SELECT comms.store_fingerprint(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','channel','global','profile','{}'::jsonb,'example_ids',ids)),'source no longer eligible');

 -- Make this test job the oldest so a shared idle test DB cannot claim another job.
 UPDATE comms.jobs SET created_at='1900-01-01' WHERE job_id=(j->>'job_id')::uuid;
 leased:=comms.claim_job('dbtest_worker');
 PERFORM pg_temp.assert_true(leased->>'job_id'=j->>'job_id' AND (leased->>'attempts')::int=1,'lease claim');
 UPDATE comms.jobs SET lease_until=now()-interval '1 second' WHERE job_id=(j->>'job_id')::uuid;
 PERFORM pg_temp.expect_error(format('SELECT comms.complete_job(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','job_id',j->>'job_id','lease_token',leased->>'lease_token','draft',jsonb_build_object('body','stale'),'verification',jsonb_build_object('passed',true))),'invalid or expired lease');
 leased:=comms.claim_job('dbtest_worker');
 PERFORM pg_temp.assert_true((leased->>'attempts')::int=2,'expired lease recovery');
 a:=comms.fail_job(leased||'{"error":"transient"}');
 PERFORM pg_temp.assert_true(a->>'status'='retry' AND (a->>'available_at')::timestamptz>=now()+interval '59 seconds','bounded exponential backoff');
 UPDATE comms.jobs SET available_at=now()-interval '1 second' WHERE job_id=(j->>'job_id')::uuid;
 leased:=comms.claim_job('dbtest_worker');
 a:=comms.fail_job(leased||'{"error":"permanent"}');
 PERFORM pg_temp.assert_true(a->>'status'='dead_letter' AND (a->>'attempts')::int=3,'dead letter retry bound');

 j:=comms.enqueue_job('{"tenant_id":"northstar_demo","request_id":"dbtest_complete","channel":"email","input":{"query":"pricing"}}');
 UPDATE comms.jobs SET created_at='1899-01-01' WHERE job_id=(j->>'job_id')::uuid;
 leased:=comms.claim_job('dbtest_worker');
 d:=comms.complete_job(leased||jsonb_build_object('draft',jsonb_build_object('body','Hello, here is the verified proposed reply.','metadata',jsonb_build_object('evidence',jsonb_build_array(jsonb_build_object('chunk_id','dbtest_public','content','dbtestneedle pricing is 149 monthly')))),'verification',jsonb_build_object('passed',true)));
 PERFORM pg_temp.assert_true(d->>'status'='human_review','verified draft held for human review');
 a:=comms.complete_job(leased||jsonb_build_object('draft',jsonb_build_object('body','second body')));
 PERFORM pg_temp.assert_true(a->>'draft_id'=d->>'draft_id' AND (a->>'replayed')::boolean,'exactly one draft on retry');
 PERFORM pg_temp.expect_error(format('SELECT comms.request_action(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send_stale','draft_id',d->>'draft_id','revision_hash','stale')),'stale revision');
 a:=comms.request_action(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash'));
 PERFORM pg_temp.assert_true(a->>'status'='disconnected' AND NOT(a->>'dispatch_allowed')::boolean,'explicit send stage disconnected');
 b:=comms.request_action(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash'));
 PERFORM pg_temp.assert_true(b->>'action_id'=a->>'action_id' AND (b->>'replayed')::boolean,'action idempotence');
 a:=comms.request_action(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','save','request_id','dbtest_save','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash'));
 PERFORM pg_temp.assert_true((SELECT count(DISTINCT kind)=3 FROM comms.outbox WHERE draft_id=(d->>'draft_id')::uuid),'draft notification/send/save distinct');
 UPDATE comms.rag_chunks SET active=false WHERE tenant_id='northstar_demo' AND chunk_id='dbtest_public';
 PERFORM pg_temp.expect_error(format('SELECT comms.request_action(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send_stalefact','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash')),'evidence is stale');
 UPDATE comms.rag_chunks SET active=true WHERE tenant_id='northstar_demo' AND chunk_id='dbtest_public';
 -- Message-based summaries remain private until recipient ACL is configured.
 ctx:=comms.retrieve_context(j);
 UPDATE comms.drafts SET metadata=metadata||jsonb_build_object('message_evidence',jsonb_build_array((SELECT v FROM jsonb_array_elements(ctx->'inbox') v WHERE v->>'source'='dbtest_inbox' LIMIT 1))) WHERE draft_id=(d->>'draft_id')::uuid;
 PERFORM pg_temp.expect_error(format('SELECT comms.request_action(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send_noacl','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash')),'recipient ACL not configured');
 UPDATE comms.messages SET body=body||' changed' WHERE tenant_id='northstar_demo' AND source='dbtest_inbox';
 PERFORM pg_temp.expect_error(format('SELECT comms.request_action(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send_stalemessage','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash')),'message evidence is stale');
 UPDATE comms.drafts SET metadata=metadata-'message_evidence' WHERE draft_id=(d->>'draft_id')::uuid;
 UPDATE comms.drafts SET verification='{"passed":false}' WHERE draft_id=(d->>'draft_id')::uuid;
 PERFORM pg_temp.expect_error(format('SELECT comms.request_action(%L::jsonb)',jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','action','send','request_id','dbtest_send_failed','draft_id',d->>'draft_id','revision_hash',d->>'revision_hash')),'verification failed');

 UPDATE comms.tenants SET config=jsonb_set(config,'{live_models}','false') WHERE tenant_id='dbtest_other';
 a:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_disabled","max_cost_usd":0.001}');
 PERFORM pg_temp.assert_true(a->>'reason'='live_models_disabled','model gate disabled by default');
 UPDATE comms.tenants SET config=jsonb_set(config,'{live_models}','true') WHERE tenant_id='dbtest_other';
 r:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget1","max_cost_usd":0.04}'); rid:=(r->>'reservation_id')::uuid;
 PERFORM pg_temp.assert_true((r->>'call_permitted')::boolean,'first atomic reserve');
 a:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget1","max_cost_usd":0.04}');
 PERFORM pg_temp.assert_true(NOT(a->>'call_permitted')::boolean AND (a->>'replayed')::boolean,'reservation replay cannot call provider');
 a:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget_over","max_cost_usd":0.02}');
 PERFORM pg_temp.assert_true(a->>'reason'='daily_budget_cap','reserved worst case consumes budget');
 a:=comms.settle_budget(jsonb_build_object('tenant_id','dbtest_other','reservation_id',rid,'status','uncertain'));
 a:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget_still_over","max_cost_usd":0.02}');
 PERFORM pg_temp.assert_true(a->>'reason'='daily_budget_cap','uncertainty never auto refunds');
 PERFORM pg_temp.expect_error(format('SELECT comms.settle_budget(%L::jsonb)',jsonb_build_object('tenant_id','dbtest_other','reservation_id',rid,'status','settled','actual_cost_usd',0.001,'provider_call_id','test_call')),'proven call');
 a:=comms.settle_budget(jsonb_build_object('tenant_id','dbtest_other','reservation_id',rid,'status','settled','actual_cost_usd',0.001,'provider_call_id','test_call','proven',true));
 r:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget2","max_cost_usd":0.049}');
 PERFORM pg_temp.assert_true((r->>'call_permitted')::boolean,'only proven settlement releases difference');
 a:=comms.reserve_budget('{"tenant_id":"dbtest_other","request_id":"dbtest_budget_exact_over","max_cost_usd":0.00000001}');
 PERFORM pg_temp.assert_true(a->>'reason'='daily_budget_cap','hard exact daily cap');
 a:=comms.settle_budget(jsonb_build_object('tenant_id','dbtest_other','reservation_id',rid,'status','settled','actual_cost_usd',0.001,'provider_call_id','test_call','proven',true));
 PERFORM pg_temp.assert_true((a->>'replayed')::boolean,'settlement idempotence');
 RAISE NOTICE 'PASS: fixture/retrieval/style/fingerprint/job/lease/action/budget functional regression';
END $$;
ROLLBACK;
