-- No persistent records: every test-created row and mutation rolls back.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert_true(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT FAILED: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.expect_error(statement text,needle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF position(needle IN SQLERRM)>0 THEN RETURN; END IF;
  RAISE EXCEPTION 'wrong error: %, expected %',SQLERRM,needle;
 END;
 RAISE EXCEPTION 'expected error missing: %',needle;
END $$;
DO $$
DECLARE a jsonb; b jsonb; p jsonb; r jsonb; again jsonb; first_token text;
BEGIN
 INSERT INTO comms.tenants(tenant_id,config) VALUES
 ('claim_test_a','{"operators":["alice","alternate"]}'),('claim_test_b','{"operators":["bob"]}');
 b:=comms.enqueue_job('{"tenant_id":"claim_test_b","request_id":"older_b","channel":"email","input":{"requested_by":"bob","query":"older B"}}');
 UPDATE comms.jobs SET created_at='1900-01-01' WHERE job_id=(b->>'job_id')::uuid;
 a:=comms.enqueue_job('{"tenant_id":"claim_test_a","request_id":"newer_a","channel":"email","input":{"requested_by":"alice","query":"new A"}}');
 p:=jsonb_build_object('tenant_id','claim_test_a','job_id',a->>'job_id','actor_id','alice','worker_id','requested-claim-test');
 PERFORM pg_temp.expect_error(format('SELECT comms.claim_requested_job(%L::jsonb)',p||'{"actor_id":"outsider"}'),'unauthorized operator');
 PERFORM pg_temp.expect_error(format('SELECT comms.claim_requested_job(%L::jsonb)',p||'{"actor_id":"alternate"}'),'unauthorized job owner');
 PERFORM pg_temp.expect_error(format('SELECT comms.claim_requested_job(%L::jsonb)',p||jsonb_build_object('job_id',b->>'job_id')),'unknown tenant job');
 r:=comms.claim_requested_job(p); first_token:=r->>'lease_token';
 PERFORM pg_temp.assert_true((r->>'claimed')::boolean AND r->>'job_id'=a->>'job_id' AND (r->>'attempts')::int=1,'interactive A claims exact A, not oldest B');
 PERFORM pg_temp.assert_true((SELECT status='queued' AND attempts=0 AND lease_token IS NULL FROM comms.jobs WHERE job_id=(b->>'job_id')::uuid),'older other-tenant B untouched');
 again:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true(NOT(again->>'claimed')::boolean AND again->>'reason'='already_running','no double claim');
 PERFORM pg_temp.assert_true((SELECT attempts=1 AND lease_token::text=first_token FROM comms.jobs WHERE job_id=(a->>'job_id')::uuid),'replay does not increment attempts or replace lease');
 UPDATE comms.jobs SET lease_until=now()-interval '1 second' WHERE job_id=(a->>'job_id')::uuid;
 r:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true((r->>'claimed')::boolean AND (r->>'attempts')::int=2 AND r->>'lease_token'<>first_token,'recover exact expired lease with fresh token');
 r:=comms.fail_job(r||'{"error":"test retry"}');
 again:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true(NOT(again->>'claimed')::boolean AND again->>'reason'='not_ready','backoff respected');
 UPDATE comms.jobs SET available_at=now()-interval '1 second' WHERE job_id=(a->>'job_id')::uuid;
 r:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true((r->>'attempts')::int=3,'third and final attempt');
 UPDATE comms.jobs SET lease_until=now()-interval '1 second' WHERE job_id=(a->>'job_id')::uuid;
 again:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true(NOT(again->>'claimed')::boolean AND again->>'reason'='dead_letter','final expired lease dead letters exact row');
 PERFORM pg_temp.assert_true((SELECT attempts=3 AND lease_token IS NULL AND status='dead_letter' FROM comms.jobs WHERE job_id=(a->>'job_id')::uuid),'attempt bound and token invalidation');
 again:=comms.claim_requested_job(p);
 PERFORM pg_temp.assert_true(again->>'reason'='dead_letter','dead letter is stable');
 UPDATE comms.jobs SET status='completed',completed_at=now() WHERE job_id=(b->>'job_id')::uuid;
 again:=comms.claim_requested_job(jsonb_build_object('tenant_id','claim_test_b','job_id',b->>'job_id','actor_id','bob','worker_id','requested-claim-test'));
 PERFORM pg_temp.assert_true(NOT(again->>'claimed')::boolean AND again->>'reason'='completed','completed request cannot claim another job');
 RAISE NOTICE 'PASS: exact tenant/owner claim, no global fallback, replay, expired lease, bounded retries, completed state';
END $$;
ROLLBACK;
