'use strict';
// Build exactly three installed workflows. Components are node groups, never hidden/runtime workflows.
const fs=require('fs'),path=require('path');
const {components}=require('./components.cjs');
const root=path.resolve(__dirname,'..');
const IDS={knowledge:'CommsVoiceKB2026',backend:'CommsBackend2026',main:'CommsMain2026'};
const byKey=Object.fromEntries(components.map(w=>[w.nodes.find(n=>n.type!=='n8n-nodes-base.stickyNote').id.split('_')[0],w]));
let seq=0;
const copy=x=>JSON.parse(JSON.stringify(x));
function walkStrings(o,fn){if(typeof o==='string')return fn(o);if(Array.isArray(o))return o.map(x=>walkStrings(x,fn));if(o&&typeof o==='object')return Object.fromEntries(Object.entries(o).map(([k,v])=>[k,walkStrings(v,fn)]));return o;}
function part(key,prefix){
 const w=copy(byKey[key]);if(!w)throw Error('Missing component '+key);
 w.nodes=w.nodes.filter(n=>n.type!=='n8n-nodes-base.stickyNote');
 const names=Object.fromEntries(w.nodes.map(n=>[n.name,prefix+' · '+n.name]));
 const rename=s=>{for(const [a,b] of Object.entries(names)){s=s.split("$('"+a+"')").join("$('"+b+"')").split('$("'+a+'")').join('$("'+b+'")');}return s;};
 for(const n of w.nodes){n.name=names[n.name];n.id=prefix.toLowerCase()+'_'+n.id;n.parameters=walkStrings(n.parameters,rename);if(n.type==='n8n-nodes-base.executeWorkflowTrigger'){n.type='n8n-nodes-base.noOp';n.typeVersion=1;n.parameters={};}}
 w.connections=Object.fromEntries(Object.entries(w.connections).map(([name,c])=>[names[name],walkStrings(c,s=>names[s]||s)]));
 return {nodes:w.nodes,connections:w.connections,names,n:old=>names[old]};
}
function flow(key,title,parts){const w={id:IDS[key],name:'COMMS '+title,active:false,nodes:parts.flatMap(p=>p.nodes),connections:Object.assign({},...parts.map(p=>p.connections)),settings:{executionOrder:'v1',saveManualExecutions:true,saveDataSuccessExecution:'none',saveDataErrorExecution:'all',executionTimeout:240,callerPolicy:'workflowsFromSameOwner'},pinData:{},tags:[]};return w;}
function node(w,name,type,parameters={},position=[0,0],version=1,extra={}){w.nodes.push({id:'three_'+(++seq),name,type:'n8n-nodes-base.'+type,typeVersion:version,parameters,position,...extra});return name;}
function code(w,name,js,pos){return node(w,name,'code',{mode:'runOnceForAllItems',jsCode:js},pos,2);}
function note(w,name,text,pos,width=1600,height=190,color=4){return node(w,name,'stickyNote',{content:text,width,height,color},pos);}
function get(w,name){const n=w.nodes.find(n=>n.name===name);if(!n)throw Error('Missing node '+name);return n;}
function link(w,a,b,index=0){const c=w.connections[a]||={main:[]};while(c.main.length<=index)c.main.push([]);c.main[index].push({node:b,type:'main',index:0});}
function setNext(w,a,targets,index=0){const c=w.connections[a]||={main:[]};while(c.main.length<=index)c.main.push([]);c.main[index]=targets.map(node=>({node,type:'main',index:0}));}
function remove(w,name){w.nodes=w.nodes.filter(n=>n.name!==name);delete w.connections[name];for(const c of Object.values(w.connections))for(const a of c.main)for(let i=a.length-1;i>=0;i--)if(a[i].node===name)a.splice(i,1);}
function noOp(w,name){const n=get(w,name);n.type='n8n-nodes-base.noOp';n.typeVersion=1;n.parameters={};delete n.credentials;delete n.onError;if(w.connections[name])w.connections[name].main=[w.connections[name].main[0]||[]];}
function iff(w,name,expr,pos){return node(w,name,'if',{conditions:{options:{caseSensitive:true,typeValidation:'strict',version:2},conditions:[{leftValue:expr,rightValue:true,operator:{type:'boolean',operation:'true',singleValue:true}}],combinator:'and'},options:{}},pos,2.2);}
function rootRouter(w,key,ops,defaultExpr){
 const start=node(w,'Internal · operation request','executeWorkflowTrigger',{inputSource:'passthrough'},[-500,-350],1.3);
 const route=code(w,'Internal · validate operation',`if($input.all().length!==1)throw Error('Use one operation envelope per execution');return $input.all().map((i,index)=>{const op=i.json._op||(${defaultExpr});if(!${JSON.stringify(Object.keys(ops))}.includes(op))throw Error('Unknown internal operation');return {json:{...i.json,_op:op},pairedItem:{item:index}};});`,[-220,-350]);link(w,start,route);
 let prev=route;
 const entries=Object.entries(ops);
 for(let i=0;i<entries.length;i++){const [op,target]=entries[i];const cond=iff(w,'Internal · route '+op,`={{ $json._op === '${op}' }}`,[i*280,-350]);link(w,prev,cond,prev===route?0:1);link(w,cond,target);prev=cond;}
 const reject=code(w,'Internal · reject unknown operation',"throw Error('Unsupported operation');",[entries.length*280,-350]);link(w,prev,reject,1);
}
function callOther(w,original,target,op,wait=true){
 const n=get(w,original);n.parameters={source:'database',workflowId:{__rl:true,value:IDS[target],mode:'id'},mode:'each',options:{waitForSubWorkflow:wait}};
 const before=code(w,original+' · set operation',`return $input.all().map((i,index)=>({json:{...i.json,_op:'${op}'},...(i.binary?{binary:i.binary}:{}),pairedItem:{item:index}}));`,[n.position[0]-220,n.position[1]]);
 for(const c of Object.values(w.connections))for(const a of c.main)for(const edge of a)if(edge.node===original)edge.node=before;
 link(w,before,original);
}
function groupGrid(w,names,x,y,cols=7){names.forEach((name,i)=>{if(w.nodes.some(n=>n.name===name))get(w,name).position=[x+(i%cols)*310,y+Math.floor(i/cols)*330];});}
function namesExcept(p,excluded=[]){return p.nodes.map(n=>n.name).filter(n=>!excluded.includes(n));}
// 1: fingerprints, explicit demo bootstrap and approved knowledge preparation.
const seed=part('setup','Seed'),style=part('style','Style');
const knowledge=flow('knowledge','1 · Fingerprints & Knowledge',[seed,style]);
const seedBegin=node(knowledge,'Seed · explicit bootstrap entry','noOp',{},[0,1200]);
setNext(knowledge,seed.n('Manual test'),[seedBegin]);link(knowledge,seedBegin,seed.n('Load clearly marked synthetic fixture'));
noOp(knowledge,seed.n('Compile each style fingerprint'));setNext(knowledge,seed.n('Compile each style fingerprint'),[style.n('Explicit fingerprint request')]);
// Mapping all items preserves the former five separate child executions at the store barrier.
get(knowledge,style.n('Extract 14 measurable style statistics')).parameters.jsCode=get(knowledge,style.n('Extract 14 measurable style statistics')).parameters.jsCode.replace("const d=$json.data; const req=$('Style · Explicit candidate IDs to approve?').item.json;return [{json:fingerprint({...d,actor_id:req.actor_id})}];", "return $input.all().map((item,index)=>{const req=$('Style · Explicit candidate IDs to approve?').itemMatching(index).json;return {json:fingerprint({...item.json.data,actor_id:req.actor_id}),pairedItem:{item:index}};});");
get(knowledge,style.n('Fingerprint update receipt')).parameters.jsCode="return $input.all().map((i,index)=>{const f=i.json.data;return {json:{tenant_id:f.tenant_id,channel:f.channel,version:f.version,provenance:f.provenance,sample_size:f.profile.sample_size,status:'active_uncalibrated',previous_versions_retained:true},pairedItem:{item:index}};});";
const continuation=iff(knowledge,'Seed · continue only after all profiles stored',"={{ $('Seed · explicit bootstrap entry').isExecuted }}",[0,1000]);
link(knowledge,style.n('Fingerprint update receipt'),continuation);link(knowledge,continuation,seed.n('Replay mixed inbox events'));
// Bootstrap approval only selects current eligible fixture hashes, never stale source revisions.
get(knowledge,seed.n('Explicit DEMO approval — fixture examples only')).parameters.query="SELECT comms.approve_examples(jsonb_build_object('tenant_id','northstar_demo','actor_id','demo_operator','example_ids',(SELECT jsonb_agg(e.example_id) FROM comms.style_examples e JOIN comms.messages m USING(tenant_id,message_id) WHERE e.tenant_id='northstar_demo' AND e.source='fixture_gold' AND e.synthetic AND m.direction='outbound' AND m.audience_class='external' AND m.confirmed_sent AND e.content_hash=encode(public.digest(m.body,'sha256'),'hex')))) AS data;";
callOther(knowledge,seed.n('Classify + deduplicate test inbox'),'backend','capture');
get(knowledge,seed.n('Demo ready — next open Slack Concierge')).parameters.jsCode="return [{json:{status:'synthetic_demo_ready',company:'Northstar Relay',profiles:5,gold_samples:100,inbox_events:20,models_called:0,next:'Open COMMS 3 Main Chat & Work',disconnected:['Slack','email','LinkedIn','cloud folders']}}];";
rootRouter(knowledge,'knowledge',{fingerprint:style.n('Explicit fingerprint request'),bootstrap:seedBegin},"'fingerprint'");
groupGrid(knowledge,namesExcept(style),0,100,6);groupGrid(knowledge,[...namesExcept(seed),seedBegin,continuation],0,1450,6);
get(knowledge,continuation).position=[1860,760];
note(knowledge,'Guide · fingerprints','# 1 · Fingerprints & knowledge\nApproved sent examples → review → 14 measured statistics → immutable medium/global profiles. Minimum 20 eligible samples; real examples require explicit human approval. Incoming/internal/unsent text never trains the fingerprint.\n\nKnowledge embeddings remain deferred. Current factual retrieval is PostgreSQL full-text/trigram; keep factual KB approval separate from voice examples.',[0,-150],1850,220);
note(knowledge,'Guide · bootstrap','## Optional synthetic demo bootstrap\nManual seed is explicit and demo-only. All FIVE profile stores complete before the mixed inbox replay. Existing source IDs deduplicate. The old seven-flow version is held in the rollback export, not called by this workflow.',[0,1150],1850,210,5);
// 2: capture and outbox are independent executions within one backend canvas.
const intake=part('intake','Capture'),outbox=part('outbox','Outbox');
const backend=flow('backend','2 · Sorting & Backend',[intake,outbox]);
const artifactRead=get(backend,outbox.n('Retrieve exact persisted artifact'));artifactRead.parameters.options.batching={batch:{batchSize:1,batchInterval:75}};artifactRead.retryOnFail=true;artifactRead.maxTries=3;artifactRead.waitBetweenTries=1000;
rootRouter(backend,'backend',{capture:intake.n('Normalized event from trusted adapter'),outbox:outbox.n('Recovery / review request')},"typeof i.json.body==='string'?'capture':'outbox'");
groupGrid(backend,namesExcept(intake),0,100,6);groupGrid(backend,namesExcept(outbox),0,1100,7);
note(backend,'Guide · capture','# 2 · Sorting & backend\nNormalize trusted-adapter events → exclude internal text → deduplicate → persist external inbox and pending sent examples. Stable IDs, source revisions, tenant policy and approval checks stay in PostgreSQL. No heavy inference during ordinary capture.',[0,-150],1900,210);
note(backend,'Guide · outbox','## Durable outbox / background recovery\nSeparate executions inspect held outputs, reconstruct exact document bytes and prepare Slack review cards. Delivery adapters and schedules remain disabled. Never acknowledge sending without a provider receipt. Queue recovery wakes Main in a separate execution; Main claims once.',[0,850],1900,210,5);
// 3: combine command routing, drafting and the two typed decision gates, with no hidden workflows.
const chat=part('concierge','Chat'),work=part('worker','Work'),verify=part('verify','Verify');
const main=flow('main','3 · Main Chat & Work',[chat,work,verify]);
remove(main,work.n('Manual test'));
const oldSchedule=get(main,work.n('Queued-job recovery every minute — DISABLED'));remove(main,oldSchedule.name);oldSchedule.name='Recovery · queued jobs every minute — DISABLED';oldSchedule.position=[0,2500];backend.nodes.push(oldSchedule);
const wake=code(backend,'Recovery · wake main worker',"return [{json:{_op:'work'}}];",[310,2500]);
const dispatch=node(backend,'Recovery · independent main execution','executeWorkflow',{source:'database',workflowId:{__rl:true,value:IDS.main,mode:'id'},mode:'each',options:{waitForSubWorkflow:false}},[620,2500],1.3);
link(backend,oldSchedule.name,wake);link(backend,wake,dispatch);
noOp(main,chat.n('Run on-demand drafting worker'));setNext(main,chat.n('Run on-demand drafting worker'),[work.n('Queued request wakeup')]);
for(const terminal of ['Slack review card — copy / save / explicit send','No queued work — zero tokens','Backoff / retry / dead letter'])link(main,work.n(terminal),chat.n('Return local Slack response preview'));
callOther(main,chat.n('Review / update style fingerprint'),'knowledge','fingerprint');
// Exact requested job for a chat; global dequeue only for a trusted worker recovery execution.
get(main,work.n('Claim durable job + lease')).parameters.query="SELECT CASE WHEN ($1::jsonb ? 'job_id') THEN comms.claim_requested_job($1::jsonb) ELSE comms.claim_job($2) END AS data;";
get(main,work.n('Claim durable job + lease')).parameters.options.queryReplacement='={{ [JSON.stringify($("Chat · Queue request exactly once").isExecuted ? {tenant_id:$("Chat · Queue request exactly once").first().json.data.tenant_id,job_id:$("Chat · Queue request exactly once").first().json.data.job_id,actor_id:$("Chat · Queue request exactly once").first().json.data.input.requested_by,worker_id:"n8n-"+$execution.id} : {}),"n8n-"+$execution.id] }}';
// Inline Verify: preserve current run context even on attempt1; errors retain uncertain budget.
noOp(main,work.n('Joey veto + Mammoth evidence/style check'));setNext(main,work.n('Joey veto + Mammoth evidence/style check'),[verify.n('One bounded candidate with approved sources')]);
for(const terminal of ['Strict answer validation + thresholds','Veto — route to bounded rewrite or review'])link(main,verify.n(terminal),work.n('One bounded rewrite needed?'));
const quickFail=verify.n('Evaluator error — fail closed');
get(main,quickFail).name=quickFail;get(main,quickFail).parameters.jsCode="const x=$('Verify · One bounded candidate with approved sources').itemMatching(0).json;return [{json:{...x,budget_uncertain:true,verification:{passed:false,reason:'evaluation_error',detail:String($json.error?.message||$json.message||'Invalid Joey response').slice(0,1000),human_review_required:true}}}];";
const deepFail=code(main,'Verify · Mammoth error — keep current attempt and spend',"const x=$('Verify · Validate Joey answer — never approval').itemMatching(0).json;return [{json:{...x,budget_uncertain:true,verification:{passed:false,reason:'evaluation_error',detail:String($json.error?.message||$json.message||'Invalid Mammoth response').slice(0,1000),human_review_required:true}}}];",[0,0]);
for(const name of ['Compile Mammoth fact + voice rubric','OpenRouter Decisions — Mammoth','Strict answer validation + thresholds'])setNext(main,verify.n(name),[deepFail],1);
link(main,quickFail,work.n('One bounded rewrite needed?'));link(main,deepFail,work.n('One bounded rewrite needed?'));
get(main,work.n('Keep budget conservative when cost is uncertain')).parameters.options.queryReplacement=get(main,work.n('Keep budget conservative when cost is uncertain')).parameters.options.queryReplacement.replace('$json.model_calls?.length &&','$json.budget_uncertain !== true && $json.model_calls?.length &&');
// Shortened HTTP timeouts fit two bounded attempts comfortably inside workflow/lease bounds.
for(const n of main.nodes){if(n.type==='n8n-nodes-base.httpRequest' && n.parameters.url?.startsWith('https://openrouter.ai/'))n.parameters.options.timeout=n.name.includes('Joey')?20000:30000;if(n.name===work.n('Compile PDF / PPTX — internal service'))n.parameters.options.timeout=15000;}
// Persist uncertainty with the immutable audit as well as in the reservation ledger.
get(main,work.n('Persistable final artifact + evidence audit')).parameters.jsCode=get(main,work.n('Persistable final artifact + evidence audit')).parameters.jsCode.replace('model_calls:x.model_calls||[],','budget_uncertain:x.budget_uncertain===true,model_calls:x.model_calls||[],');
rootRouter(main,'main',{chat:chat.n('Authenticated Slack command envelope'),work:work.n('Queued request wakeup')},"typeof i.json.text==='string'||i.json.action_id?'chat':'work'");
groupGrid(main,namesExcept(chat),0,150,7);
const workNames=namesExcept(work,[work.n('Manual test'),work.n('Queued-job recovery every minute — DISABLED')]);groupGrid(main,workNames,0,1350,8);groupGrid(main,namesExcept(verify).concat(deepFail),0,3200,7);
note(main,'Guide · chat','# 3 · Main Slack chat & work\nCommands and button actions authenticate the configured operator. Requests queue once; interactive work claims ONLY its canonical tenant/job. One candidate, at most one rewrite, current public facts, citations and exact-revision human approval remain mandatory.',[0,-100],2200,210);
note(main,'Guide · drafting','## Drafting / files / review\nSame models, fingerprint inheritance, source filters, 3-cent reservation and 5-cent daily test cap. Dry-run creates visibly unverified fixtures. PDF/PPTX compilation keeps the review banner and checksum. Failures use durable bounded retries/dead letters. No external account is connected.',[0,1080],2200,210,5);
note(main,'Guide · decisions','## System 1 verification — inline\nJoey veto → Mammoth NLI + voice → strict answer validation. Current-attempt checkpoints survive the corrective pass. Any evaluator transport/parser error retains an UNCERTAIN reservation rather than refunding incomplete spend. No extra paid tests are part of this consolidation.',[0,2930],2200,210,3);
const built=[knowledge,backend,main];
require('./reduce-nodes.cjs')(built);
require('./layout.cjs')(built);
require('./slack-demo.cjs')(built);
require('./natural-conversation.cjs')(built);
for(const w of built){
 w.nodes.sort((a,b)=>(a.type==='n8n-nodes-base.manualTrigger'?-1:0)-(b.type==='n8n-nodes-base.manualTrigger'?-1:0));
 const names=new Set(w.nodes.map(n=>n.name));if(names.size!==w.nodes.length)throw Error('Duplicate node names');
 for(const [name,c] of Object.entries(w.connections)){if(!names.has(name))throw Error('Unknown source '+name);for(const output of c.main)for(const e of output)if(!names.has(e.node))throw Error('Unknown target '+e.node);}
 for(const n of w.nodes){if(n.type==='n8n-nodes-base.code')new Function(n.parameters.jsCode);const text=JSON.stringify(n.parameters);for(const m of text.matchAll(/\$\((?:'|\\")(.*?)(?:'|\\")\)/g)){if(!names.has(m[1]))throw Error('Missing node reference '+m[1]+' in '+n.name);}if(n.type==='n8n-nodes-base.executeWorkflow'&&!Object.values(IDS).includes(n.parameters.workflowId.value))throw Error('Legacy workflow reference');}
 if(w.nodes.filter(n=>n.type==='n8n-nodes-base.executeWorkflowTrigger').length!==1)throw Error('Exactly one internal operation trigger required');
}
const out=path.join(root,'workflows');fs.mkdirSync(out,{recursive:true});
// Generated directory has only the three deployable definitions; legacy files move to rollback.
const obsolete=['setup','intake','concierge','worker','style','verify','outbox'];
for(const key of obsolete){const file=path.join(out,key+'.json');if(fs.existsSync(file))fs.renameSync(file,path.join(root,'rollback',key+'-legacy.json'));}
for(let i=0;i<built.length;i++)fs.writeFileSync(path.join(out,Object.keys(IDS)[i]+'.json'),JSON.stringify(built[i],null,2)+'\n');
fs.writeFileSync(path.join(root,'all-workflows.json'),JSON.stringify(built,null,2)+'\n');
fs.writeFileSync(path.join(root,'workflow-index.json'),JSON.stringify(built.map(w=>({id:w.id,name:w.name,nodes:w.nodes.filter(n=>n.type!=='n8n-nodes-base.stickyNote').length,url:'http://localhost:5678/workflow/'+w.id})),null,2)+'\n');
console.log(JSON.stringify(built.map(w=>({id:w.id,name:w.name,nodes:w.nodes.length}))));
module.exports={built,IDS};
