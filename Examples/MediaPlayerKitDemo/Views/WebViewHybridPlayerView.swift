import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTML 嵌入式 H5 播放控制器页面模板 (动态节点流与多源容错架构)
private let hybridPlayerHTML: String = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>IH5Player 节点混合控制台</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", Arial, sans-serif; -webkit-tap-highlight-color: transparent; }
        html, body { height: 100%; width: 100%; background-color: #0B0F19; color: #F8FAFC; font-size: 13px; overflow: hidden; display: flex; flex-direction: column; }
        
        /* 1. 主内容区域容器 (置于上方，自适应占满所有可用空间) */
        .tab-content-container { flex: 1; min-height: 0; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 12px; }
        .tab-pane { display: none; height: 100%; }
        .tab-pane.active { display: flex; flex-direction: column; animation: fadeIn 0.15s ease-in-out; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(3px); } to { opacity: 1; transform: translateY(0); } }

        /* 2. 底部 Tab 导航栏 (贴近大拇指操作区，单手轻松切换) */
        .tab-bar { display: flex; background: #1E293B; border-top: 1px solid #334155; padding: 6px 6px 8px 6px; gap: 6px; flex-shrink: 0; }
        .tab-btn { flex: 1; padding: 8px 2px; text-align: center; font-size: 12px; font-weight: 600; color: #94A3B8; background: transparent; border: none; border-radius: 8px; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; gap: 4px; }
        .tab-btn.active { background: #2563EB; color: #FFFFFF; font-weight: 700; box-shadow: 0 2px 8px rgba(37, 99, 235, 0.4); }
        .tab-badge { font-size: 9.5px; background: rgba(255, 255, 255, 0.25); padding: 1px 5px; border-radius: 6px; }

        /* 卡片样式 */
        .card { background: #1E293B; border-radius: 10px; padding: 10px; margin-bottom: 10px; border: 1px solid #334155; }
        
        /* 迷你实时事件横幅 */
        .mini-event-banner { background: #0F172A; border: 1px solid #3B82F6; border-radius: 8px; padding: 8px 10px; margin-bottom: 10px; display: flex; align-items: center; justify-content: space-between; font-size: 11.5px; flex-shrink: 0; }
        .mini-event-text { color: #60A5FA; font-weight: 600; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        
        /* 节点状态指示条 */
        .node-chip { background: rgba(59, 130, 246, 0.15); border: 1px solid #3B82F6; border-radius: 6px; padding: 4px 8px; margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between; font-size: 11px; }
        .node-name { color: #93C5FD; font-weight: 700; display: flex; align-items: center; gap: 4px; }

        /* 主播放大按钮 */
        .main-play-btn { width: 100%; height: 44px; border-radius: 10px; border: none; font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2563EB; display: flex; align-items: center; justify-content: center; gap: 8px; cursor: pointer; margin-bottom: 10px; flex-shrink: 0; transition: all 0.15s; box-shadow: 0 4px 10px rgba(37, 99, 235, 0.35); }
        .main-play-btn.playing { background: #D97706; box-shadow: 0 4px 10px rgba(217, 119, 6, 0.35); }
        .main-play-btn:active { transform: scale(0.98); }

        /* 快捷按钮网格 */
        .btn-grid-4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 8px; flex-shrink: 0; }
        .btn-grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; margin-bottom: 8px; flex-shrink: 0; }
        .btn { background: #334155; color: #F1F5F9; border: none; border-radius: 8px; padding: 10px 4px; font-size: 12px; font-weight: 600; cursor: pointer; text-align: center; transition: all 0.15s; display: flex; align-items: center; justify-content: center; gap: 4px; }
        .btn:active { background: #2563EB; color: #FFF; transform: scale(0.96); }
        .btn.active { background: #2563EB; color: #FFF; border: 1px solid #60A5FA; font-weight: 700; }

        /* 滑块控制器 */
        .slider-box { background: #0F172A; border-radius: 8px; padding: 8px 10px; margin-bottom: 8px; border: 1px solid #334155; flex-shrink: 0; }
        .slider-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; font-size: 12px; }
        .slider-row input[type=range] { flex: 1; accent-color: #3B82F6; height: 6px; border-radius: 3px; }

        /* 流与播放源卡片列表 */
        .stream-card-list { display: flex; flex-direction: column; gap: 8px; }
        .source-card { background: #0F172A; border: 1.5px solid #334155; border-radius: 8px; padding: 10px 12px; cursor: pointer; transition: all 0.2s; }
        .source-card.active { border-color: #3B82F6; background: rgba(59, 130, 246, 0.18); box-shadow: 0 0 10px rgba(59, 130, 246, 0.2); }
        .source-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; font-weight: 700; font-size: 12.5px; color: #F1F5F9; }
        .source-stream-id { font-family: monospace; font-size: 12px; color: #38BDF8; font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 220px; }
        .source-desc { font-size: 10.5px; color: #94A3B8; word-break: break-all; margin-top: 3px; }
        .source-badge { font-size: 10px; padding: 2px 7px; border-radius: 4px; background: #334155; color: #CBD5E1; }
        .source-badge.active-badge { background: #2563EB; color: #FFF; font-weight: 700; }
        .source-badge.live-badge { background: #059669; color: #FFF; font-weight: 700; }

        /* 日志盒子 (全高占满) */
        .log-box { background: #020617; border-radius: 8px; padding: 10px; flex: 1; min-height: 200px; overflow-y: auto; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 11px; border: 1px solid #334155; }
        .log-item { margin-bottom: 6px; line-height: 1.4; border-bottom: 1px solid rgba(51, 65, 85, 0.3); padding-bottom: 4px; }
        .log-time { color: #64748B; margin-right: 4px; }
        .log-event { color: #34D399; font-weight: bold; }
        .log-error { color: #F87171; font-weight: bold; }
        .log-cmd { color: #60A5FA; font-weight: 600; }
        .log-auto { color: #FBBF24; font-weight: bold; }

        /* 属性指标网格 */
        .stat-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; font-size: 11.5px; margin-top: 4px; flex-shrink: 0; }
        .stat-box { background: #0F172A; padding: 6px 8px; border-radius: 6px; border: 1px solid #334155; }
        .stat-label { color: #94A3B8; font-size: 10px; margin-bottom: 2px; }
        .stat-val { font-family: ui-monospace, SFMono-Regular, monospace; font-weight: 700; color: #38BDF8; }

        /* 演练指南卡片 */
        .guide-box { background: linear-gradient(135deg, #1E293B, #0F172A); border: 1.5px solid #3B82F6; border-radius: 10px; padding: 14px; margin-bottom: 10px; }
        .auto-btn { width: 100%; background: linear-gradient(90deg, #2563EB, #4F46E5); color: #FFFFFF; border: none; border-radius: 8px; padding: 12px; font-size: 14px; font-weight: 700; cursor: pointer; text-align: center; box-shadow: 0 3px 8px rgba(37, 99, 235, 0.4); margin-top: 10px; }
        .auto-btn:active { transform: scale(0.98); }
    </style>
</head>
<body>

    <!-- 1. 内容区域容器 (置于上方，垂直方向最大化展开) -->
    <div class="tab-content-container">

        <!-- ================= TAB 1: 核心控制器 (单屏即可操作所有常用控制) ================= -->
        <div class="tab-pane active" id="tabControls">
            
            <!-- 实时事件吸顶迷你横幅 -->
            <div class="mini-event-banner">
                <div class="mini-event-text">
                    <span>⚡️</span><span id="miniEventStatus">Native 状态: preparing (准备就绪)</span>
                </div>
                <span style="font-size: 10px; color: #94A3B8;" id="miniEventTime">00:00</span>
            </div>

            <!-- 当前节点与流标识 -->
            <div class="node-chip">
                <span class="node-name">📡 <span id="ctrlNodeName">节点: 未连接</span></span>
                <span style="font-family: monospace; font-size: 10.5px; color: #CBD5E1;" id="ctrlStreamId">Stream: vod_girl</span>
            </div>

            <!-- 主播放/暂停大按钮 -->
            <button class="main-play-btn playing" id="mainPlayBtn" onclick="togglePlayPause()">
                <span id="mainPlayIcon">⏸</span><span id="mainPlayText">暂停播放 (Pause)</span>
            </button>

            <!-- 进度调节 -->
            <div class="slider-box">
                <div class="slider-row">
                    <span style="min-width: 35px; color: #94A3B8;">进度</span>
                    <input type="range" id="seekSlider" min="0" max="100" value="0" onchange="onSeekChange(this.value)">
                    <span id="timeText" style="min-width: 90px; text-align: right; font-family: monospace; font-weight: 700; color: #38BDF8;">00:00 / 00:00</span>
                </div>
            </div>

            <!-- 快退/快进/静音/刷新 -->
            <div class="btn-grid-4">
                <button class="btn" onclick="seekRelative(-10)">⏪ -10s</button>
                <button class="btn" onclick="seekRelative(10)">⏩ +10s</button>
                <button class="btn" id="muteBtn" onclick="toggleMute()">🔊 静音开</button>
                <button class="btn" onclick="refreshProperties()">🔄 查属性</button>
            </div>

            <!-- 倍速快速切换 -->
            <div class="btn-grid-4">
                <button class="btn speed-btn active" id="spd10" onclick="setSpeed(1.0)">1.0x</button>
                <button class="btn speed-btn" id="spd125" onclick="setSpeed(1.25)">1.25x</button>
                <button class="btn speed-btn" id="spd15" onclick="setSpeed(1.5)">1.5x</button>
                <button class="btn speed-btn" id="spd20" onclick="setSpeed(2.0)">2.0x</button>
            </div>

            <!-- 音量滑块 -->
            <div class="slider-box">
                <div class="slider-row">
                    <span style="min-width: 35px; color: #94A3B8;">音量</span>
                    <input type="range" id="volumeSlider" min="0" max="100" value="100" oninput="onVolumeChange(this.value)">
                    <span id="volumeText" style="min-width: 35px; text-align: right; font-family: monospace; color: #38BDF8;">100%</span>
                </div>
            </div>

            <!-- 属性概览指标 -->
            <div class="stat-grid">
                <div class="stat-box">
                    <div class="stat-label">当前倍速 / 音量</div>
                    <div class="stat-val" id="statSpeedVol">1.0x / 100%</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">视频自然分辨率</div>
                    <div class="stat-val" id="statResolution">自适应</div>
                </div>
            </div>
        </div>

        <!-- ================= TAB 2: 换播放源与节点在线流 ================= -->
        <div class="tab-pane" id="tabSources">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                <div style="font-size: 12px; color: #94A3B8;">
                    当前节点: <b style="color: #60A5FA;" id="sourcesNodeRemark">火山北京</b> (<span id="sourcesNodeDomain">p8.vzan.com</span>)
                </div>
                <button class="btn" style="padding: 3px 8px; font-size: 11px;" onclick="refreshNodeStreams()">🔄 刷新流</button>
            </div>

            <!-- 动态节点流容器 -->
            <div class="stream-card-list" id="dynamicStreamsContainer">
                <div style="text-align: center; color: #64748B; padding: 20px; font-size: 11.5px;">正在加载节点实时流列表...</div>
            </div>

            <div style="margin-top: 12px; margin-bottom: 6px; font-size: 11px; font-weight: bold; color: #64748B;">测试与备用播放源</div>
            <div class="stream-card-list">
                <div class="source-card" id="src_vod_girl" onclick="selectPresetSource('vod_girl')">
                    <div class="source-header">
                        <span>🎬 经典点播 MP4 (官方测试)</span>
                        <span class="source-badge" id="badge_vod_girl">点此切换</span>
                    </div>
                    <div class="source-desc">https://vplayerctrl-dev.weizan.cn/girl.mp4 (720P)</div>
                </div>

                <div class="source-card" id="src_live_test" onclick="selectPresetSource('live_test')">
                    <div class="source-header">
                        <span>⚡️ 官方容错直播测试流</span>
                        <span class="source-badge" id="badge_live_test">点此切换</span>
                    </div>
                    <div class="source-desc">https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</div>
                </div>
            </div>
        </div>

        <!-- ================= TAB 3: 实时事件流日志 ================= -->
        <div class="tab-pane" id="tabLogs">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; flex-shrink: 0;">
                <span style="font-size: 12px; color: #94A3B8;">实时记录 VZH5EventListener 广播事件：</span>
                <button class="btn" style="padding: 3px 10px; font-size: 11px;" onclick="clearLogs()">清空日志</button>
            </div>
            <div class="log-box" id="logBox">
                <div class="log-item"><span class="log-time">[Init]</span><span class="log-cmd">🚀 JSBridge 准备就绪，已向原生发送起播指令...</span></div>
            </div>
        </div>

        <!-- ================= TAB 4: 演练与指南 ================= -->
        <div class="tab-pane" id="tabGuide">
            <div class="guide-box">
                <div style="font-size: 13.5px; font-weight: 700; color: #60A5FA; margin-bottom: 6px;">💡 混合开发原理</div>
                <div style="font-size: 12px; color: #CBD5E1; line-height: 1.55; margin-bottom: 10px;">
                    上方视频由 <b>iOS 原生 Metal / AVPlayer</b> 硬件加速渲染；<br>
                    下方由 <b>WKWebView</b> 承载 H5 控制台。通过 <code>StreamAPIService</code> 动态拉取当前节点的在线流与播放地址，并通过 <b>JSON 契约</b> 双向透传。
                </div>
                <div style="font-size: 12.5px; font-weight: 700; color: #FBBF24; margin-bottom: 4px;">🚀 懒人体验：一键自动全流程演练</div>
                <div style="font-size: 11.5px; color: #94A3B8; margin-bottom: 8px;">
                    点击下方按钮，将全自动按顺序执行：起播节点首选流 ➔ Seek 5s ➔ 1.5x 倍速 ➔ 静音切换 ➔ 动态切流 ➔ 恢复 1.0x。
                </div>
                <button class="auto-btn" onclick="runAutoDemonstration()">
                    <span id="autoBtnText">立即开始「一键全功能自动化演练」</span>
                </button>
            </div>
        </div>

    </div>

    <!-- 2. 最下方 Tab 导航栏 (贴合大拇指操作区，单手轻松切换) -->
    <div class="tab-bar">
        <button class="tab-btn active" onclick="switchTab('tabControls')">🎮 控制台</button>
        <button class="tab-btn" onclick="switchTab('tabSources')">📺 换播源</button>
        <button class="tab-btn" onclick="switchTab('tabLogs')">📡 实时日志<span class="tab-badge" id="logCountBadge">0</span></button>
        <button class="tab-btn" onclick="switchTab('tabGuide')">🚀 自动演练</button>
    </div>

    <script>
        let currentPosSec = 0;
        let totalDurationSec = 0;
        let isPlayingState = true;
        let isMutedState = false;
        let currentSpeed = 1.0;
        let logCounter = 0;
        let isAutoTesting = false;
        let currentActiveStreamId = '';
        let availableStreams = [];

        // 选项卡切换
        function switchTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
            
            const btn = Array.from(document.querySelectorAll('.tab-bar button')).find(b => b.getAttribute('onclick').includes(tabId));
            if (btn) btn.classList.add('active');
            
            const pane = document.getElementById(tabId);
            if (pane) pane.classList.add('active');
        }

        function log(type, msg) {
            logCounter++;
            const badge = document.getElementById('logCountBadge');
            if (badge) badge.innerText = logCounter;

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
            if (type === 'Node') tag = `<span class="log-cmd" style="color:#A78BFA;">[节点调度]</span>`;
            
            item.innerHTML = `<span class="log-time">${timeStr}</span>${tag} ${msg}`;
            box.appendChild(item);
            box.scrollTop = box.scrollHeight;
        }

        function clearLogs() {
            logCounter = 0;
            document.getElementById('logCountBadge').innerText = '0';
            document.getElementById('logBox').innerHTML = '';
        }

        // JSBridge 通信
        function sendCmd(method, paramsJson = '{}') {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vzPlayerBridge) {
                window.webkit.messageHandlers.vzPlayerBridge.postMessage({
                    method: method,
                    paramsJson: paramsJson
                });
                log('H5➔iOS', `执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
            } else {
                log('Web独立', `[独立模式] 执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
                simulateWebResponse(method, paramsJson);
            }
        }

        // 动态切节点流
        function selectNodeStream(streamId) {
            currentActiveStreamId = streamId;
            document.getElementById('ctrlStreamId').innerText = 'Stream: ' + streamId;
            updateStreamCardsHighlight();
            sendCmd('switchStream', JSON.stringify({ streamId: streamId }));
            setTimeout(() => switchTab('tabControls'), 300);
        }

        // 选择内置备用源
        function selectPresetSource(sourceKey) {
            currentActiveStreamId = sourceKey;
            document.getElementById('ctrlStreamId').innerText = 'Stream: ' + sourceKey;
            updateStreamCardsHighlight();
            sendCmd('switchSource', JSON.stringify({ sourceKey: sourceKey }));
            setTimeout(() => switchTab('tabControls'), 300);
        }

        function refreshNodeStreams() {
            log('Node', '向 Native 发送刷新节点在线流指令...');
            sendCmd('refreshStreams');
        }

        // Native 注入节点流列表
        window.vzBridgeUpdateStreamList = function(data) {
            try {
                const nodeRemark = data.activeNodeRemark || '默认节点';
                const nodeDomain = data.activeNodeDomain || '';
                availableStreams = data.streams || [];
                currentActiveStreamId = data.currentStreamId || currentActiveStreamId;

                document.getElementById('ctrlNodeName').innerText = '节点: ' + (nodeRemark || nodeDomain);
                document.getElementById('sourcesNodeRemark').innerText = nodeRemark || '当前节点';
                document.getElementById('sourcesNodeDomain').innerText = nodeDomain;

                const container = document.getElementById('dynamicStreamsContainer');
                if (!container) return;

                if (availableStreams.length === 0) {
                    container.innerHTML = '<div style="text-align: center; color: #94A3B8; padding: 15px; background: #0F172A; border-radius: 8px;">当前节点暂无活跃在线推流，可点击下方测试播放源</div>';
                    return;
                }

                let html = '';
                availableStreams.forEach((s, idx) => {
                    const isActive = s.streamid === currentActiveStreamId;
                    const resBadge = s.resolution ? `<span style="font-size: 9px; background: rgba(59,130,246,0.2); color:#60A5FA; padding: 1px 4px; border-radius:3px;">${s.resolution}</span>` : '';
                    const fpsBadge = s.fps ? `<span style="font-size: 9px; color:#94A3B8;">${s.fps}</span>` : '';
                    
                    html += `
                    <div class="source-card ${isActive ? 'active' : ''}" id="stream_${s.streamid}" onclick="selectNodeStream('${s.streamid}')">
                        <div class="source-header">
                            <span class="source-stream-id">📡 ${s.streamid}</span>
                            <span class="source-badge ${isActive ? 'active-badge' : 'live-badge'}">${isActive ? '当前播放中 ✓' : '在线直播'}</span>
                        </div>
                        <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                            ${resBadge} ${fpsBadge}
                            <span style="font-size: 9.5px; color:#64748B;">HLS/FLV 多源容错</span>
                        </div>
                    </div>`;
                });
                container.innerHTML = html;
                log('Node', `已加载 <b>${availableStreams.length}</b> 条节点在线流`);
            } catch(e) {
                console.error(e);
            }
        };

        function updateStreamCardsHighlight() {
            document.querySelectorAll('.source-card').forEach(c => c.classList.remove('active'));
            document.querySelectorAll('.source-badge').forEach(b => {
                if (!b.classList.contains('live-badge')) b.innerText = '点此切换';
            });
            const activeCard = document.getElementById('stream_' + currentActiveStreamId) || document.getElementById('src_' + currentActiveStreamId);
            if (activeCard) {
                activeCard.classList.add('active');
                const badge = activeCard.querySelector('.source-badge');
                if (badge) {
                    badge.innerText = '当前播放中 ✓';
                    badge.className = 'source-badge active-badge';
                }
            }
        }

        // Web 独立模式下的自闭环模拟
        function simulateWebResponse(method, paramsJson) {
            if (method === 'play') {
                window.vzBridgeReceiveEvent('playing');
            } else if (method === 'pause') {
                window.vzBridgeReceiveEvent('pause');
            } else if (method === 'getProperties') {
                window.vzBridgeUpdateProperties({
                    currentTime: currentPosSec,
                    duration: totalDurationSec || 120,
                    speed: currentSpeed,
                    volume: 1.0,
                    muted: isMutedState,
                    videoWidth: 1920,
                    videoHeight: 1080
                });
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
            updateStats();
        }

        function toggleMute() {
            isMutedState = !isMutedState;
            document.getElementById('muteBtn').innerText = isMutedState ? '🔇 已静音' : '🔊 静音开';
            sendCmd('setMuted', JSON.stringify({ muted: isMutedState }));
            updateStats();
        }

        function onVolumeChange(val) {
            document.getElementById('volumeText').innerText = val + '%';
            const vol = parseFloat(val) / 100.0;
            sendCmd('setVolume', JSON.stringify({ volume: vol }));
            updateStats();
        }

        function refreshProperties() {
            sendCmd('getProperties');
        }

        function updateStats() {
            const volText = (document.getElementById('volumeSlider').value) + '%';
            const muteText = isMutedState ? ' (静音)' : '';
            document.getElementById('statSpeedVol').innerText = `${currentSpeed}x / ${volText}${muteText}`;
        }

        // ================= 自动化演练脚本 =================
        function runAutoDemonstration() {
            if (isAutoTesting) return;
            isAutoTesting = true;
            const btn = document.getElementById('autoBtnText');
            btn.innerText = '⏳ 演练中... 请查看画面与控制台';
            switchTab('tabLogs');
            log('Auto', '=== 🚀 开始节点流自动化测试演练 ===');

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

                    log('Auto', '步骤 4/5: 动态切换节点流/备用源');
                    if (availableStreams.length > 0) {
                        selectNodeStream(availableStreams[0].streamid);
                    } else {
                        selectPresetSource('vod_girl');
                    }
                    await sleep(2000);

                    log('Auto', '步骤 5/5: 恢复 1.0x 倍速');
                    setSpeed(1.0);
                    await sleep(1000);

                    log('Auto', '🎉 自动化演练全部完成！各节点 API 响应正常。');
                } catch(e) {
                    log('Error', '演练异常: ' + e);
                } finally {
                    isAutoTesting = false;
                    btn.innerText = '🚀 再次体验「一键全功能自动化演练」';
                }
            })();
        }

        // ================= Native ➔ H5 回调注入方法 =================

        window.vzBridgeReceiveEvent = function(eventName) {
            log('Event', `接收事件: <b>${eventName}</b>`);
            const miniStatus = document.getElementById('miniEventStatus');
            const playBtn = document.getElementById('mainPlayBtn');
            const playIcon = document.getElementById('mainPlayIcon');
            const playText = document.getElementById('mainPlayText');

            if (eventName === 'playing' || eventName === 'play') {
                isPlayingState = true;
                if (miniStatus) miniStatus.innerText = `Native 状态: ${eventName} (正在播放)`;
                if (playBtn) {
                    playBtn.className = 'main-play-btn playing';
                    playIcon.innerText = '⏸';
                    playText.innerText = '暂停播放 (Pause)';
                }
            } else if (eventName === 'pause') {
                isPlayingState = false;
                if (miniStatus) miniStatus.innerText = 'Native 状态: pause (已暂停)';
                if (playBtn) {
                    playBtn.className = 'main-play-btn';
                    playIcon.innerText = '▶️';
                    playText.innerText = '开始播放 (Play)';
                }
            } else if (eventName === 'waiting') {
                if (miniStatus) miniStatus.innerText = 'Native 状态: waiting (缓冲中...)';
            } else if (eventName === 'ended') {
                isPlayingState = false;
                if (miniStatus) miniStatus.innerText = 'Native 状态: ended (已结束)';
                if (playBtn) {
                    playBtn.className = 'main-play-btn';
                    playIcon.innerText = '▶️';
                    playText.innerText = '重新播放 (Replay)';
                }
            }
            sendCmd('getProperties');
        };

        window.vzBridgeReceiveTimeUpdate = function(currentTimeSec) {
            currentPosSec = currentTimeSec;
            const curStr = formatTime(currentPosSec);
            
            if (totalDurationSec > 0) {
                const durStr = formatTime(totalDurationSec);
                const percent = Math.min(100, Math.floor((currentPosSec / totalDurationSec) * 100));
                document.getElementById('seekSlider').value = percent;
                document.getElementById('timeText').innerText = `${curStr} / ${durStr}`;
                document.getElementById('miniEventTime').innerText = `${curStr}/${durStr}`;
            } else {
                document.getElementById('timeText').innerText = `${curStr} (直播)`;
                document.getElementById('miniEventTime').innerText = curStr;
            }
        };

        window.vzBridgeReceiveError = function(code, errMsg) {
            log('Error', `播放异常 code=${code} msg=${errMsg}`);
            const miniStatus = document.getElementById('miniEventStatus');
            if (miniStatus) miniStatus.innerText = `Native 错误: ${code}`;
        };

        window.vzBridgeUpdateProperties = function(props) {
            try {
                if (props.duration !== undefined && props.duration > 0) {
                    totalDurationSec = props.duration;
                }
                if (props.speed !== undefined) {
                    currentSpeed = props.speed;
                }
                if (props.videoWidth && props.videoHeight) {
                    document.getElementById('statResolution').innerText = `${props.videoWidth}x${props.videoHeight}`;
                }
                updateStats();
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

// MARK: - JSBridge 协调器与事件监听器 (全面支持节点流与动态地址解析)
final class VZPlayerJSBridgeCoordinator: NSObject, WKScriptMessageHandler, VZH5EventListener {
    weak var webView: WKWebView?
    weak var vzPlayer: IH5Player?
    private let apiService = StreamAPIService.shared
    
    // 当前正在播放的流 ID / 标记
    var currentPlayingStreamId: String = "vod_girl"
    
    // 基础备用源
    private let fallbackSources: [String: [VZPlayerSource]] = [
        "vod_girl": [
            VZPlayerSource(url: "https://vplayerctrl-dev.weizan.cn/girl.mp4", type: "hls", tag: "vod_girl", videoCodec: 2, orderno: 1, isLive: false, ext: "mp4"),
            VZPlayerSource(url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8", type: "hls", tag: "live_backup", videoCodec: 2, orderno: 2, isLive: false, ext: "m3u8")
        ],
        "live_test": [
            VZPlayerSource(url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", type: "hls", tag: "live_test", videoCodec: 2, orderno: 1, isLive: true, ext: "m3u8")
        ]
    ]
    
    init(webView: WKWebView? = nil, vzPlayer: IH5Player?) {
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
            case "switchStream":
                // 动态切节点流：通过 API 解析真实播放地址
                if let streamId = self.extractParam(from: paramsJson, key: "streamId") {
                    self.playNodeStream(streamId: streamId)
                }
            case "switchSource":
                // 切换备用测试源
                if let key = self.extractParam(from: paramsJson, key: "sourceKey"), let sources = self.fallbackSources[key] {
                    self.currentPlayingStreamId = key
                    player.setSources(sources)
                    player.play()
                    self.syncPropertiesToH5()
                } else {
                    self.playNodeStream(streamId: "vod_girl")
                }
            case "refreshStreams":
                self.apiService.fetchStreamList { [weak self] _ in
                    self?.syncNodeStreamsToH5()
                }
            case "getProperties":
                self.syncPropertiesToH5()
            default:
                break
            }
        }
    }
    
    /// 播放节点的在线流：自动请求 toolsapi 播放地址并构造成多源容错管线
    func playNodeStream(streamId: String) {
        guard let player = vzPlayer else { return }
        self.currentPlayingStreamId = streamId
        
        apiService.fetchPlayerSources(for: streamId) { [weak self] container in
            guard let self = self else { return }
            if let container = container, !container.allSources.isEmpty {
                let vzSources = container.allSources.enumerated().map { (index, item) -> VZPlayerSource in
                    let source = VZPlayerSource(
                        url: item.src,
                        type: item.type.lowercased(),
                        tag: item.tag ?? "source_\(index)",
                        videoCodec: item.videoCodec ?? (item.codecText.contains("265") ? 4 : 2),
                        orderno: index + 1,
                        isLive: true,
                        ext: item.type.lowercased()
                    )
                    source.sourceIndex = index
                    return source
                }
                player.setSources(vzSources)
                player.play()
            } else if let fallback = self.fallbackSources[streamId] ?? self.fallbackSources["vod_girl"] {
                player.setSources(fallback)
                player.play()
            }
            self.syncNodeStreamsToH5()
            self.syncPropertiesToH5()
        }
    }
    
    private func extractParam(from json: String, key: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = dict[key] as? String else {
            return nil
        }
        return val
    }
    
    /// 将节点最新在线流与状态实时同步给 H5
    func syncNodeStreamsToH5() {
        guard let webView = webView else { return }
        
        let streamsArray: [[String: Any]] = apiService.streamList.map { s in
            return [
                "streamid": s.streamid,
                "resolution": s.resolutionText,
                "fps": s.fpsText
            ]
        }
        
        let payload: [String: Any] = [
            "activeNodeDomain": apiService.activeNodeDomain,
            "activeNodeRemark": apiService.activeNodeItem?.remark ?? apiService.activeNodeDomain,
            "currentStreamId": currentPlayingStreamId,
            "streams": streamsArray
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonStr = String(data: data, encoding: .utf8) {
            let script = "if (window.vzBridgeUpdateStreamList) { window.vzBridgeUpdateStreamList(\(jsonStr)); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func syncPropertiesToH5() {
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
    @ObservedObject private var apiService = StreamAPIService.shared
    
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
                
                // 顶部状态提示条与快捷节点菜单
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("🖥 iOS 原生 Metal 渲染层")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    if !apiService.nodeItems.isEmpty {
                        Menu {
                            ForEach(apiService.nodeItems) { item in
                                Button(action: {
                                    apiService.setActiveNode(domain: item.domain)
                                }) {
                                    HStack {
                                        Text(item.displayText)
                                        if apiService.activeNodeDomain == item.domain {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 9))
                                Text(apiService.activeNodeItem?.remark.isEmpty == false ? apiService.activeNodeItem!.remark : apiService.activeNodeDomain)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7.5))
                            }
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(6)
            }
            
            Divider()
            
            // MARK: - 2. 下方 WKWebView (承载现代化底部导航 H5 控制台与 JSBridge)
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
            if apiService.hasCompleteConfig && apiService.streamList.isEmpty {
                apiService.fetchStreamList { _ in
                    coordinator?.syncNodeStreamsToH5()
                }
            }
        }
        .onReceive(apiService.$streamList) { streams in
            coordinator?.syncNodeStreamsToH5()
        }
        .onDisappear {
            if let userContentController = webView?.configuration.userContentController {
                userContentController.removeScriptMessageHandler(forName: "vzPlayerBridge")
            }
            vzPlayer?.destroy()
            vzPlayer = nil
            coordinator = nil
            webView = nil
        }
    }

    private func setupHybridPlayer() {
        guard vzPlayer == nil else { return }

        // 1. 创建 IH5Player 实例
        let player = export.CreateVZPlayer(playerView)
        self.vzPlayer = player

        // 2. 初始化 WKUserContentController 与 WKWebViewConfiguration
        let userController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userController

        let coord = VZPlayerJSBridgeCoordinator(webView: nil, vzPlayer: player)
        self.coordinator = coord
        
        // 注册 JSBridge 消息监听
        userController.add(coord, name: "vzPlayerBridge")
        
        let wv = WKWebView(frame: .zero, configuration: config)
        coord.webView = wv
        self.webView = wv
        
        // 注册播放器事件监听器
        player.setOnH5EventListener(coord)

        // 3. 起播节点的首个流或预设备用源
        if let firstStream = apiService.streamList.first {
            coord.playNodeStream(streamId: firstStream.streamid)
        } else {
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
        }

        // 4. 加载 H5 控制台页面并在加载后推送最新节点流
        wv.loadHTMLString(hybridPlayerHTML, baseURL: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coord.syncNodeStreamsToH5()
        }
    }
}
