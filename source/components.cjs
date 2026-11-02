'use strict';
const fs=require('fs'),path=require('path'); const logic=require('./logic.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'workflows'); 
const IDS={setup:'Comms00Setup2026',intake:'Comms01Inbox2026',concierge:'Comms02Slack2026',worker:'Comms03Draft2026',style:'Comms04Style2026',verify:'Comms05Verify26',outbox:'Comms06Outbox26'};
const pgCred={postgres:{id:'REPLACE_CREDENTIAL_ID',name:'Comms Agent · isolated PostgreSQL'}};
const orCred={openRouterApi:{id:'REPLACE_CREDENTIAL_ID',name:'OpenRouter account'}};
let workflows=[];
class Flow {
 constructor(key,name){this.key=key;this.w={id:IDS[key],name:'COMMS '+name,active:false,nodes:[],connections:{},settings:{executionOrder:'v1',saveManualExecutions:true,saveDataSuccessExecution:'none',saveDataErrorExecution:'all',executionTimeout:240,callerPolicy:'workflowsFromSameOwner'},pinData:{},tags:[]};}
 node(name,type,p,x,y,v=1,extra={}){this.w.nodes.push({id:this.key+'_'+this.w.nodes.length,name,type:'n8n-nodes-base.'+type,typeVersion:v,position:[x,y],parameters:p,...extra});return name;}
 code(name,js,x,y,funcs=[]){return this.node(name,'code',{jsCode:funcs.map(f=>logic[f].toString()).join('\n')+'\n'+js,mode:'runOnceForAllItems'},x,y,2);}
 pg(name,query,expr,x,y){return this.node(name,'postgres',{operation:'executeQuery',query,options:{queryReplacement:expr||'={{ [JSON.stringify($json)] }}'}},x,y,2.8,{credentials:pgCred});}
 fn(name,func,x,y,expr){return this.pg(name,'SELECT comms.'+func+'($1::jsonb) AS data;',expr,x,y);}
 trigger(name,x,y){return this.node(name,'executeWorkflowTrigger',{inputSource:'passthrough'},x,y,1.3);}
 manual(x,y){return this.node('Manual test','manualTrigger',{},x,y);}
 call(name,key,x,y){return this.node(name,'executeWorkflow',{source:'database',workflowId:{__rl:true,value:IDS[key],mode:'id'},mode:'each',options:{waitForSubWorkflow:true}},x,y,1.3);}
 note(text,x,y,w=650,h=180,color=5){return this.node('Guide '+this.w.nodes.length,'stickyNote',{content:text,width:w,height:h,color},x,y);}
 iff(name,condition,x,y){return this.node(name,'if',{conditions:{options:{caseSensitive:true,typeValidation:'strict',version:2},conditions:[{leftValue:condition,rightValue:true,operator:{type:'boolean',operation:'true',singleValue:true}}],combinator:'and'},options:{}},x,y,2.2);}
 http(name,url,body,x,y,artifact=false){return this.node(name,'httpRequest',{method:'POST',url,authentication:artifact?'genericCredentialType':'predefinedCredentialType',...(artifact?{genericAuthType:'httpHeaderAuth'}:{nodeCredentialType:'openRouterApi'}),sendBody:true,specifyBody:'json',jsonBody:body,options:{timeout:45000,response:{response:{responseFormat:'json'}}}},x,y,4.3,{credentials:artifact?{httpHeaderAuth:{id:'REPLACE_CREDENTIAL_ID',name:'Comms Agent · internal artifact token'}}:orCred,onError:'continueErrorOutput',retryOnFail:false});}
 link(a,b,index=0){let c=this.w.connections[a]||={main:[]};while(c.main.length<=index)c.main.push([]);c.main[index].push({node:b,type:'main',index:0});return this;}
 chain(...ns){for(let i=1;i<ns.length;i++)this.link(ns[i-1],ns[i]);return this;}
 done(){if(this.key==='worker'){const groups=[['Queued request wakeup','Manual test','Claim durable job + lease','A job is available?','Retrieve current public facts + style','Load worker policy','Prepare draft context','Live models enabled?'],['Reserve bounded job budget — 3 cents maximum','Budget permits this execution?','Generation call context','OpenRouter — economical structured draft','Parse draft and preserve evidence','Deterministic citation / number / language gate','Live draft passes deterministic gate?','Joey veto + Mammoth evidence/style check','One bounded rewrite needed?'],['DRY RUN — evidence-only fixture draft','Candidate has a model reservation?','Keep budget conservative when cost is uncertain','Restore final reviewed candidate','Create a report or PowerPoint file?','Compile document request','Compile PDF / PPTX — internal service','Attach document + keep audit metadata'],['No queued work — zero tokens','Capture failure for durable retry','Backoff / retry / dead letter','Persistable final artifact + evidence audit','Transaction — draft + review outbox + completed job','Load immutable draft for review','Slack review card — copy / save / explicit send']];groups.forEach((g,row)=>g.forEach((name,col)=>{const n=this.w.nodes.find(n=>n.name===name);if(n)n.position=[col*290,row*400];}));['Surgical rewrite — once only','OpenRouter — single corrective rewrite','Parse corrective draft'].forEach((name,i)=>{const n=this.w.nodes.find(n=>n.name===name);if(n)n.position=[(i+6)*290,1650];});}this.w.nodes.sort((a,b)=>(a.type==='n8n-nodes-base.manualTrigger'?-1:0)-(b.type==='n8n-nodes-base.manualTrigger'?-1:0));workflows.push(this.w);}
}
const unwrap='return $input.all().map(i=>({json:i.json.data}));';
// 00: explicit synthetic demo bootstrap. No external source or model calls.
{
 const f=new Flow('setup','00 · START HERE — seed + fingerprint demo');
 const m=f.manual(0,100);
 const fixture={tenant_id:'northstar_demo',rag_chunks:readJSONL('rag_chunks'),outbound_gold:readJSONL('outbound_gold'),events:[]};
 const load=f.code('Load clearly marked synthetic fixture','return [{json:'+JSON.stringify(fixture)+'}];',240,100);
 const seed=f.fn('Seed approved facts + sent example candidates','seed_fixture',500,100);
 const approve=f.pg('Explicit DEMO approval — fixture examples only',"SELECT comms.approve_examples(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','example_ids',(SELECT jsonb_agg(example_id) FROM comms.style_examples WHERE tenant_id='northstar_demo' AND source='fixture_gold'))) AS data;",'={{ [] }}',760,100);
 const ch=f.code('Build five versioned medium profiles',"return ['global','email','linkedin_message','linkedin_post','report'].map(channel=>({json:{tenant_id:'northstar_demo',actor_id:'demo_operator',channel,action:'compile'}}));",1020,100);
 const call=f.call('Compile each style fingerprint','style',1280,100);
 const ev=f.code('Replay mixed inbox events','return '+JSON.stringify(readJSONL('events'))+'.map(json=>({json:{...json,synthetic:true,source:"fixture_event"}}));',1540,100);
 const input=f.call('Classify + deduplicate test inbox','intake',1800,100);
 const done=f.code('Demo ready — next open Slack Concierge',"return [{json:{status:'synthetic_demo_ready',company:'Northstar Relay',profiles:5,gold_samples:100,inbox_events:20,models_called:0,next:'Open COMMS 02 Slack Concierge and execute the manual example',disconnected:['Slack','email','LinkedIn','cloud folders']}}];",2060,100);
 f.chain(m,load,seed,approve,ch,call,ev,input,done);
 f.note('# START HERE\nRun once to seed the isolated database and build **synthetic** fingerprints. No inference or outbound accounts. Replays deduplicate messages; fingerprint reruns create a new immutable version.\n\nThen open **COMMS 02**. This is an offline test environment, not cloud deployment.',0,-170,900,210,4);
 f.done();
}
// 01: transport-agnostic capture, internal exclusion before models.
{
 const f=new Flow('intake','01 · Inbox Capture — email forwards + channel adapters');
 const t=f.trigger('Normalized event from trusted adapter',0,100);
 const m=f.manual(0,330);const demo=f.code('Example forwarded customer email',`return [{json:{tenant_id:'northstar_demo',id:'manual-forward-'+$execution.id,source:'forwarded_email',channel:'email_forward',direction:'inbound',external:true,synthetic:true,body:'Could you send plan prices and explain the Enterprise SLA?',occurred_at:new Date().toISOString()}}];`,230,330);
 const n=f.code('Normalize · exclude internal · detect sent',"return $input.all().map(i=>({json:normalizeEvent(i.json)}));",500,100,['normalizeEvent']);
 const store=f.fn('Persist idempotent inbox + style candidate','ingest_event',780,100);
 const done=f.code('Capture receipt — no heavy generation',unwrap,1040,100);
 f.chain(t,n,store,done);f.chain(m,demo,n);
 const slack=f.node('Slack source adapter — DISCONNECTED','slackTrigger',{trigger:['message'],options:{}},0,620,1,{disabled:true});
 const email=f.node('Forwarded email adapter — DISCONNECTED','emailReadImap',{options:{},format:'resolved',postProcessAction:'nothing'},330,620,2,{disabled:true});
 const li=f.node('LinkedIn approved export adapter — DISCONNECTED','webhook',{httpMethod:'POST',path:'comms-linkedin-import-disabled',responseMode:'onReceived',options:{}},660,620,2,{disabled:true});
 f.note('# Light daytime path\nAuthenticating adapters normalize events into the subworkflow input. Internal Slack content is excluded from the external style corpus. Only confirmed **sent external** messages become pending style examples. Incoming messages never enter the approved factual KB.\n\nNo inference is necessary for reliable direction/domain rules. Ambiguous sources stay excluded until an adapter can verify their scope.',0,-210,1050,240,5);
 f.note('## Connect later\nDisabled adapters below are visible integration slots, not working connections. Email is forwarded-content intake only. LinkedIn DMs require approved API access or user-provided exports. Do not use private scraping endpoints. Cursor/replay handling belongs in each adapter.',0,850,1050,200,3);
 f.done();
}
// 02: Slack is the user interface. A demo path exercises the same command router.
{
 const f=new Flow('concierge','02 · Slack Concierge — request / review / save / send');
 const t=f.trigger('Authenticated Slack command envelope',0,100),m=f.manual(0,350);
 const demo=f.code('Edit this demo Slack request',"return [{json:{tenant_id:'northstar_demo',actor_id:'demo_operator',demo:true,request_id:'demo-slack-'+$execution.id,text:'draft email Explain the routing v2 pilot result, including its limits',reply_channel:'demo-review'}}];",230,350);
 const cfg=f.pg('Load trusted tenant policy','SELECT comms.tenant_config($1) AS data;','={{ [$json.tenant_id] }}',500,100);
 const parse=f.code('Authenticate operator + parse explicit command',"const original=$('Authenticated Slack command envelope').isExecuted ? $('Authenticated Slack command envelope').first().json : $('Edit this demo Slack request').first().json; return [{json:parseCommand(original,$input.first().json.data)}];",760,100,['parseCommand']);
 const draft=f.iff('Draft or report requested?',"={{ $json.route === 'draft' }}",1020,100),enqueue=f.fn('Queue request exactly once','enqueue_job',1280,0),worker=f.call('Run on-demand drafting worker','worker',1540,0);
 const action=f.iff('Explicit save or send?',"={{ $json.route === 'action' }}",1280,270),req=f.fn('Validate exact revision + stage action','request_action',1540,200);
 const fp=f.iff('Fingerprint command?',"={{ $json.route === 'fingerprint' }}",1540,450),style=f.call('Review / update style fingerprint','style',1800,380);
 const help=f.code('Show command help',"return [{json:{...$json,status:'No external action performed'}}];",1800,650);
 const resp=f.code('Return local Slack response preview',"return $input.all().map(i=>({json:{result:i.json.data||i.json,delivery:'staged_only',slack_connected:false}}));",2080,180);
 f.chain(t,cfg,parse,draft);f.chain(m,demo,cfg);f.chain(draft,enqueue,worker,resp);f.link(draft,action,1);f.chain(action,req,resp);f.link(action,fp,1);f.chain(fp,style,resp);f.link(fp,help,1);
 const st=f.node('Slack bot command trigger — DISCONNECTED','slackTrigger',{trigger:['app_mention','message'],options:{}},0,690,1,{disabled:true});
 f.note('# Slack is the front door\n`draft email <brief>` · `draft linkedin_message <brief>` · `draft linkedin_post <brief>` · `draft pptx <brief>` · `report <brief>`\n`send <draft-id> <revision-hash>` · `save <draft-id> <revision-hash>`\n`fingerprint <medium>` previews the candidate folder; explicit IDs approve and update it.\n\nDemo operator is local only. Live requests require a verified Slack workspace/user mapping; payload flags cannot create a public endpoint.',0,-260,1180,270,4);
 f.done();
}
// 03: one cheap draft, at most one surgical rewrite, immutable evidence and review output.
{
 const f=new Flow('worker','03 · On-demand Draft Worker — RAG → draft → review');
 const t=f.trigger('Queued request wakeup',0,100),m=f.manual(0,320);
 const claim=f.pg('Claim durable job + lease','SELECT comms.claim_job($1) AS data;','={{ ["n8n-" + $execution.id] }}',250,100);
 const has=f.iff('A job is available?',"={{ $json.data.claimed === true }}",510,100);
 const context=f.fn('Retrieve current public facts + style','retrieve_context',770,20,'={{ [JSON.stringify($json.data)] }}');
 const cfg=f.pg('Load worker policy','SELECT comms.tenant_config($1) AS data;','={{ [$("Claim durable job + lease").first().json.data.tenant_id] }}',1030,20);
 const prep=f.code('Prepare draft context',"return [{json:compilePrompt($('Retrieve current public facts + style').first().json.data,$('Claim durable job + lease').first().json.data,$input.first().json.data)}];",1290,20,['compilePrompt']);
 const live=f.iff('Live models enabled?',"={{ $json.cfg.live_models === true && $json.cfg.dry_run === false }}",1550,20);
 const budget=f.fn('Reserve bounded job budget — 3 cents maximum','reserve_budget',1810,-100,'={{ [JSON.stringify({tenant_id:$json.tenant_id,request_id:$json.job.job_id+":"+$json.job.attempts,max_cost_usd:0.03})] }}');
 const allowed=f.iff('Budget permits this execution?',"={{ $json.data.call_permitted === true }}",2070,-100);
 const restore=f.code('Generation call context',"const c=$('Prepare draft context').first().json; return [{json:{...c,budget:$input.first().json.data}}];",2330,-160);
 const gen=f.http('OpenRouter — economical structured draft','https://openrouter.ai/api/v1/chat/completions','={{ $json.request_body }}',2590,-160);
 const parsed=f.code('Parse draft and preserve evidence',"return [{json:parseGeneration($input.first().json,$('Generation call context').item.json)}];",2850,-160,['parseGeneration']);
 const fixture=f.code('DRY RUN — evidence-only fixture draft',"return [{json:dryDraft($json)}];",1810,230,['dryDraft']);
 const gate=f.code('Deterministic citation / number / language gate',"return [{json:preGate($json)}];",3110,100,['preGate']);
 const decision=f.iff('Live draft passes deterministic gate?',"={{ $json.mode === 'live' && $json.pregate.passed === true }}",3370,100);
 const verify=f.call('Joey veto + Mammoth evidence/style check','verify',3630,-30);
 const retry=f.iff('One bounded rewrite needed?',"={{ $json.mode === 'live' && $json.verification.passed !== true && $json.attempt < 1 }}",3890,100);
 const rewrite=f.code('Surgical rewrite — once only',"const x=$json; const feedback=JSON.stringify({pregate:x.pregate,joey:x.joey,verification:x.verification}); const r={...x.request_body,messages:[...x.request_body.messages.slice(0,2),{role:'assistant',content:JSON.stringify(x.generated)},{role:'user',content:'Correct only these failures using the same facts. Return the same JSON schema. '+feedback}]}; if(Buffer.byteLength(JSON.stringify(r),'utf8')>22000)throw Error('Rewrite context exceeds byte budget'); return [{json:{...x,attempt:x.attempt+1,request_body:r}}];",3890,380);
 // Preserve rewrite state through a dedicated call and parser; both use the same reservation.
 const regen=f.http('OpenRouter — single corrective rewrite','https://openrouter.ai/api/v1/chat/completions','={{ $json.request_body }}',4150,380);
 const reparse=f.code('Parse corrective draft',"const x=parseGeneration($json,$('Surgical rewrite — once only').item.json);return [{json:{...x,attempt:1}}];",4410,380,['parseGeneration']);
 const settle=f.fn('Keep budget conservative when cost is uncertain','settle_budget',4150,100,'={{ [JSON.stringify({tenant_id:$json.tenant_id,reservation_id:$json.budget.reservation_id,status:($json.model_calls?.length && $json.model_calls.every(c=>c.id && Number.isFinite(c.usage?.cost)))?"settled":"uncertain",proven:true,provider_call_id:($json.model_calls||[]).map(c=>c.id).join("|"),actual_cost_usd:($json.model_calls||[]).reduce((s,c)=>s+(c.usage?.cost||0),0)})] }}');
 const settled=f.code('Restore final reviewed candidate',"return [{json:$('One bounded rewrite needed?').item.json}];",4410,100);
 const long=f.iff('Create a report or PowerPoint file?',"={{ ['report','pptx'].includes($json.job.channel) }}",4670,100);
 const artprep=f.code('Compile document request',"const x=$json;return [{json:{...x,artifact_request:{artifact_id:x.job.job_id,channel:x.job.channel,banner:x.cfg.demo?'SYNTHETIC FIXTURE — NOT APPROVED FOR EXTERNAL USE':(x.verification.passed?'DRAFT — HUMAN REVIEW REQUIRED':'UNVERIFIED DRAFT — DO NOT SEND'),title:x.generated.title||'Requested company brief',body:x.generated.body,...(x.job.channel==='pptx'?{slides:x.generated.slides}:{})}}}];",4930,-30);
 const artifact=f.http('Compile PDF / PPTX — internal service','http://comms-agent-artifacts-1:8000/compile','={{ $json.artifact_request }}',5190,-30,true);
 const binary=f.code('Attach document + keep audit metadata',"const x=$('Compile document request').item.json;const a=$json;if(!a.sha256||!a.base64)throw Error('Missing artifact');return [{json:{...x,artifact:{artifact_id:x.job.job_id,filename:a.filename,mime_type:a.mime_type,sha256:a.sha256,size_bytes:a.size_bytes,visual_review_required:true}},binary:{data:{data:a.base64,mimeType:a.mime_type,fileName:a.filename}}}];",5450,-30);
 const final=f.code('Persistable final artifact + evidence audit',"const x=$json;return [{json:{tenant_id:x.tenant_id,job_id:x.job.job_id,lease_token:x.job.lease_token,verification:x.verification,draft:{body:x.draft.replace(/\\s*\\[[a-zA-Z0-9_-]+\\]/g,''),metadata:{mode:x.mode,coverage:x.coverage,evidence:x.facts,message_evidence:(x.inbox||[]).filter(m=>x.draft.includes('['+m.source_id+']')),pregate:x.pregate,joey:x.joey||null,attempt:x.attempt,fingerprint_versions:Object.fromEntries(Object.entries(x.fingerprint).map(([k,v])=>[k,v.version])),model_calls:x.model_calls||[],citation_draft:x.draft,artifact:x.artifact||null,request:x.job.input,generated:x.generated}},}}];",5710,100);
 const save=f.fn('Transaction — draft + review outbox + completed job','complete_job',5970,100);
 const lookup=f.fn('Load immutable draft for review','get_draft',6230,100,'={{ [JSON.stringify({tenant_id:$("Claim durable job + lease").first().json.data.tenant_id,actor_id:$("Claim durable job + lease").first().json.data.input.requested_by,draft_id:$json.data.draft_id})] }}');
 const card=f.code('Slack review card — copy / save / explicit send',"return [{json:reviewCard($json.data)}];",6490,100,['reviewCard']);
 const idle=f.code('No queued work — zero tokens',"return [{json:{status:'idle',models_called:0}}];",770,380);
 const fail=f.code('Capture failure for durable retry',"const j=$('Claim durable job + lease').first().json.data;return [{json:{tenant_id:j.tenant_id,job_id:j.job_id,lease_token:j.lease_token,error:String($json.error?.message||$json.message||'Node failed; inspect execution').slice(0,2000)}}];",3110,700);
 const failed=f.fn('Backoff / retry / dead letter','fail_job',3370,700);
 f.chain(t,claim,has,context,cfg,prep,live,budget,allowed,restore,gen,parsed,gate,decision,verify,retry);f.chain(m,claim);f.link(has,idle,1);f.link(live,fixture,1);f.chain(fixture,gate);f.link(allowed,fail,1);f.link(decision,retry,1);f.chain(retry,rewrite,regen,reparse,gate);f.link(retry,settle,1);f.chain(settle,settled,long);f.chain(long,artprep,artifact,binary,final,save,lookup,card);f.link(long,final,1);
 // Fixture paths have no budget reservation. Bypass the settlement node explicitly.
 const fixtureDone=f.iff('Candidate has a model reservation?',"={{ !!$json.budget?.reservation_id }}",4150,630);
 // redirect retry false into reservation check
 f.w.connections[retry].main[1]=[{node:fixtureDone,type:'main',index:0}];f.link(fixtureDone,settle);f.link(fixtureDone,long,1);
 f.chain(fail,failed);
 for(const n of [gen,regen,artifact])f.link(n,fail,1);
 for(const n of [context,cfg,prep,parsed,gate,verify,reparse,artprep,binary,final]){const node=f.w.nodes.find(z=>z.name===n);node.onError='continueErrorOutput';f.link(n,fail,1);}
 const schedule=f.node('Queued-job recovery every minute — DISABLED','scheduleTrigger',{rule:{interval:[{field:'minutes',minutesInterval:1}]}},0,230,1.2,{disabled:true});f.link(schedule,claim);
 f.note('# Heavy work happens only on a request\nOne draft → deterministic screen → Joey veto → Mammoth evidence/style check. At most one corrective rewrite. Every source is current, public-approved and tenant-filtered. A high score is an uncalibrated decision signal, not a factual guarantee.\n\nDry-run fixtures are visibly **unverified**, never send-eligible. Daily model reservation cap is $0.05, with $0.03 held per live job until usage can be reconciled.',0,-330,1370,280,4);
 f.note('## Durable failure path\nLeases, database job IDs, bounded attempts, exponential backoff and dead letters survive process restarts. HTTP requests never retry invisibly. A failed/uncertain provider call keeps its budget reservation. No workflow publishes or sends automatically.\n\nLong requests are bounded; larger section/slide-by-slide verification is a future expansion. Context over the byte cap stops for review.',2700,930,1200,220,3);
 f.done();
}
// 04: explicit candidate review; fingerprint profiles never ingest received messages.
{
 const f=new Flow('style','04 · Fingerprint Studio — pending sent → approved version');
 const t=f.trigger('Explicit fingerprint request',0,100),m=f.manual(0,350),d=f.code('Demo: compile approved email examples',"return [{json:{tenant_id:'northstar_demo',channel:'email',actor_id:'demo_operator',action:'compile'}}];",230,350);
 const prev=f.iff('Preview pending sent examples?',"={{ $json.action === 'preview' }}",500,100);
 const p=f.pg('Pending-sent folder — no automatic learning',"SELECT comms.require_operator($1,$3), jsonb_build_object('tenant_id',$1,'channel',$2,'candidates',coalesce((SELECT jsonb_agg(x) FROM (SELECT e.example_id,e.channel,left(e.content,200) AS preview,e.synthetic,e.approved FROM comms.style_examples e JOIN comms.messages m USING(tenant_id,message_id) WHERE e.tenant_id=$1 AND ($2='global' OR e.channel=$2) AND NOT e.approved AND m.direction='outbound' AND m.audience_class='external' AND m.confirmed_sent AND e.content_hash=encode(public.digest(m.body,'sha256'),'hex') ORDER BY e.created_at DESC LIMIT 30) x),'[]'::jsonb)) AS data;",'={{ [$json.tenant_id,$json.channel,$json.actor_id] }}',760,0);
 const pending=f.code('Slack folder card — one-click fingerprint update',"return [{json:fingerprintReviewCard($json.data)}];",1020,-20,['fingerprintReviewCard']);
 const update=f.iff('Explicit candidate IDs to approve?',"={{ $json.action === 'update' && $json.example_ids.length > 0 }}",760,250),approve=f.fn('Approve only selected current sent examples','approve_examples',1020,180);
 const restore=f.code('Preserve fingerprint request',"return [{json:$('Explicit candidate IDs to approve?').item.json}];",1280,180);
 const samples=f.fn('Load approved current examples — medium scoped','get_style_examples',1540,250,'={{ [JSON.stringify({tenant_id:$json.tenant_id,channel:$json.channel})] }}');
 const compute=f.code('Extract 14 measurable style statistics',"const d=$json.data; const req=$('Explicit candidate IDs to approve?').item.json;return [{json:fingerprint({...d,actor_id:req.actor_id})}];",1800,250,['fingerprint']);
 const store=f.fn('Store immutable version + activate profile','store_fingerprint',2060,250);
 const receipt=f.code('Fingerprint update receipt',"const f=$json.data;return [{json:{tenant_id:f.tenant_id,channel:f.channel,version:f.version,provenance:f.provenance,sample_size:f.profile.sample_size,status:'active_uncalibrated',previous_versions_retained:true}}];",2320,250);
 f.chain(t,prev);f.chain(m,d,prev);f.chain(prev,p,pending);f.link(prev,update,1);f.chain(update,approve,restore,samples,compute,store,receipt);f.link(update,samples,1);
 f.note('# Review sent examples before learning\nUse `fingerprint email` to preview the pending-sent folder. Then select explicit example IDs to approve and rebuild. Incoming, internal, unsent and superseded text is excluded. Each channel inherits the global style and overrides measured differences.\n\nMinimum 20 eligible approved samples. The demo has 25 per medium. All seeded profiles remain marked **synthetic / uncalibrated**. Dependency-parser metrics and semantic style descriptors are deferred; the 14 actual measurements are listed in the profile.',0,-230,1220,260,4);
 f.done();
}
// 05: typed Decisions contracts, strict response validation, no authorization decisions.
{
 const f=new Flow('verify','05 · System 1 Verification — Joey veto / Mammoth NLI');
 const t=f.trigger('One bounded candidate with approved sources',0,100);
 const req=f.code('Compile Joey typed veto',"return [{json:{...$json,decision_body:decisionRequest($json,'quick')}}];",260,100,['decisionRequest']);
 const http=f.http('OpenRouter Decisions — Joey','https://openrouter.ai/api/alpha/decisions','={{ $json.decision_body }}',520,100);
 const parse=f.code('Validate Joey answer — never approval',"const x=evaluateDecision($json,$('Compile Joey typed veto').item.json,'quick');return [{json:{...x,joey_raw:$json}}];",780,100,['evaluateDecision']);
 const ok=f.iff('Joey has not vetoed?',"={{ $json.joey.passed === true }}",1040,100);
 const mm=f.code('Compile Mammoth fact + voice rubric',"return [{json:{...$json,decision_body:decisionRequest($json,'deep')}}];",1300,20,['decisionRequest']);
 const mh=f.http('OpenRouter Decisions — Mammoth','https://openrouter.ai/api/alpha/decisions','={{ $json.decision_body }}',1560,20);
 const mp=f.code('Strict answer validation + thresholds',"return [{json:{...evaluateDecision($json,$('Compile Mammoth fact + voice rubric').item.json,'deep'),mammoth_raw:$json}}];",1820,20,['evaluateDecision']);
 const veto=f.code('Veto — route to bounded rewrite or review',"return [{json:{...$json,verification:{passed:false,reason:'joey_veto',human_review_required:true}}}];",1300,330);
 const fail=f.code('Evaluator error — fail closed',"const x=$('One bounded candidate with approved sources').first().json;return [{json:{...x,verification:{passed:false,reason:'evaluation_error',detail:String($json.error?.message||$json.message||'Malformed response').slice(0,1000),human_review_required:true}}}];",1820,450);
 f.chain(t,req,http,parse,ok,mm,mh,mp);f.link(ok,veto,1);
 for(const n of [req,http,parse,mm,mh,mp]){f.w.nodes.find(z=>z.name===n).onError='continueErrorOutput';f.link(n,fail,1);}
 f.note('# Correct OpenRouter System 1 adapter\nUses **Decisions**, not chat completions: `answers.style.noul`, `answers.fact.probabilities`, `answers.voice.score`. Date-pinned model builds, question dictionaries and bounded payloads. Joey may veto; only a full deterministic + Mammoth pass can make a draft send-eligible after human approval.\n\nModel probabilities need calibration against held-out company examples. Missing / malformed answers fail closed. Internal data is never supplied as an alternative fact source.',0,-230,1150,270,5);
 f.done();
}
// 06: previews the durable outbox, and contains clearly disabled future adapters.
{
 const f=new Flow('outbox','06 · Outbox & Recovery — preview / adapters disconnected');
 const m=f.manual(0,100),t=f.trigger('Recovery / review request',0,320);
 const p=f.code('Tenant-scoped review configuration',"return $input.all().map(i=>{const t=i.json.tenant_id||'northstar_demo';if(t!=='northstar_demo'&&!i.json.actor_id)throw Error('Operator required');return {json:{tenant_id:t,actor_id:i.json.actor_id||(t==='northstar_demo'?'demo_operator':null)}};});",260,100);
 const q=f.fn('Read held notifications and explicit actions','prepare_outbox',520,100);
 const list=f.code('Expand review items',"const d=$json.data;return d.items.length?d.items.map(json=>({json})):[{json:{empty:true,status:'No pending output'}}];",780,100);
 const has=f.iff('Pending draft/action exists?',"={{ $json.empty !== true }}",1040,100);
 const get=f.fn('Fetch draft and complete artifact metadata','get_draft',1300,20,'={{ [JSON.stringify({tenant_id:$json.tenant_id,actor_id:$("Tenant-scoped review configuration").item.json.actor_id||"demo_operator",draft_id:$json.draft_id})] }}');
 const card=f.code('Build Slack review blocks + copyable text',"return $input.all().map(i=>({json:{...reviewCard(i.json.data),draft:i.json.data},...(i.binary?{binary:i.binary}:{})}));",1560,20,['reviewCard']);
 const held=f.code('HELD — no external adapter connected',"return $input.all().map(i=>({json:{...i.json,status:'held',delivered:false,reason:'Connect and verify Slack/folder/send adapters before enabling dispatch'},...(i.binary?{binary:i.binary}:{})}));",1820,20);
 const schedule=f.node('Every minute recovery — DISABLED until deployment','scheduleTrigger',{rule:{interval:[{field:'minutes',minutesInterval:1}]}},0,620,1.2,{disabled:true});
 const slack=f.node('Post review to Slack — DISCONNECTED','slack',{resource:'message',operation:'post',select:'channel',channelId:{__rl:true,value:'',mode:'id'},messageType:'block',blocksUi:'={{ JSON.stringify($json.blocks) }}',text:'={{ $json.text }}',otherOptions:{}},1300,620,2.3,{disabled:true});
 const mail=f.node('Send approved email — DISCONNECTED','emailSend',{fromEmail:'',toEmail:'',subject:'',emailFormat:'text',text:'',options:{}},1620,620,2.1,{disabled:true});
 const folder=f.node('Save approved file to folder — DISCONNECTED','httpRequest',{method:'POST',url:'https://example.invalid/choose-cloud-folder-adapter',options:{}},1940,620,4.3,{disabled:true});
 const li=f.node('LinkedIn post / DM export — DISCONNECTED','noOp',{},2260,620,1,{disabled:true});
 const file=f.iff('Stored document exists?',"={{ !!$json.data.metadata?.artifact?.filename }}",1560,290);
 const fetch=f.node('Retrieve exact persisted artifact','httpRequest',{url:'={{ \"http://comms-agent-artifacts-1:8000/artifacts/\" + encodeURIComponent($json.data.metadata.artifact.filename) }}',authentication:'genericCredentialType',genericAuthType:'httpHeaderAuth',options:{timeout:15000,response:{response:{responseFormat:'json'}}}},1820,290,4.3,{credentials:{httpHeaderAuth:{id:'REPLACE_CREDENTIAL_ID',name:'Comms Agent · internal artifact token'}}});
 const attach=f.code('Reattach verified document bytes',"return $input.all().map((i,index)=>{const a=i.json;const d=$('Stored document exists?').itemMatching(index).json.data;if(a.sha256!==d.metadata.artifact.sha256)throw Error('Artifact checksum changed');return {json:{data:d},binary:{data:{data:a.base64,fileName:a.filename,mimeType:a.mime_type}}};});",2080,290);
 f.chain(m,p,q,list,has,get,file,fetch,attach,card,held);f.link(file,card,1);f.chain(t,p);f.link(schedule,p);
 f.note('# Durable review outbox\nRows remain held until a real adapter acknowledges delivery. Copyable content, source audit and file metadata remain available in PostgreSQL. Slack Block Kit payloads include Save and exact-revision Send controls only when eligible.\n\nSlack client copy controls vary; the code block and plain text attachment are the copy fallback. Browser clipboard buttons are not supported by Block Kit. Folder uploads and email/LinkedIn sends intentionally remain disconnected.',0,-230,1200,260,4);
 f.note('## Cloud enablement\nSchedule COMMS 03 for queued jobs and COMMS 06 for outbox recovery. Add provider-authenticated ingress adapters, verified Slack users, target recipients, a folder, dispatcher acknowledgement/idempotency, backups, HTTPS and monitoring before activation. The existing local n8n volume is preserved.\n\nA disabled node is a connection slot, not a completed live integration.',500,870,1200,220,3);
 f.done();
}
function readJSONL(name){return fs.readFileSync(path.join(root,'fixtures',name+'.jsonl'),'utf8').trim().split('\n').map(JSON.parse);}
module.exports={components:workflows,legacyIds:IDS};
