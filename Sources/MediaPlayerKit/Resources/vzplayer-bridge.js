// MediaPlayerKit reusable WebView bridge. No DOM or Demo dependencies.
(function () {
"use strict";
// Standard SDK requests return a Promise. Demo scheduling commands retain sendCmd.
if (window.vzPlayerBridge?.request?.mediaPlayerKitBridge) return;
window.vzPlayerBridge = window.vzPlayerBridge || {};
let androidSendEvent = null;
window.vzPlayerBridge.configure = function (options = {}) {
    if (options.androidSendEvent != null && typeof options.androidSendEvent !== 'function') {
        throw new TypeError('androidSendEvent must be a function');
    }
    androidSendEvent = options.androidSendEvent || null;
};
const bridgePending = new Map();
let bridgeSequence = 0;
window.vzPlayerBridge.onResponse = function (response) {
    if (!response || typeof response.requestId !== 'string') return;
    const pending = bridgePending.get(response.requestId);
    if (!pending) return;
    bridgePending.delete(response.requestId);
    clearTimeout(pending.timer);
    if (response.ok) pending.resolve(response.result);
    else pending.reject(new Error(response.error || 'bridge_error'));
};
window.vzPlayerBridge.request = function (method, params = {}) {
    return new Promise((resolve, reject) => {
        let paramsJson;
        try { paramsJson = typeof params === 'string' ? params : JSON.stringify(params); }
        catch (error) { reject(error); return; }
        const native = window.AndroidBridge || window.vzPlayerNative;
        if (native && (method === 'SendEvent' || method === 'sendEvent')) {
            try {
                const event = JSON.parse(paramsJson);
                if (!event || !['NEXT_SOURCE', 'SWITCH_PLAYER'].includes(event.eventName)) {
                    throw new Error('unsupported_event');
                }
                const params = event.params === undefined ? {} : event.params;
                if (!params || typeof params !== 'object' || Array.isArray(params)) throw new Error('invalid_parameters');
                if (!androidSendEvent) throw new Error('android_event_adapter_required');
                Promise.resolve(androidSendEvent(event.eventName, JSON.stringify(params))).then(value => {
                    if (value === false || value === 'false') reject(new Error('invalid_parameters_or_rejected'));
                    else resolve(value === undefined ? null : value);
                }, reject);
            } catch (error) { reject(error); }
            return;
        }
        const aliases = {Play:'play', Pause:'pause', Resume:'resume', Destroy:'destroy', getCurrentTime:'get_currentTime', setCurrentTime:'set_currentTime',
            getDuration:'get_duration', getPause:'get_pause', getVolume:'get_volume', setVolume:'set_volume',
            getMuted:'get_muted', setMuted:'set_muted', getLoop:'get_loop', setLoop:'set_loop',
            getSpeed:'get_speed', setSpeed:'set_speed', getVideoWidth:'get_videoWidth',
            getVideoHeight:'get_videoHeight', getBuffered:'get_buffered', getCurrentSource:'get_currentsource'};
        if (native) {
            try {
                const name = typeof native[method] === 'function' ? method : aliases[method];
                if (!name || typeof native[name] !== 'function') throw new Error('unsupported_method');
                const raw = native[name](paramsJson);
                const value = typeof raw === 'string' ? JSON.parse(raw) : raw;
                if (value === false) throw new Error('invalid_parameters_or_rejected');
                resolve(value === undefined ? null : value);
            } catch (error) { reject(error); }
            return;
        }
        const handler = window.webkit?.messageHandlers?.vzPlayerBridge;
        if (!handler) { reject(new Error('bridge_unavailable')); return; }
        const requestId = `request-${++bridgeSequence}`;
        const timer = setTimeout(() => {
            bridgePending.delete(requestId);
            reject(new Error('bridge_timeout'));
        }, 10000);
        bridgePending.set(requestId, {resolve, reject, timer});
        try { handler.postMessage({method, paramsJson, requestId}); }
        catch (error) {
            clearTimeout(timer); bridgePending.delete(requestId); reject(error);
        }
    });
};
window.addEventListener('pagehide', () => {
    for (const pending of bridgePending.values()) {
        clearTimeout(pending.timer); pending.reject(new Error('page_closed'));
    }
    bridgePending.clear();
});


window.vzPlayerBridge.request.mediaPlayerKitBridge = true;
})();
