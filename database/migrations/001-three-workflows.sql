-- Additive migration for tenant/owner-scoped interactive claims. PostgreSQL 16.
-- The adapter authenticates the actor; SQL checks its configured allowlist and job ownership.
BEGIN;
CREATE OR REPLACE FUNCTION comms.claim_requested_job(payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
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
COMMIT;
