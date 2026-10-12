const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');

const base = 'https://elghliaraqi-ops.github.io/GardeFlow/';
const edge = 'https://bqmtkdzlqfvfocxlffac.supabase.co/functions/v1/generate-practice-daily-challenge';
const dir = 'smoke-evidence';
fs.mkdirSync(dir, { recursive: true });
const results = [];

async function check(label, fn) {
  const start = Date.now();
  try {
    const details = await fn();
    results.push({ label, result: 'PASS', ms: Date.now()-start, ...details });
    console.log('PASS', label, JSON.stringify(details));
  } catch (error) {
    results.push({ label, result: 'FAIL', ms: Date.now()-start, reason: String(error).slice(0,600) });
    console.error('FAIL', label, String(error));
  }
}

(async () => {
  await check('Live GitHub Pages responds HTML', async () => {
    const r = await fetch(base, {signal:AbortSignal.timeout(20000)});
    const html = await r.text();
    assert.equal(r.status,200,'Main page must be public HTTP 200');
    assert.match(html, /flutter_bootstrap\.js/);
    assert.match(html, /base href="\/GardeFlow\/"/);
    return {status:r.status,htmlBytes:html.length,base};
  });

  let buildId;
  await check('Real published build id', async () => {
    const r = await fetch(base+'build-id.txt',{signal:AbortSignal.timeout(20000)});
    assert.equal(r.status,200);
    buildId = (await r.text()).trim();
    assert.match(buildId,/^[a-f0-9]{12}$/);
    return {buildId};
  });

  await check('Live Flutter JavaScript assets', async () => {
    const names=['flutter_bootstrap.js','main.dart.js'];
    const data=[];
    for(const name of names) {
      const r = await fetch(base+name+'?build='+buildId,{method:'HEAD',signal:AbortSignal.timeout(20000)});
      assert.equal(r.status,200,name+' should be reachable');
      data.push({name,status:r.status,contentType:r.headers.get('content-type'),size:r.headers.get('content-length')});
    }
    return {assets:data};
  });

  await check('Unauthenticated AI endpoint rejects calls without Groq generation', async () => {
    const r = await fetch(edge,{method:'POST',headers:{'Content-Type':'application/json'},body:'{"mode":"cours_ia"}',signal:AbortSignal.timeout(15000)});
    const t=(await r.text()).slice(0,250);
    assert.ok(r.status===401||r.status===403,'Endpoint must refuse anonymous POST: HTTP '+r.status);
    return {status:r.status,response:t};
  });

  await check('Headless Chromium renders published Flutter app', async () => {
    const browser=await chromium.launch({headless:true,channel:'chrome',args:['--no-sandbox']});
    const errors=[],consoleErrors=[],failedRequests=[],badResponses=[];
    try {
      const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1,locale:'fr-FR'});
      page.on('pageerror',e=>errors.push(String(e).slice(0,350)));
      page.on('console',msg=>{if(msg.type()==='error'||msg.type()==='warning')consoleErrors.push(msg.text().slice(0,240))});
      page.on('requestfailed',req=>failedRequests.push({url:req.url().slice(0,170),failure:req.failure()?.errorText}));
      page.on('response',res=>{if(res.status()>=400)badResponses.push({url:res.url().slice(0,160),status:res.status()})});
      const nav=await page.goto(base,{waitUntil:'domcontentloaded',timeout:45000});
      assert.ok(nav && nav.status()===200,'Browser main navigation failed');
      let mounted=true,why='';
      try{
        await page.waitForSelector('flutter-view, flt-glass-pane',{state:'attached',timeout:30000});
      }catch(e){mounted=false;why=String(e).slice(0,260)}
      await page.waitForTimeout(2000);
      const details=await page.evaluate(()=>({
        title:document.title,language:navigator.language,languages:navigator.languages,flutterView:document.querySelectorAll('flutter-view').length,
        glassPane:document.querySelectorAll('flt-glass-pane').length,
        canvas:document.querySelectorAll('canvas').length,
        loaderVisible:!!document.querySelector('#gardeflow-loader'),
        bodyText:document.body?.innerText?.slice(0,250)||'',
        bodyHtml:document.body?.innerHTML?.slice(0,400)||''
      }));
      await page.screenshot({path:dir+'/mobile-login.png',fullPage:true});
      console.log('BROWSER_DIAGNOSTICS',JSON.stringify({mounted,why,details,errors,consoleErrors,failedRequests,badResponses}));
      assert.ok(mounted,'Flutter not mounted; '+JSON.stringify({details,errors,consoleErrors,failedRequests,badResponses}).slice(0,1000));
      assert.equal(errors.length,0,'Uncaught JS exceptions: '+errors.join(' | '));
      return { ...details, browserErrors:errors.length,consoleErrors,failedRequests,badResponses,screenshot:'mobile-login.png' };
    } finally { await browser.close(); }
  });

})().catch(e=>{ results.push({label:'runner',result:'FAIL',reason:String(e)}); console.error(e); }).finally(()=>{
  fs.writeFileSync(dir+'/results.json',JSON.stringify(results,null,2));
  console.log('LIVE_SMOKE_RESULTS',JSON.stringify(results));
  if(results.some(r=>r.result==='FAIL'))process.exitCode=1;
});
