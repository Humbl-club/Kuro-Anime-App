'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');const W=require('./backend_workload');
const actor={id:'a',email:'kuro-load-test-a@example.invalid',token:'fixture',librarySize:25,writeEntry:{mediaId:1,lifecycleId:'life',revision:7,position:2}};
const fixture={origin:W.ORIGIN,runId:'kuro-load-test',accounts:[actor],media:{anime:[1],manga:[2]}};
const config={production:true,rps:2,duration:60,vus:1,maxRequests:120};
test('exact origin, explicit mode and bounded limits reject unsafe runs',()=>{
 assert.doesNotThrow(()=>W.validateConfig(config,fixture));
 for(const c of [{production:false},{rps:51},{duration:601},{vus:101},{maxRequests:20001},{rps:NaN}])assert.throws(()=>W.validateConfig({...config,...c},fixture));
 assert.throws(()=>W.validateConfig(config,{...fixture,origin:W.ORIGIN+'.evil.invalid'}));
 assert.throws(()=>W.validateConfig(config,{...fixture,accounts:[actor,actor]}));
 assert.throws(()=>W.validateConfig(config,{...fixture,accounts:[{...actor,email:'customer@example.invalid'}]}));
});
test('nearest rank percentiles preserve tail values',()=>{assert.equal(W.percentile([1,2,3,100],.95),100);assert.equal(W.percentile([], .95),null);});
test('errors, lost arrivals and slow successful replies cannot pass',()=>{
 const s=[{kind:'browse',ms:100,status:200,ok:true}];assert.equal(W.summarize(s,1,1).pass,true);
 assert.equal(W.summarize(s,2,1).pass,false);
 assert.equal(W.summarize([{kind:'browse',ms:1,status:503,ok:false}],1,1).pass,false);
 assert.equal(W.summarize([{kind:'browse',ms:751,status:200,ok:true}],1,1).pass,false);
});
test('workload represents bounded real RPCs; paid narration stays off',()=>{
 for(const kind of Object.keys(W.WEIGHTS)){const r=W.requestFor(kind,actor,fixture,1,()=>.1);assert.match(r.path,/^\/(rest|functions)\/v1\//);assert.doesNotMatch(r.path,/bulk-import|release-intake|apply_remove/);}
 assert.equal(W.requestFor('recommend',actor,fixture,1).body.narrate,false);
 assert.equal(Object.values(W.WEIGHTS).reduce((a,b)=>a+b),100);
});
test('HTTP200 empty failures do not masquerade as working personalized pages',()=>{
 const home=W.requestFor('home',actor,fixture,1);assert.equal(W.validateResponse('home',{active:[],home_revision:1},actor,home),false);
 assert.equal(W.validateResponse('home',{active:[{}],home_revision:1,club:{state:'error'}},actor,home),false);
 assert.equal(W.validateResponse('home',{active:[{}],home_revision:1,club:{state:'none'}},actor,home),true);
 assert.equal(W.validateResponse('browse',[],actor,{}),false);
 assert.equal(W.validateResponse('detail',{header:null},actor,{}),false);
});
test('tracking must be applied with matching receipt; conflicts do not count as success',()=>{
 const a=structuredClone(actor),r=W.requestFor('progress',a,fixture,1);
 assert.equal(W.validateResponse('progress',{items:[{mutation_id:r.mutationId,outcome:'conflict',server_revision:8}]},a,r),false);
 assert.equal(W.validateResponse('progress',{items:[{mutation_id:r.mutationId,outcome:'applied',server_revision:8}]},a,r),true);
 assert.equal(a.writeEntry.revision,8);assert.equal(a.writeEntry.position,3);
});
test('parser response belongs to the caller; deterministic recommendations contain content',()=>{
 assert.equal(W.validateResponse('parse',{success:true,userId:'outsider',items:[{}]},actor,{}),false);
 assert.equal(W.validateResponse('recommend',{success:true,narrated:true,items:[{}]},actor,{}),false);
 assert.equal(W.validateResponse('recommend',{success:true,narrated:false,items:[{}]},actor,{}),true);
});
