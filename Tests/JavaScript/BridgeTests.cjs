const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = readFileSync(require('node:path').join(__dirname, '../../Examples/MediaPlayerKitDemo/Resources/HybridPlayer/player.js'), 'utf8');
const code = source.slice(source.indexOf('const bridgePending'), source.indexOf('function sendCmd'));
function setup(native) {
    const messages = [], timers = new Map(), events = {};
    let sequence = 0;
    const window = {vzPlayerBridge: {}, addEventListener: (name, fn) => events[name] = fn};
    if (native) window.AndroidBridge = native;
    else window.webkit = {messageHandlers: {vzPlayerBridge: {postMessage: msg => messages.push(msg)}}};
    vm.runInNewContext(code, {window, setTimeout: fn => { timers.set(++sequence, fn); return sequence; }, clearTimeout: id => timers.delete(id)});
    return {bridge: window.vzPlayerBridge, messages, timers, events};
}
(async () => {
    const ios = setup();
    const first = ios.bridge.request('getVolume');
    const second = ios.bridge.request('setVolume', {volume: 2});
    ios.bridge.onResponse({requestId: ios.messages[1].requestId, ok: false, error: 'invalid_parameters_or_rejected'});
    await assert.rejects(second, /invalid_parameters/);
    ios.bridge.onResponse({requestId: ios.messages[0].requestId, ok: true, result: {volume: 0.5}});
    assert.equal((await first).volume, 0.5);
    assert.equal(ios.timers.size, 0);
    const timeout = ios.bridge.request('getVolume');
    [...ios.timers.values()][0]();
    await assert.rejects(timeout, /bridge_timeout/);
    const closed = ios.bridge.request('getVolume');
    ios.events.pagehide();
    await assert.rejects(closed, /page_closed/);
    const android = setup({get_volume: () => '{"volume":0.8}', set_volume: () => false});
    assert.equal((await android.bridge.request('getVolume')).volume, 0.8);
    await assert.rejects(android.bridge.request('setVolume', {volume: 2}), /invalid_parameters/);
    await assert.rejects(android.bridge.request('missing'), /unsupported_method/);
    console.log('Bridge tests passed: reply correlation, failure, timeout, page cleanup, Android aliases/results.');
})().catch(error => { console.error(error); process.exitCode = 1; });
