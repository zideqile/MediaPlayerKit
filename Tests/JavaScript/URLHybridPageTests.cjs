const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.join(__dirname, '../../Examples/MediaPlayerKitDemo/Resources/URLHybridPlayer/url-player.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements = new Map();
function element(id) {
    if (!elements.has(id)) elements.set(id, {value:'', textContent:'', checked:false, disabled:false,
        addEventListener(name, fn) { this[name] = fn; }, blur() {}});
    return elements.get(id);
}
const calls = [];
let failure;
const bridge = {request: async (method, params) => {
    calls.push({method, params});
    if (failure) throw new Error(failure);
    return {};
}};
vm.runInNewContext(script, {window:{vzPlayerBridge:bridge}, document:{getElementById:element}, Date});
(async () => {
    element('url').value = '  https://example.com/live.m3u8  ';
    element('type').value = 'hls'; element('live').checked = true;
    await element('form').submit({preventDefault(){}});
    assert.equal(calls[0].method, 'loadURL');
    assert.equal(calls[0].params.url, 'https://example.com/live.m3u8');
    assert.equal(calls[0].params.isLive, true);
    assert.equal(element('submit').disabled, false);
    bridge.onEvent('playing'); assert.equal(element('status').textContent, '播放中');
    bridge.onTimeUpdate(12); assert.match(element('time').textContent, /12/);
    await element('mute').onclick(); assert.equal(calls.at(-1).params.muted, true);
    failure = 'invalid address';
    await element('form').submit({preventDefault(){}});
    assert.equal(element('error').textContent, 'invalid address');
    assert.equal(element('submit').disabled, false);
    bridge.onEvent('PlayerWARN'); assert.match(element('status').textContent, /播放失败/);
    for (let i=0;i<100;i++) bridge.onEvent('waiting');
    assert.equal(element('logs').textContent.split('\n').length, 40);
    console.log('URL hybrid page tests passed: URL payload, controls, events, rejection and bounded logs.');
})().catch(error => {console.error(error);process.exitCode=1;});
