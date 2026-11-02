'use strict';
module.exports = function reduceNodes(flows) {
 const byId = new Map(flows.map(w => [w.id, w]));
 const removals = {
  CommsVoiceKB2026: ['Seed · Compile each style fingerprint','Style · Explicit fingerprint request'],
  CommsBackend2026: ['Capture · Normalized event from trusted adapter','Outbox · Recovery / review request'],
  CommsMain2026: ['Chat · Run on-demand drafting worker','Work · Queued request wakeup']
 };
 function bypass(w, name, expectedType) {
  const n = w.nodes.find(x => x.name === name);
  if (!n || n.type !== 'n8n-nodes-base.' + expectedType) throw Error('Unexpected bypass node: ' + name);
  if (w.nodes.some(x => x !== n && JSON.stringify(x.parameters).includes(name))) throw Error('Referenced node cannot be bypassed: '+name);
  const branches = w.connections[name]?.main;
  if (!branches || branches.length !== 1 || branches[0].length !== 1 || branches[0][0].index !== 0) throw Error('Unexpected outgoing branches: '+name);
  const target = branches[0][0].node;
  for (const c of Object.values(w.connections)) for (const branch of c.main) for (const e of branch) if (e.node === name) e.node = target;
  w.nodes = w.nodes.filter(x => x !== n); delete w.connections[name];
 }
 for (const [id,names] of Object.entries(removals)) for (const name of names) bypass(byId.get(id),name,'noOp');
 const backend = byId.get('CommsBackend2026');
 const card=backend.nodes.find(n=>n.name==='Outbox · Build Slack review blocks + copyable text');
 const old='...reviewCard(i.json.data),draft:i.json.data';
 const replacement="...reviewCard(i.json.data),draft:i.json.data,status:'held',delivered:false,reason:'Connect and verify Slack/folder/send adapters before enabling dispatch'";
 if (!card.parameters.jsCode.includes(old)) throw Error('Unexpected outbox card code');
 card.parameters.jsCode=card.parameters.jsCode.replace(old,replacement);
 const held='Outbox · HELD — no external adapter connected';
 const heldNode=backend.nodes.find(n=>n.name===held);
 if (!heldNode || heldNode.type!=='n8n-nodes-base.code' || backend.connections[held]) throw Error('Unexpected held terminal');
 const cardEdges=backend.connections[card.name]?.main;
 if (!cardEdges || cardEdges.length!==1 || cardEdges[0].length!==1 || cardEdges[0][0].node!==held) throw Error('Unexpected card continuation');
 if (backend.nodes.some(n=>n!==heldNode && JSON.stringify(n.parameters).includes(held))) throw Error('Held node is referenced');
 delete backend.connections[card.name];
 backend.nodes=backend.nodes.filter(n=>n!==heldNode);
};
