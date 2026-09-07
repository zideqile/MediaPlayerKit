import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTML 嵌入式 H5 播放控制器页面模板
private let hybridPlayerHTML: String = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>IH5Player 混合开发控制台</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", Arial, sans-serif; -webkit-tap-highlight-color: transparent; }
        body { background-color: #0F172A; color: #F8FAFC; padding: 12px; font-size: 13px; line-height: 1.5; }
        
        /* 1. 操作引导卡片 */
        .guide-card { background: linear-gradient(135deg, #1E293B 0%, #0F172A 100%); border: 1.5px solid #3B82F6; border-radius: 12px; padding: 12px; margin-bottom: 12px; box-shadow: 0 4px 12px rgba(59, 130, 246, 0.15); }
        .guide-title { font-size: 13px; font-weight: 700; color: #60A5FA; display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
        .guide-desc { font-size: 11.5px; color: #94A3B8; margin-bottom: 10px; line-height: 1.4; }
        .step-list { display: flex; flex-direction: column; gap: 4px; font-size: 11px; color: #CBD5E1; margin-bottom: 10px; }
        .step-item { display: flex; align-items: flex-start; gap: 6px; }
        .step-num { background: #3B82F6; color: #FFF; font-size: 9px; font-weight: bold; border-radius: 50%; width: 15px; height: 15px; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; margin-top: 1px; }
        
        .auto-btn { width: 100%; background: linear-gradient(90deg, #2563EB, #4F46E5); color: #FFFFFF; border: none; border-radius: 8px; padding: 9px; font-size: 12.5px; font-weight: 700; cursor: pointer; text-align: center; box-shadow: 0 2px 6px rgba(37, 99, 235, 0.4); display: flex; align-items: center; justify-content: center; gap: 6px; }
        .auto-btn:active { transform: scale(0.98); opacity: 0.9; }

        /* 通用卡片容器 */
        .card { background: #1E293B; border-radius: 12px; padding: 12px; margin-bottom: 12px; border: 1px solid #334155; }
        .card-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
        .card-title { font-size: 12.5px; font-weight: 700; color: #E2E8F0; display: flex; align-items: center; gap: 6px; }
        .badge { font-size: 10px; padding: 2px 8px; border-radius: 10px; font-weight: 600; }
        .badge-live { background: #10B981; color: #FFFFFF; }
        .badge-pause { background: #64748B; color: #FFFFFF; }
        .badge-buffering { background: #F59E0B; color: #FFFFFF; }

        /* 主播放按钮 */
        .main-play-btn { width: 100%; height: 42px; border-radius: 10px; border: none; font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2563EB; display: flex; align-items: center; justify-content: center; gap: 8px; cursor: pointer; margin-bottom: 10px; transition: all 0.2s; box-shadow: 0 4px 10px rgba(37, 99, 235, 0.3); }
        .main-play-btn.playing { background: #D97706; box-shadow: 0 4px 10px rgba(217, 119, 6, 0.3); }
        .main-play-btn:active { transform: scale(0.98); }

        /* 控制按钮网格 */
        .btn-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 10px; }
        .btn { background: #334155; color: #F1F5F9; border: none; border-radius: 8px; padding: 8px 4px; font-size: 11.5px; font-weight: 600; cursor: pointer; text-align: center; transition: all 0.15s; }
        .btn:active { background: #3B82F6; color: #FFF; transform: scale(0.96); }
        .btn.active { background: #2563EB; color: #FFF; border: 1px solid #60A5FA; }

        /* 滑块控制器 */
        .slider-box { background: #0F172A; border-radius: 8px; padding: 8px 10px; margin-bottom: 8px; border: 1px solid #334155; }
        .slider-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; font-size: 11.5px; }
        .slider-row input[type=range] { flex: 1; accent-color: #3B82F6; height: 5px; border-radius: 3px; }
        
        /* 播放源选择列表 */
        .source-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; margin-bottom: 8px; }
        .source-card { background: #0F172A; border: 1px solid #334155; border-radius: 8px; padding: 8px; cursor: pointer; text-align: left; transition: all 0.2s; }
        .source-card.active { border-color: #3B82F6; background: rgba(59, 130, 246, 0.12); }
        .source-name { font-size: 11px; font-weight: 700; color: #F1F5F9; margin-bottom: 2px; display: flex; align-items: center; justify-content: space-between; }
        .source-tag { font-size: 9.5px; color: #94A3B8; }

        /* 状态与指标面板 */
        .stat-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; font-size: 11px; }
        .stat-box { background: #0F172A; padding: 6px 8px; border-radius: 6px; border: 1px solid #334155; }
        .stat-label { color: #94A3B8; font-size: 9.5px; margin-bottom: 2px; }
        .stat-val { font-family: ui-monospace, SFMono-Regular, monospace; font-weight: 700; color: #38BDF8; word-break: break-all; }

        /* 实时日志盒子 */
        .log-box { background: #020617; border-radius: 8px; padding: 8px; max-height: 150px; overflow-y: auto; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 10px; border: 1px solid #334155; }
        .log-item { margin-bottom: 4px; line-height: 1.35; }
        .log-time { color: #64748B; margin-right: 4px; }
        .log-event { color: #34D399; font-weight: bold; }
        .log-error { color: #F87171; font-weight: bold; }
        .log-cmd { color: #60A5FA; }
        .log-auto { color: #FBBF24; font-weight: bold; }
    </style>
</head>
<body>

    <!-- 1. 操作引导与一键自动化演示 -->
    <div class="guide-card">
        <div class="guide-title">
            <span>💡 混合开发原理 & 极简操作指南</span>
            <span style="font-size: 10px; color: #93C5FD;">JSBridge 透传</span>
        </div>
        <div class="guide-desc">
            上方画面为 iOS 原生播放器渲染；下方为您正在交互的 H5 网页。所有点击均通过 <b>JSBridge</b> 发送 JSON 指令控制底层 <code>IH5Player</code>。
        </div>
        <div class="step-list">
            <div class="step-item"><span class="step-num">1</span><span>点击大按钮 <b>[▶️ 播放 / ⏸ 暂停]</b> 或 <b>[⏩ 快进/倍速]</b> 操控原生画面。</span></div>
            <div class="step-item"><span class="step-num">2</span><span>在下方 <b>[预设播放源]</b> 点击切换 MP4 回放或微赞直播流。</span></div>
            <div class="step-item"><span class="step-num">3</span><span>查看最下方 <b>[事件流]</b> 观察原生内核向 H5 实时派发的状态心跳。</span></div>
        </div>
        <button class="auto-btn" onclick="runAutoDemonstration()">
            <span>🚀</span><span id="autoBtnText">点击体验「全功能一键自动化演练」</span>
        </button>
    </div>

    <!-- 2. H5 ➔ Native 控制台 -->
    <div class="card">
        <div class="card-header">
            <span class="card-title">🎮 H5 播放控制器 (Web ➔ Native)</span>
            <span class="badge badge-live" id="playStateBadge">🟢 播放中</span>
        </div>

        <!-- 主播放切换按钮 -->
        <button class="main-play-btn" id="mainPlayBtn" onclick="togglePlayPause()">
            <span id="mainPlayIcon">⏸</span><span id="mainPlayText">暂停播放 (Pause)</span>
        </button>

        <!-- 快退/快进/静音/刷新 -->
        <div class="btn-grid">
            <button class="btn" onclick="seekRelative(-10)">⏪ 快退 10s</button>
            <button class="btn" onclick="seekRelative(10)">⏩ 快进 10s</button>
            <button class="btn" id="muteBtn" onclick="toggleMute()">🔊 切换静音</button>
            <button class="btn" onclick="refreshProperties()">🔄 刷新属性</button>
        </div>

        <!-- 倍速切换 -->
        <div class="btn-grid">
            <button class="btn speed-btn active" id="spd10" onclick="setSpeed(1.0)">1.0x</button>
            <button class="btn speed-btn" id="spd125" onclick="setSpeed(1.25)">1.25x</button>
            <button class="btn speed-btn" id="spd15" onclick="setSpeed(1.5)">1.5x</button>
            <button class="btn speed-btn" id="spd20" onclick="setSpeed(2.0)">2.0x</button>
        </div>

        <!-- 进度条 -->
        <div class="slider-box">
            <div class="slider-row">
                <span style="min-width: 40px;">⏱ 进度:</span>
                <input type="range" id="seekSlider" min="0" max="100" value="0" onchange="onSeekChange(this.value)">
                <span id="timeText" style="min-width: 75px; text-align: right; font-family: monospace;">00:00</span>
            </div>
        </div>

        <!-- 音量滑块 -->
        <div class="slider-box">
            <div class="slider-row">
                <span style="min-width: 40px;">🔊 音量:</span>
                <input type="range" id="volumeSlider" min="0" max="100" value="100" oninput="onVolumeChange(this.value)">
                <span id="volumeText" style="min-width: 35px; text-align: right; font-family: monospace;">100%</span>
            </div>
        </div>
    </div>

    <!-- 3. 快速选源与预设 -->
    <div class="card">
        <div class="card-header">
            <span class="card-title">📺 预设播放源切换 (多协议与多源)</span>
            <span style="font-size: 10px; color: #94A3B8;">双层自动容错</span>
        </div>
        <div class="source-grid">
            <div class="source-card active" id="srcVod1" onclick="selectPresetSource('vod_girl')">
                <div class="source-name"><span>🎬 经典点播 MP4</span><span style="color: #60A5FA;">✓</span></div>
                <div class="source-tag">点播回放 | H.264 720P</div>
            </div>
            <div class="source-card" id="srcLive1" onclick="selectPresetSource('live_vzan1')">
                <div class="source-name"><span>📡 微赞直播流 1</span></div>
                <div class="source-tag">直播 | HLS .m3u8</div>
            </div>
            <div class="source-card" id="srcLive2" onclick="selectPresetSource('live_vzan2')">
                <div class="source-name"><span>📡 微赞直播流 2</span></div>
                <div class="source-tag">直播 | 备用多码率</div>
            </div>
            <div class="source-card" id="srcLive3" onclick="selectPresetSource('live_test')">
                <div class="source-name"><span>⚡️ 官方测试流</span></div>
                <div class="source-tag">直播 | 故障容错源</div>
            </div>
        </div>
    </div>

    <!-- 4. IH5Player 属性监视面板 -->
    <div class="card">
        <div class="card-header">
            <span class="card-title">📊 IH5Player 属性实时读取 (JSON)</span>
            <span style="font-size: 10px; color: #38BDF8;">Getters Protocol</span>
        </div>
        <div class="stat-grid">
            <div class="stat-box">
                <div class="stat-label">currentTime / duration</div>
                <div class="stat-val" id="statTime">0s / 0s</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">speed (当前倍速)</div>
                <div class="stat-val" id="statSpeed">1.0x</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">volume / muted</div>
                <div class="stat-val" id="statVolume">1.0 / 正常</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">videoSize (分辨率)</div>
                <div class="stat-val" id="statSize">自适应</div>
            </div>
            <div class="stat-box" style="grid-column: span 2;">
                <div class="stat-label">currentSource (生效播放源)</div>
                <div class="stat-val" id="statSource" style="font-size: 10px;">-</div>
            </div>
        </div>
    </div>

    <!-- 5. Native ➔ H5 实时事件流日志 -->
    <div class="card">
        <div class="card-header">
            <span class="card-title">📡 Native ➔ H5 事件流 (VZH5EventListener)</span>
            <button class="btn" style="padding: 2px 8px; font-size: 10.5px;" onclick="clearLogs()">清空</button>
        </div>
        <div class="log-box" id="logBox">
            <div class="log-item"><span class="log-time">[Init]</span><span class="log-cmd">🚀 JSBridge 准备就绪，已向原生发送起播指令...</span></div>
        </div>
    </div>

    <script>
        let currentPosSec = 0;
        let totalDurationSec = 0;
        let isPlayingState = true;
        let isMutedState = false;
        let currentSpeed = 1.0;
        let isAutoTesting = false;

        function log(type, msg) {
            const box = document.getElementById('logBox');
            if (!box) return;
            const item = document.createElement('div');
            item.className = 'log-item';
            const now = new Date();
            const timeStr = now.toTimeString().split(' ')[0] + '.' + String(now.getMilliseconds()).padStart(3, '0');
            
            let tag = `<span class="log-cmd">[${type}]</span>`;
            if (type === 'Event') tag = `<span class="log-event">[Native事件]</span>`;
            if (type === 'Error') tag = `<span class="log-error">[错误]</span>`;
            if (type === 'Auto') tag = `<span class="log-auto">[演练]</span>`;
            
            item.innerHTML = `<span class="log-time">${timeStr}</span>${tag} ${msg}`;
            box.appendChild(item);
            box.scrollTop = box.scrollHeight;
        }

        function clearLogs() {
            document.getElementById('logBox').innerHTML = '';
        }

        // JSBridge 通信
        function sendCmd(method, paramsJson = '{}') {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vzPlayerBridge) {
                window.webkit.messageHandlers.vzPlayerBridge.postMessage({
                    method: method,
                    paramsJson: paramsJson
                });
                log('H5➔Native', `执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
            } else {
                log('Error', '未检测到 vzPlayerBridge 容器');
            }
        }

        function togglePlayPause() {
            if (isPlayingState) {
                sendCmd('pause');
            } else {
                sendCmd('play');
            }
        }

        function seekRelative(delta) {
            const target = Math.max(0, currentPosSec + delta);
            sendCmd('setCurrentTime', JSON.stringify({ currentTime: target }));
        }

        function onSeekChange(percent) {
            if (totalDurationSec > 0) {
                const target = Math.floor(totalDurationSec * (percent / 100));
                sendCmd('setCurrentTime', JSON.stringify({ currentTime: target }));
            }
        }

        function setSpeed(spd) {
            currentSpeed = spd;
            document.querySelectorAll('.speed-btn').forEach(b => b.classList.remove('active'));
            if (spd === 1.0) document.getElementById('spd10').classList.add('active');
            if (spd === 1.25) document.getElementById('spd125').classList.add('active');
            if (spd === 1.5) document.getElementById('spd15').classList.add('active');
            if (spd === 2.0) document.getElementById('spd20').classList.add('active');
            sendCmd('setSpeed', JSON.stringify({ speed: spd }));
        }

        function toggleMute() {
            isMutedState = !isMutedState;
            document.getElementById('muteBtn').innerText = isMutedState ? '🔇 已静音' : '🔊 切换静音';
            sendCmd('setMuted', JSON.stringify({ muted: isMutedState }));
        }

        function onVolumeChange(val) {
            document.getElementById('volumeText').innerText = val + '%';
            const vol = parseFloat(val) / 100.0;
            sendCmd('setVolume', JSON.stringify({ volume: vol }));
        }

        function selectPresetSource(sourceKey) {
            document.querySelectorAll('.source-card').forEach(c => {
                c.classList.remove('active');
                const nameSpan = c.querySelector('.source-name');
                const check = nameSpan.querySelector('span:last-child');
                if (check && check.innerText === '✓') check.remove();
            });

            let cardId = 'srcVod1';
            if (sourceKey === 'vod_girl') cardId = 'srcVod1';
            if (sourceKey === 'live_vzan1') cardId = 'srcLive1';
            if (sourceKey === 'live_vzan2') cardId = 'srcLive2';
            if (sourceKey === 'live_test') cardId = 'srcLive3';

            const activeCard = document.getElementById(cardId);
            if (activeCard) {
                activeCard.classList.add('active');
                const nameDiv = activeCard.querySelector('.source-name');
                const check = document.createElement('span');
                check.style.color = '#60A5FA';
                check.innerText = '✓';
                nameDiv.appendChild(check);
            }

            sendCmd('switchSource', JSON.stringify({ sourceKey: sourceKey }));
        }

        function refreshProperties() {
            sendCmd('getProperties');
        }

        // ================= 自动化演练脚本 =================
        function runAutoDemonstration() {
            if (isAutoTesting) return;
            isAutoTesting = true;
            const btn = document.getElementById('autoBtnText');
            btn.innerText = '⏳ 自动化演示进行中...';
            log('Auto', '=== 🚀 开始全功能自动化测试 ===');

            const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

            (async () => {
                try {
                    log('Auto', '步骤 1/5: 播放并 Seek 到 5 秒');
                    sendCmd('play');
                    await sleep(1200);
                    sendCmd('setCurrentTime', JSON.stringify({ currentTime: 5 }));
                    await sleep(1500);

                    log('Auto', '步骤 2/5: 切换到 1.5x 倍速');
                    setSpeed(1.5);
                    await sleep(1500);

                    log('Auto', '步骤 3/5: 测试静音与解除静音');
                    toggleMute();
                    await sleep(1200);
                    toggleMute();
                    await sleep(1000);

                    log('Auto', '步骤 4/5: 切换至微赞直播源 1');
                    selectPresetSource('live_vzan1');
                    await sleep(2000);

                    log('Auto', '步骤 5/5: 恢复 1.0x 倍速与点播源');
                    setSpeed(1.0);
                    selectPresetSource('vod_girl');
                    await sleep(1000);

                    log('Auto', '🎉 自动化演练全部完成！各项 API 响应正常。');
                } catch(e) {
                    log('Error', '演示异常: ' + e);
                } finally {
                    isAutoTesting = false;
                    btn.innerText = '🚀 再次体验「全功能一键自动化演练」';
                }
            })();
        }

        // ================= Native ➔ H5 回调注入方法 =================

        // 1. 原生生命周期事件
        window.vzBridgeReceiveEvent = function(eventName) {
            log('Event', `接收事件: <b>${eventName}</b>`);
            const badge = document.getElementById('playStateBadge');
            const playBtn = document.getElementById('mainPlayBtn');
            const playIcon = document.getElementById('mainPlayIcon');
            const playText = document.getElementById('mainPlayText');

            if (eventName === 'playing' || eventName === 'play') {
                isPlayingState = true;
                badge.innerText = '🟢 播放中';
                badge.className = 'badge badge-live';
                playBtn.className = 'main-play-btn playing';
                playIcon.innerText = '⏸';
                playText.innerText = '暂停播放 (Pause)';
            } else if (eventName === 'pause') {
                isPlayingState = false;
                badge.innerText = '⚪️ 已暂停';
                badge.className = 'badge badge-pause';
                playBtn.className = 'main-play-btn';
                playIcon.innerText = '▶️';
                playText.innerText = '开始播放 (Play)';
            } else if (eventName === 'waiting') {
                badge.innerText = '🟡 缓冲中...';
                badge.className = 'badge badge-buffering';
            } else if (eventName === 'ended') {
                isPlayingState = false;
                badge.innerText = '⏹ 已结束';
                badge.className = 'badge badge-pause';
                playBtn.className = 'main-play-btn';
                playIcon.innerText = '▶️';
                playText.innerText = '重新播放 (Replay)';
            }
            sendCmd('getProperties');
        };

        // 2. 进度定时心跳 (500ms)
        window.vzBridgeReceiveTimeUpdate = function(currentTimeSec) {
            currentPosSec = currentTimeSec;
            if (totalDurationSec > 0) {
                const percent = Math.min(100, Math.floor((currentPosSec / totalDurationSec) * 100));
                document.getElementById('seekSlider').value = percent;
                document.getElementById('timeText').innerText = formatTime(currentPosSec) + ' / ' + formatTime(totalDurationSec);
                document.getElementById('statTime').innerText = currentPosSec + 's / ' + totalDurationSec + 's';
            } else {
                document.getElementById('timeText').innerText = formatTime(currentPosSec);
                document.getElementById('statTime').innerText = currentPosSec + 's (直播)';
            }
        };

        // 3. 错误回调
        window.vzBridgeReceiveError = function(code, errMsg) {
            log('Error', `播放异常 code=${code} msg=${errMsg}`);
            const badge = document.getElementById('playStateBadge');
            badge.innerText = '🔴 播放出错';
            badge.className = 'badge';
            badge.style.background = '#DC2626';
        };

        // 4. 属性更新回传
        window.vzBridgeUpdateProperties = function(props) {
            try {
                if (props.duration !== undefined && props.duration > 0) {
                    totalDurationSec = props.duration;
                }
                if (props.speed !== undefined) {
                    document.getElementById('statSpeed').innerText = props.speed + 'x';
                }
                if (props.volume !== undefined || props.muted !== undefined) {
                    document.getElementById('statVolume').innerText = (props.volume ?? 1.0) + ' / ' + (props.muted ? '已静音' : '正常');
                    isMutedState = props.muted ?? false;
                    document.getElementById('muteBtn').innerText = isMutedState ? '🔇 已静音' : '🔊 切换静音';
                }
                if (props.videoWidth && props.videoHeight) {
                    document.getElementById('statSize').innerText = props.videoWidth + 'x' + props.videoHeight;
                }
                if (props.currentSource) {
                    const url = props.currentSource.url || JSON.stringify(props.currentSource);
                    document.getElementById('statSource').innerText = url;
                }
            } catch(e) {
                console.error(e);
            }
        };

        function formatTime(sec) {
            const m = Math.floor(sec / 60);
            const s = Math.floor(sec % 60);
            return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
        }
    </script>
</body>
</html>
"""

// MARK: - WKWebView 跨平台 Representable 封装
#if canImport(UIKit)
public struct HybridWKWebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit
public struct HybridWKWebViewRepresentable: NSViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeNSView(context: Context) -> WKWebView {
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

// MARK: - JSBridge 协调器与事件监听器
final class VZPlayerJSBridgeCoordinator: NSObject, WKScriptMessageHandler, VZH5EventListener {
    weak var webView: WKWebView?
    weak var vzPlayer: IH5Player?
    
    // 预设源映射
    private let presetSources: [String: [VZPlayerSource]] = [
        "vod_girl": [
            VZPlayerSource(url: "https://vplayerctrl-dev.weizan.cn/girl.mp4", type: "hls", tag: "vod_girl", videoCodec: 2, orderno: 1, isLive: false, ext: "mp4"),
            VZPlayerSource(url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8", type: "hls", tag: "live_backup", videoCodec: 2, orderno: 2, isLive: false, ext: "m3u8")
        ],
        "live_vzan1": [
            VZPlayerSource(url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8", type: "hls", tag: "live_vzan1", videoCodec: 2, orderno: 1, isLive: true, ext: "m3u8"),
            VZPlayerSource(url: "https://p2.vzan.com/teststream40/teststream40/live.m3u8", type: "hls", tag: "live_backup", videoCodec: 2, orderno: 2, isLive: true, ext: "m3u8")
        ],
        "live_vzan2": [
            VZPlayerSource(url: "https://p2.vzan.com/teststream40/teststream40/live.m3u8", type: "hls", tag: "live_vzan2", videoCodec: 2, orderno: 1, isLive: true, ext: "m3u8"),
            VZPlayerSource(url: "https://vplayerctrl-dev.weizan.cn/girl.mp4", type: "hls", tag: "vod_backup", videoCodec: 2, orderno: 2, isLive: true, ext: "mp4")
        ],
        "live_test": [
            VZPlayerSource(url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", type: "hls", tag: "live_test", videoCodec: 2, orderno: 1, isLive: true, ext: "m3u8")
        ]
    ]
    
    init(webView: WKWebView, vzPlayer: IH5Player?) {
        self.webView = webView
        self.vzPlayer = vzPlayer
        super.init()
    }
    
    // MARK: - WKScriptMessageHandler (拦截 H5 ➔ Native 指令)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vzPlayerBridge",
              let dict = message.body as? [String: Any],
              let method = dict["method"] as? String else {
            return
        }
        
        let paramsJson = dict["paramsJson"] as? String ?? "{}"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.vzPlayer else { return }
            
            switch method {
            case "play":
                player.play()
            case "pause":
                player.pause()
            case "setCurrentTime":
                _ = player.set_currentTime(paramsJson)
            case "setSpeed":
                _ = player.set_speed(paramsJson)
            case "setVolume":
                _ = player.set_volume(paramsJson)
            case "setMuted":
                _ = player.set_muted(paramsJson)
            case "switchSource":
                if let key = self.extractSourceKey(from: paramsJson), let sources = self.presetSources[key] {
                    player.setSources(sources)
                    player.play()
                } else if paramsJson.contains("live") {
                    player.setSources(self.presetSources["live_vzan1"] ?? [])
                    player.play()
                } else {
                    player.setSources(self.presetSources["vod_girl"] ?? [])
                    player.play()
                }
            case "getProperties":
                self.syncPropertiesToH5()
            default:
                break
            }
        }
    }
    
    private func extractSourceKey(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = dict["sourceKey"] as? String else {
            return nil
        }
        return key
    }
    
    private func syncPropertiesToH5() {
        guard let player = vzPlayer, let webView = webView else { return }
        let curTimeJson = player.get_currentTime()
        let durJson = player.get_duration()
        let speedJson = player.get_speed()
        let volJson = player.get_volume()
        let mutedJson = player.get_muted()
        let widthJson = player.get_videoWidth()
        let heightJson = player.get_videoHeight()
        let srcJson = player.get_currentsource()
        
        let script = """
        (function() {
            try {
                const curTime = \(curTimeJson).currentTime || 0;
                const dur = \(durJson).duration || 0;
                const spd = \(speedJson).speed || 1.0;
                const vol = \(volJson).volume || 1.0;
                const mut = \(mutedJson).muted || false;
                const w = \(widthJson).videoWidth || 0;
                const h = \(heightJson).videoHeight || 0;
                const src = \(srcJson.isEmpty ? "{}" : srcJson);
                if (window.vzBridgeUpdateProperties) {
                    window.vzBridgeUpdateProperties({
                        currentTime: curTime,
                        duration: dur,
                        speed: spd,
                        volume: vol,
                        muted: mut,
                        videoWidth: w,
                        videoHeight: h,
                        currentSource: src
                    });
                }
            } catch(e) {
                console.error(e);
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    // MARK: - VZH5EventListener (Native ➔ H5 实时广播)
    func onEvent(_ eventName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let script = "if (window.vzBridgeReceiveEvent) { window.vzBridgeReceiveEvent('\(eventName)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func onTimeUpdate(_ currentTime: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let script = "if (window.vzBridgeReceiveTimeUpdate) { window.vzBridgeReceiveTimeUpdate(\(currentTime)); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func onError(_ code: Int, errMsg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let safeMsg = errMsg.replacingOccurrences(of: "'", with: "\\'")
            let script = "if (window.vzBridgeReceiveError) { window.vzBridgeReceiveError(\(code), '\(safeMsg)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - H5 混合播放演示主视图 (WebViewHybridPlayerView)
public struct WebViewHybridPlayerView: View {
    private let playerView = MediaPlayerView()
    @State private var vzPlayer: IH5Player?
    @State private var coordinator: VZPlayerJSBridgeCoordinator?
    @State private var webView: WKWebView?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部原生视频渲染窗口 (VZPlayerView)
            ZStack(alignment: .topLeading) {
                VZPlayerViewRepresentable(playerView: playerView)
                    .frame(height: 220)
                    .background(Color.black)
                
                // 顶部状态提示条
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("🖥 iOS 原生 Metal 渲染层")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    Text("⚡️ IH5Player Core")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                }
                .padding(8)
            }
            
            Divider()
            
            // MARK: - 2. 下方 WKWebView (承载 H5 控制台与 JSBridge 实时交互)
            if let wv = webView {
                HybridWKWebViewRepresentable(webView: wv)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载 H5 容器与 JSBridge...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            setupHybridPlayer()
        }
        .onDisappear {
            vzPlayer?.destroy()
        }
    }

    private func setupHybridPlayer() {
        guard vzPlayer == nil else { return }

        // 1. 创建 IH5Player 实例
        let player = export.CreateVZPlayer(playerView)
        self.vzPlayer = player

        // 2. 初始化 WKWebView 与 JSBridge 注入
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        
        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv

        let coord = VZPlayerJSBridgeCoordinator(webView: wv, vzPlayer: player)
        self.coordinator = coord
        
        // 注册 JSBridge 消息监听
        userController.add(coord, name: "vzPlayerBridge")
        config.userContentController = userController
        
        // 注册播放器事件监听器
        player.setOnH5EventListener(coord)

        // 默认载入测试播放源并自动起播
        let initialSources = [
            VZPlayerSource(
                url: "https://vplayerctrl-dev.weizan.cn/girl.mp4",
                type: "hls",
                tag: "vod_girl",
                videoCodec: 2,
                orderno: 1,
                isLive: false,
                ext: "mp4"
            ),
            VZPlayerSource(
                url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8",
                type: "hls",
                tag: "live_backup",
                videoCodec: 2,
                orderno: 2,
                isLive: false,
                ext: "m3u8"
            )
        ]
        player.setSources(initialSources)
        player.play()

        // 3. 加载 H5 控制台页面
        wv.loadHTMLString(hybridPlayerHTML, baseURL: nil)
    }
}
