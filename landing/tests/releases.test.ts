import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countDownloads, fetchDownloads, createDownloadCache, type Release, type ReleaseAsset } from '../lib/releases';

const repo = 'owner/pot';
const asset = (id:number,name='Pot-0.1.0-macOS-arm64.dmg',count=5):ReleaseAsset => ({ id, name, download_count:count, browser_download_url:`https://github.com/${repo}/releases/download/v0.1.0/${name}` });
const release = (id:number, assets:ReleaseAsset[], overrides:Partial<Release>={}):Release => ({id, assets, draft:false, prerelease:false, published_at:'2026-11-01T00:00:00Z', ...overrides});

test('counts only actual stable Pot installers, once per asset ID',()=>{
  const actual = countDownloads([
    release(1,[asset(1), asset(2,'Pot-0.1.0-macOS-x86_64.dmg',8),asset(3,'Pot.zip',100),asset(4,'Pot.dmg.sig',100),asset(5,'Other.dmg',100)]),
    release(2,[asset(1)]),release(3,[asset(6)],{draft:true}),release(4,[asset(7)],{prerelease:true}),release(5,[asset(8)],{published_at:null}),
  ],repo,new Date('2026-11-25T12:00:00Z'));
  assert.equal(actual?.total,13); assert.deepEqual(actual?.assetIDs,[1,2]); assert.equal(actual?.ruleVersion,1);
});
test('missing releases and malformed downloads never produce invented zero',()=>{
  assert.equal(countDownloads([],repo),null);
  assert.equal(countDownloads([release(1,[asset(1,'Pot.dmg',-1)])],repo),null);
  assert.equal(countDownloads([release(1,[{...asset(1),browser_download_url:'https://untrusted.test/Pot.dmg'}])],repo),null);
  assert.equal(countDownloads([release(1,[asset(1,'Pot.dmg',0)])],repo)?.total,0);
});
test('fetches every page before reporting historical total',async()=>{
  const calls:string[]=[];
  const snapshot = await fetchDownloads(repo,async(url)=>{calls.push(url);return {ok:true,status:200,json:async()=>url.endsWith('page=1')?Array.from({length:100},(_,i)=>release(i,[asset(i)])):[release(101,[asset(101)])]};});
  assert.equal(calls.length,2); assert.equal(snapshot?.total,505);
});
test('rate limiting and partial pagination reject instead of returning a partial count',async()=>{
  let call=0;
  await assert.rejects(fetchDownloads(repo,async()=>++call===1?{ok:true,status:200,json:async()=>Array.from({length:100},(_,i)=>release(i,[asset(i)]))}:{ok:false,status:403,json:async()=>({})}));
});
test('404 means no public installer and invalid repositories never reach fetch',async()=>{
  assert.equal(await fetchDownloads(repo,async()=>({ok:false,status:404,json:async()=>({})})),null);
  await assert.rejects(fetchDownloads('../private',async()=>{throw Error('must not fetch')}));
});
test('cache preserves only a verified snapshot on error and backs off retries',async()=>{
  const cache=createDownloadCache(100,50);let calls=0;
  const first=await cache(async()=>{calls++;return countDownloads([release(1,[asset(1)])],repo)},1000);
  assert.equal(first?.total,5);
  await cache(async()=>{throw Error('not due')},1050);
  const stale=await cache(async()=>{calls++;throw Error('rate limited')},1101);
  assert.equal(stale?.total,5);assert.equal(stale?.stale,true);assert.equal(calls,2);
  await cache(async()=>{calls++;throw Error('not yet')},1120);assert.equal(calls,2);
  const emptyCache=createDownloadCache();assert.equal(await emptyCache(async()=>{throw Error('offline')}),null);
});
test('cache coalesces simultaneous requests',async()=>{
  const cache=createDownloadCache();let calls=0;
  const loader=async()=>{calls++;await Promise.resolve();return countDownloads([release(1,[asset(1)])],repo)};
  const [a,b]=await Promise.all([cache(loader),cache(loader)]);assert.equal(calls,1);assert.deepEqual(a,b);
});
