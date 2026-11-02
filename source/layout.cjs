'use strict';
// Visual layout only. Preserve each source node's original target ordering.
module.exports=function applyLayout(flows){
 const tables={
  CommsVoiceKB2026:[
   [0,0,['Internal · operation request','Internal · validate operation','Internal · route fingerprint','Internal · route bootstrap','Internal · reject unknown operation']],
   [0,520,['Seed · Manual test','Seed · explicit bootstrap entry','Seed · Load clearly marked synthetic fixture','Seed · Seed approved facts + sent example candidates','Seed · Explicit DEMO approval — fixture examples only','Seed · Build five versioned medium profiles']],
   [0,1150,['Style · Manual test','Style · Demo: compile approved email examples','Style · Preview pending sent examples?','Style · Pending-sent folder — no automatic learning','Style · Slack folder card — one-click fingerprint update']],
   [850,1500,['Style · Explicit candidate IDs to approve?','Style · Approve only selected current sent examples','Style · Preserve fingerprint request']],
   [850,1880,['Style · Load approved current examples — medium scoped','Style · Extract 14 measurable style statistics','Style · Store immutable version + activate profile','Style · Fingerprint update receipt','Seed · continue only after all profiles stored']],
   [0,2400,['Seed · Replay mixed inbox events','Seed · Classify + deduplicate test inbox · set operation','Seed · Classify + deduplicate test inbox','Seed · Demo ready — next open Slack Concierge']]
  ],
  CommsBackend2026:[
   [0,0,['Internal · operation request','Internal · validate operation','Internal · route capture','Internal · route outbox','Internal · reject unknown operation']],
   [0,520,['Capture · Manual test','Capture · Example forwarded customer email','Capture · Normalize · exclude internal · detect sent','Capture · Persist idempotent inbox + style candidate','Capture · Capture receipt — no heavy generation']],
   [0,1150,['Outbox · Manual test','Outbox · Every minute recovery — DISABLED until deployment','Outbox · Tenant-scoped review configuration','Outbox · Read held notifications and explicit actions','Outbox · Expand review items','Outbox · Pending draft/action exists?','Outbox · Fetch draft and complete artifact metadata','Outbox · Stored document exists?']],
   [1400,1500,['Outbox · Build Slack review blocks + copyable text']],
   [1400,1840,['Outbox · Retrieve exact persisted artifact','Outbox · Reattach verified document bytes']],
   [0,2400,['Recovery · queued jobs every minute — DISABLED','Recovery · wake main worker','Recovery · independent main execution']],
   [0,2950,['Capture · Slack source adapter — DISCONNECTED','Capture · Forwarded email adapter — DISCONNECTED','Capture · LinkedIn approved export adapter — DISCONNECTED','Outbox · Post review to Slack — DISCONNECTED','Outbox · Send approved email — DISCONNECTED','Outbox · Save approved file to folder — DISCONNECTED','Outbox · LinkedIn post / DM export — DISCONNECTED']]
  ],
  CommsMain2026:[
   [0,0,['Internal · operation request','Internal · validate operation','Internal · route chat','Internal · route work','Internal · reject unknown operation']],
   [0,520,['Chat · Manual test','Chat · Edit this demo Slack request','Chat · Authenticated Slack command envelope','Chat · Load trusted tenant policy','Chat · Authenticate operator + parse explicit command','Chat · Draft or report requested?','Chat · Queue request exactly once']],
   [1200,870,['Chat · Explicit save or send?','Chat · Validate exact revision + stage action','Chat · Fingerprint command?','Chat · Review / update style fingerprint · set operation','Chat · Review / update style fingerprint','Chat · Show command help']],
   [0,1350,['Work · Claim durable job + lease','Work · A job is available?','Work · Retrieve current public facts + style','Work · Load worker policy','Work · Prepare draft context','Work · Live models enabled?','Work · Reserve bounded job budget — 3 cents maximum','Work · Budget permits this execution?']],
   [2200,1700,['Work · Generation call context','Work · OpenRouter — economical structured draft','Work · Parse draft and preserve evidence','Work · Deterministic citation / number / language gate','Work · Live draft passes deterministic gate?','Work · Joey veto + Mammoth evidence/style check']],
   [2200,2050,['Work · DRY RUN — evidence-only fixture draft']],
   [0,2550,['Verify · One bounded candidate with approved sources','Verify · Compile Joey typed veto','Verify · OpenRouter Decisions — Joey','Verify · Validate Joey answer — never approval','Verify · Joey has not vetoed?','Verify · Compile Mammoth fact + voice rubric','Verify · OpenRouter Decisions — Mammoth','Verify · Strict answer validation + thresholds']],
   [1500,2900,['Verify · Veto — route to bounded rewrite or review','Verify · Evaluator error — fail closed','Verify · Mammoth error — keep current attempt and spend']],
   [0,3500,['Work · One bounded rewrite needed?','Work · Surgical rewrite — once only','Work · OpenRouter — single corrective rewrite','Work · Parse corrective draft']],
   [0,3900,['Work · Candidate has a model reservation?','Work · Keep budget conservative when cost is uncertain','Work · Restore final reviewed candidate','Work · Create a report or PowerPoint file?','Work · Compile document request','Work · Compile PDF / PPTX — internal service','Work · Attach document + keep audit metadata']],
   [0,4300,['Work · Persistable final artifact + evidence audit','Work · Transaction — draft + review outbox + completed job','Work · Load immutable draft for review','Work · Slack review card — copy / save / explicit send','Chat · Return local Slack response preview']],
   [0,4850,['Work · No queued work — zero tokens','Work · Capture failure for durable retry','Work · Backoff / retry / dead letter']],
   [0,5300,['Chat · Slack bot command trigger — DISCONNECTED']]
  ]
 };
 const sections={
  CommsVoiceKB2026:[['Guide · fingerprints','FINGERPRINTS · APPROVE → MEASURE → STORE','Approved external sent examples only. Profiles are versioned; incoming or internal messages never train them. Embeddings remain deferred.',[0,970],3500,1200,4],['Guide · bootstrap','SYNTHETIC DEMO · MANUAL SETUP','Use this lane only to seed the fictional company. The five profiles complete before inbox fixtures are replayed.',[0,340],3200,450,5]],
  CommsBackend2026:[['Guide · capture','INBOX · COLLECT → CLASSIFY → STORE','Trusted sources feed this lane. Internal chatter is excluded and provider events are deduplicated.',[0,340],3000,450,4],['Guide · outbox','OUTBOX · PREPARE REVIEW & FILES','Held records and exact document bytes are reconstructed here. External delivery and schedules are disconnected.',[0,970],4800,1200,5]],
  CommsMain2026:[['Guide · chat','1 · REQUEST & ROUTE','Slack requests are authenticated and routed to draft, fingerprint, save or send approval.',[0,340],4300,730,4],['Guide · drafting','2 · RETRIEVE & DRAFT','Claim the correct job, load public facts and the style profile, reserve budget, and create a draft or dry-run fixture.',[0,1170],4900,1100,5],['Guide · decisions','3 · VERIFY & RECOVER','Deterministic screen → Joey veto → Mammoth fact/voice check. Errors fail closed; one bounded rewrite is allowed.',[0,2370],4900,1050,3]]
 };
 for(const w of flows){
  const positions=new Map(w.nodes.map(n=>[n.name,n.position.slice()]));const nodes=new Map(w.nodes.map(n=>[n.name,n]));
  for(const [x,y,names] of tables[w.id])names.forEach((name,i)=>{if(!nodes.has(name))throw Error('Unknown node '+name);nodes.get(name).position=[x+i*320,y];});
  const constraints=[];for(const c of Object.values(w.connections)){const targets=[...new Set(c.main.flat().map(e=>e.node))];targets.sort((a,b)=>{const A=positions.get(a),B=positions.get(b);return A[1]-B[1]||A[0]-B[0];});for(let i=1;i<targets.length;i++)constraints.push([targets[i-1],targets[i]]);}
  // n8n executes sibling branches by canvas order. Encode the old order as strict vertical precedence.
  const oldSort=(a,b)=>{const A=positions.get(a),B=positions.get(b);return A[1]-B[1]||A[0]-B[0];};
  constraints.sort((a,b)=>oldSort(a[0],b[0]));
  for(const [a,b] of constraints){const A=nodes.get(a),B=nodes.get(b);if(B.position[1]<=A.position[1])B.position[1]=A.position[1]+140;}
  // Prevent nodes assigned to the same grid cell from overlapping without altering their branch order.
  const seen=[];for(const n of w.nodes.filter(n=>n.type!=='n8n-nodes-base.stickyNote').sort((a,b)=>oldSort(a.name,b.name))){let [x,y]=n.position;while(seen.some(([xx,yy])=>Math.abs(xx-x)<220&&Math.abs(yy-y)<115))x+=320;n.position=[x,y];seen.push(n.position);}
  for(const [a,b] of constraints){const A=nodes.get(a).position,B=nodes.get(b).position;if(!(A[1]<B[1]||(A[1]===B[1]&&A[0]<B[0])))throw Error('Branch order changed: '+a+' / '+b);}
  for(const [name,title,desc,pos,width,height,color] of sections[w.id]){const n=nodes.get(name);n.position=pos;n.parameters={content:'# '+title+'\n'+desc,width,height,color};}
  const overview={id:'visual_overview_'+w.id,name:'Visual overview · '+w.id,type:'n8n-nodes-base.stickyNote',typeVersion:1,position:[0,-310],parameters:{content:w.id==='CommsMain2026'?'# MAIN PATH\n**Request → Retrieve → Draft → Verify → Review**\nFollow the numbered lanes. Error, retry and disconnected nodes are grouped separately.':w.id==='CommsVoiceKB2026'?'# MAIN PATH\n**Select examples → Approve → Measure → Save fingerprint**\nThe synthetic demo is a separate setup lane.':'# MAIN PATH\n**Collect → Classify → Store**   |   **Review outbox → Retrieve files**\nDisabled integrations and recovery schedules are grouped below.',width:2800,height:180,color:6}};
  w.nodes.push(overview);
  const laneLabels={
   CommsVoiceKB2026:[['DEMO REPLAY','Seed · Replay mixed inbox events']],
   CommsBackend2026:[['JOB RECOVERY · DISABLED','Recovery · queued jobs every minute — DISABLED'],['FUTURE CONNECTIONS · DISCONNECTED','Capture · Slack source adapter — DISCONNECTED']],
   CommsMain2026:[['4 · REWRITE','Work · One bounded rewrite needed?'],['5 · PACKAGE','Work · Candidate has a model reservation?'],['6 · REVIEW & SAVE','Work · Persistable final artifact + evidence audit'],['IDLE / RETRY','Work · No queued work — zero tokens'],['SLACK TRIGGER · DISCONNECTED','Chat · Slack bot command trigger — DISCONNECTED']]
  };
  laneLabels[w.id].forEach(([label,anchor],i)=>w.nodes.push({id:'visual_lane_'+w.id+'_'+i,name:'Visual lane · '+label,type:'n8n-nodes-base.stickyNote',typeVersion:1,position:[-530,nodes.get(anchor).position[1]-50],parameters:{content:'## '+label,width:420,height:140,color:6}}));
  console.log(JSON.stringify({workflow:w.id,branch_order_constraints:constraints.length,nodes:w.nodes.length}));
 }
};
