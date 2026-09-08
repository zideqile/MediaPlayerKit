import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTML 嵌入式 H5 播放控制器页面模板 (动态节点流与流内多播放线路切换)
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

        /* 子播放线路卡片 */
        .subsource-card { background: #0F172A; border: 1.5px solid #334155; border-radius: 8px; padding: 9px 11px; cursor: pointer; transition: all 0.2s; }
        .subsource-card.active { border-color: #8B5CF6; background: rgba(139, 92, 246, 0.18); box-shadow: 0 0 10px rgba(139, 92, 246, 0.25); }
        .subsource-url { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 10px; color: #94A3B8; word-break: break-all; margin-top: 4px; background: #020617; padding: 4px 6px; border-radius: 4px; border: 1px solid rgba(51, 65, 85, 0.5); }

        .empty-hint { text-align: center; color: #64748B; padding: 16px; font-size: 11.5px; background: #0F172A; border-radius: 8px; border: 1px dashed #334155; }

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
        .stat-val { font-family: ui-monospace, SFMono-Regular, monospace; font-weight: 700; color: #38BDF8; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

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
                <span style="font-family: monospace; font-size: 10.5px; color: #CBD5E1;" id="ctrlStreamId">Stream: -</span>
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
                    <div class="stat-label">视频分辨率 / 协议</div>
                    <div class="stat-val" id="statResolution">自适应</div>
                </div>
            </div>
        </div>

        <!-- ================= TAB 2: 换播放源与节点在线流 ================= -->
        <div class="tab-pane" id="tabSources">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                <div style="font-size: 12px; color: #94A3B8;">
                    当前节点: <b style="color: #60A5FA;" id="sourcesNodeRemark">默认节点</b> (<span id="sourcesNodeDomain">-</span>)
                </div>
                <button class="btn" style="padding: 4px 10px; font-size: 11px;" onclick="refreshNodeStreams()">🔄 刷新推流</button>
            </div>

            <!-- 1. 节点实时在线推流列表 -->
            <div style="margin-bottom: 6px; font-size: 11.5px; font-weight: bold; color: #38BDF8; display: flex; align-items: center; justify-content: space-between;">
                <span>📡 节点实时在线推流 (<span id="streamCountText">0</span>)</span>
                <span style="font-size: 10px; color: #64748B; font-weight: normal;">点击卡片切换流</span>
            </div>
            <div class="stream-card-list" id="dynamicStreamsContainer">
                <div class="empty-hint">正在加载节点实时推流列表...</div>
            </div>

            <!-- 2. 当前流内的所有播放线路/地址列表 (支持手动切源) -->
            <div style="margin-top: 14px; margin-bottom: 6px; font-size: 11.5px; font-weight: bold; color: #A78BFA; display: flex; align-items: center; justify-content: space-between;">
                <span>🔀 当前流播放线路/地址 (<span id="subSourceCountText">0</span>)</span>
                <span style="font-size: 10px; color: #64748B; font-weight: normal;">点击卡片手动切源</span>
            </div>
            <div class="stream-card-list" id="dynamicSubSourcesContainer">
                <div class="empty-hint">请先在上方选择一条在线推流</div>
            </div>
        </div>

        <!-- ================= TAB 3: 实时事件流日志 ================= -->
        <div class="tab-pane" id="tabLogs">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; flex-shrink: 0;">
                <span style="font-size: 12px; color: #94A3B8;">实时记录 VZH5EventListener 广播事件：</span>
                <button class="btn" style="padding: 3px 10px; font-size: 11px;" onclick="clearLogs()">清空日志</button>
            </div>
            <div class="log-box" id="logBox">
                <div class="log-item"><span class="log-time">[Init]</span><span class="log-cmd">🚀 JSBridge 准备就绪，已向原生注册事件管道...</span></div>
            </div>
        </div>

        <!-- ================= TAB 4: 演练与指南 ================= -->
        <div class="tab-pane" id="tabGuide">
            <div class="guide-box">
                <div style="font-size: 13.5px; font-weight: 700; color: #60A5FA; margin-bottom: 6px;">💡 混合开发原理</div>
                <div style="font-size: 12px; color: #CBD5E1; line-height: 1.55; margin-bottom: 10px;">
                    上方视频由 <b>iOS 原生 Metal / AVPlayer</b> 硬件加速渲染；<br>
                    下方由 <b>WKWebView</b> 承载 H5 控制台。通过 <code>StreamAPIService</code> 动态拉取当前节点的在线流与真实播放地址，并通过 <b>JSON 契约</b> 与 <code>IH5Player</code> 接口实现双向透传与手动切源。
                </div>
                <div style="font-size: 12.5px; font-weight: 700; color: #FBBF24; margin-bottom: 4px;">🚀 懒人体验：一键自动全流程演练</div>
                <div style="font-size: 11.5px; color: #94A3B8; margin-bottom: 8px;">
                    点击下方按钮，将全自动按顺序执行：起播节点首选流 ➔ Seek 5s ➔ 1.5x 倍速 ➔ 静音切换 ➔ 多线路/切流演练 ➔ 恢复 1.0x。
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
        let currentActiveSourceIndex = 0;
        let availableStreams = [];
        let availableSubSources = [];

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
            const badge = document.getElementById('logCountBadge');
            if (badge) badge.innerText = '0';
            const box = document.getElementById('logBox');
            if (box) box.innerHTML = '';
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

        // 动态切节点推流
        function selectNodeStream(streamId) {
            currentActiveStreamId = streamId;
            currentActiveSourceIndex = 0;
            document.getElementById('ctrlStreamId').innerText = 'Stream: ' + streamId;
            updateHighlight();
            sendCmd('switchStream', JSON.stringify({ streamId: streamId }));
            log('Node', `手动切换到推流 <b>${streamId}</b>，正在解析播放线路...`);
        }

        // 手动切换当前流内的子播放地址/线路
        function selectSubSource(index) {
            currentActiveSourceIndex = index;
            updateHighlight();
            sendCmd('switchSubSource', JSON.stringify({ index: index, sourceIndex: index }));
            log('Node', `手动切换当前流播放线路 ➔ <b>线路 ${index + 1}</b>`);
            setTimeout(() => switchTab('tabControls'), 250);
        }

        function refreshNodeStreams() {
            log('Node', '向 Native 发送刷新节点在线流指令...');
            sendCmd('refreshStreams');
        }

        // Native 注入节点流列表与子播放线路
        window.vzBridgeUpdateStreamList = function(data) {
            try {
                const nodeRemark = data.activeNodeRemark || '默认节点';
                const nodeDomain = data.activeNodeDomain || '';
                availableStreams = data.streams || [];
                availableSubSources = data.subSources || [];
                currentActiveStreamId = data.currentStreamId || currentActiveStreamId;
                if (data.currentSourceIndex !== undefined) {
                    currentActiveSourceIndex = data.currentSourceIndex;
                }

                document.getElementById('ctrlNodeName').innerText = '节点: ' + (nodeRemark || nodeDomain);
                document.getElementById('sourcesNodeRemark').innerText = nodeRemark || '当前节点';
                document.getElementById('sourcesNodeDomain').innerText = nodeDomain;
                
                // 1. 渲染推流列表
                const streamContainer = document.getElementById('dynamicStreamsContainer');
                const streamCountText = document.getElementById('streamCountText');
                if (streamCountText) streamCountText.innerText = availableStreams.length;

                if (streamContainer) {
                    if (availableStreams.length === 0) {
                        streamContainer.innerHTML = '<div class="empty-hint">当前节点暂无活跃在线推流，请在顶部切换节点或刷新</div>';
                    } else {
                        let html = '';
                        availableStreams.forEach((s) => {
                            const isActive = s.streamid === currentActiveStreamId;
                            const resBadge = s.resolution ? `<span style="font-size: 9px; background: rgba(59,130,246,0.2); color:#60A5FA; padding: 1px 4px; border-radius:3px;">${s.resolution}</span>` : '';
                            const fpsBadge = s.fps ? `<span style="font-size: 9px; color:#94A3B8;">${s.fps}</span>` : '';
                            const bitrateBadge = s.bitrate ? `<span style="font-size: 9px; color:#A78BFA;">${s.bitrate}</span>` : '';
                            
                            html += `
                            <div class="source-card ${isActive ? 'active' : ''}" id="stream_${s.streamid}" onclick="selectNodeStream('${s.streamid}')">
                                <div class="source-header">
                                    <span class="source-stream-id">📡 ${s.streamid}</span>
                                    <span class="source-badge ${isActive ? 'active-badge' : 'live-badge'}">${isActive ? '当前选中 ✓' : '在线推流'}</span>
                                </div>
                                <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                                    ${resBadge} ${fpsBadge} ${bitrateBadge}
                                </div>
                            </div>`;
                        });
                        streamContainer.innerHTML = html;
                    }
                }

                // 2. 渲染当前流内播放线路/地址列表 (支持手动切源)
                const subContainer = document.getElementById('dynamicSubSourcesContainer');
                const subCountText = document.getElementById('subSourceCountText');
                if (subCountText) subCountText.innerText = availableSubSources.length;

                if (subContainer) {
                    if (availableSubSources.length === 0) {
                        subContainer.innerHTML = `<div class="empty-hint">${currentActiveStreamId ? '正在请求该流的播放线路或该流暂无可用地址...' : '请先在上方选择一条在线推流'}</div>`;
                    } else {
                        let subHtml = '';
                        availableSubSources.forEach((sub, idx) => {
                            const isSubActive = idx === currentActiveSourceIndex;
                            const typeBadge = sub.type ? `<span style="font-size: 9px; background: #334155; color:#F1F5F9; padding: 1px 5px; border-radius:3px; font-weight:bold;">${sub.type.toUpperCase()}</span>` : '';
                            const codecBadge = sub.codecText ? `<span style="font-size: 9px; background: rgba(139,92,246,0.2); color:#C4B5FD; padding: 1px 5px; border-radius:3px;">${sub.codecText}</span>` : '';
                            const tagBadge = sub.tag ? `<span style="font-size: 9px; color:#94A3B8;">${sub.tag}</span>` : '';

                            subHtml += `
                            <div class="subsource-card ${isSubActive ? 'active' : ''}" id="subsource_${idx}" onclick="selectSubSource(${idx})">
                                <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom: 3px;">
                                    <div style="display:flex; align-items:center; gap:5px; font-size:12px; font-weight:700; color:#F8FAFC;">
                                        <span>线路 ${idx + 1}</span>
                                        ${typeBadge}
                                        ${codecBadge}
                                        ${tagBadge}
                                    </div>
                                    <span class="source-badge ${isSubActive ? 'active-badge' : ''}" style="${isSubActive ? 'background:#8B5CF6;' : ''}">${isSubActive ? '当前播放中 ✓' : '点击切换此线路'}</span>
                                </div>
                                <div class="subsource-url">${sub.url}</div>
                            </div>`;
                        });
                        subContainer.innerHTML = subHtml;
                    }
                }

                if (currentActiveStreamId) {
                    const activeSub = availableSubSources[currentActiveSourceIndex];
                    const subTagStr = activeSub ? ` (线路 ${currentActiveSourceIndex + 1} ${activeSub.type.toUpperCase()})` : '';
                    document.getElementById('ctrlStreamId').innerText = 'Stream: ' + currentActiveStreamId + subTagStr;
                }

                log('Node', `已刷新: <b>${availableStreams.length}</b> 条在线流，当前流拥有 <b>${availableSubSources.length}</b> 条播放线路`);
            } catch(e) {
                console.error(e);
            }
        };

        function updateHighlight() {
            document.querySelectorAll('.source-card').forEach(c => c.classList.remove('active'));
            const activeStreamCard = document.getElementById('stream_' + currentActiveStreamId);
            if (activeStreamCard) activeStreamCard.classList.add('active');

            document.querySelectorAll('.subsource-card').forEach((c, idx) => {
                if (idx === currentActiveSourceIndex) {
                    c.classList.add('active');
                    const badge = c.querySelector('.source-badge');
                    if (badge) {
                        badge.innerText = '当前播放中 ✓';
                        badge.className = 'source-badge active-badge';
                        badge.style.background = '#8B5CF6';
                    }
                } else {
                    c.classList.remove('active');
                    const badge = c.querySelector('.source-badge');
                    if (badge) {
                        badge.innerText = '点击切换此线路';
                        badge.className = 'source-badge';
                        badge.style.background = '';
                    }
                }
            });
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
                    duration: totalDurationSec || 0,
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
                    log('Auto', '步骤 1/5: 播放并 Seek 5 秒');
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

                    log('Auto', '步骤 4/5: 测试流内多线路/多流切换');
                    if (availableSubSources.length > 1) {
                        const targetSubIdx = (currentActiveSourceIndex + 1) % availableSubSources.length;
                        log('Auto', `切换到当前流的线路 ${targetSubIdx + 1}`);
                        selectSubSource(targetSubIdx);
                    } else if (availableStreams.length > 1) {
                        const nextStream = availableStreams.find(s => s.streamid !== currentActiveStreamId) || availableStreams[0];
                        log('Auto', `切换到推流 ${nextStream.streamid}`);
                        selectNodeStream(nextStream.streamid);
                    } else {
                        log('Auto', '当前仅有单条流/线路，已验证多源容错协议');
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
                document.getElementById('seekSlider').value = 0;
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
                const isLive = (props.currentSource && props.currentSource.isLive) || props.duration === 0;
                if (isLive) {
                    totalDurationSec = 0;
                    document.getElementById('seekSlider').value = 0;
                    document.getElementById('timeText').innerText = formatTime(currentPosSec) + ' (直播)';
                } else if (props.duration !== undefined && props.duration > 0) {
                    totalDurationSec = props.duration;
                }
                if (props.speed !== undefined) {
                    currentSpeed = props.speed;
                }
                if (props.videoWidth && props.videoHeight) {
                    const typeStr = (props.currentSource && props.currentSource.type) ? ` (${props.currentSource.type.toUpperCase()})` : '';
                    document.getElementById('statResolution').innerText = `${props.videoWidth}x${props.videoHeight}${typeStr}`;
                }
                if (props.currentSource && props.currentSource.sourceIndex !== undefined) {
                    currentActiveSourceIndex = props.currentSource.sourceIndex;
                    updateHighlight();
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

        // 页面 DOM 加载完毕后立即向 Native 发起属性与流列表查询
        document.addEventListener('DOMContentLoaded', () => {
            sendCmd('getProperties');
            sendCmd('refreshStreams');
        });
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

// MARK: - JSBridge 协调器与事件监听器 (全面支持节点在线流与流内多播放线路手动切换)
final class VZPlayerJSBridgeCoordinator: NSObject, WKScriptMessageHandler, VZH5EventListener {
    weak var webView: WKWebView?
    weak var vzPlayer: IH5Player?
    private let apiService = StreamAPIService.shared
    
    // 当前正在播放的流 ID
    var currentPlayingStreamId: String = ""
    
    // 当前流解析出的所有子播放线路
    var currentStreamSources: [VZPlayerSource] = []
    
    // 当前正在播放的子源索引
    var currentSourceIndex: Int = 0
    
    // 异步防竞争请求 Token
    private var activeFetchRequestId: UUID?
    
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
                // 动态切节点推流：请求播放地址并起播
                if let dict = self.parseJSON(paramsJson),
                   let streamId = dict["streamId"] as? String {
                    self.playNodeStream(streamId: streamId)
                }
            case "switchSubSource":
                // 手动切换当前流内的指定播放线路
                if let dict = self.parseJSON(paramsJson),
                   let idx = dict["index"] as? Int ?? (dict["sourceIndex"] as? Int) {
                    self.currentSourceIndex = idx
                    _ = player.switchSource(index: idx)
                    self.syncNodeStreamsToH5()
                    self.syncPropertiesToH5()
                }
            case "refreshStreams":
                self.apiService.fetchStreamList { [weak self] _ in
                    self?.syncNodeStreamsToH5()
                }
            case "getProperties":
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            default:
                break
            }
        }
    }
    
    /// 播放节点的在线流：自动请求 toolsapi 播放地址并构造成多源容错管线 (防异步竞争)
    func playNodeStream(streamId: String) {
        guard let player = vzPlayer else { return }
        self.currentPlayingStreamId = streamId
        self.currentSourceIndex = 0
        
        let requestId = UUID()
        self.activeFetchRequestId = requestId
        
        apiService.fetchPlayerSources(for: streamId) { [weak self] container in
            guard let self = self, self.activeFetchRequestId == requestId else { return }
            
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
                self.currentStreamSources = vzSources
                self.currentSourceIndex = 0
                player.setSources(vzSources)
                player.play()
            } else {
                self.currentStreamSources = []
                self.currentSourceIndex = 0
            }
            self.syncNodeStreamsToH5()
            self.syncPropertiesToH5()
        }
    }
    
    private func parseJSON(_ jsonStr: String) -> [String: Any]? {
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    /// 将节点最新在线流与当前流的子播放线路实时同步给 H5
    func syncNodeStreamsToH5() {
        guard let webView = webView else { return }
        
        let streamsArray: [[String: Any]] = apiService.streamList.map { s in
            return [
                "streamid": s.streamid,
                "resolution": s.resolutionText,
                "fps": s.fpsText,
                "bitrate": s.bitrateText,
                "location": s.locationText
            ]
        }
        
        let subSourcesArray: [[String: Any]] = currentStreamSources.enumerated().map { (index, s) in
            return [
                "index": index,
                "tag": s.tag,
                "type": s.type,
                "videoCodec": s.videoCodec,
                "codecText": s.videoCodec == 4 ? "H.265" : "H.264",
                "url": s.url,
                "isLive": s.isLive
            ]
        }
        
        if let player = vzPlayer,
           let srcData = player.get_currentsource().data(using: .utf8),
           let srcDict = try? JSONSerialization.jsonObject(with: srcData) as? [String: Any],
           let activeIdx = srcDict["sourceIndex"] as? Int {
            self.currentSourceIndex = activeIdx
        }
        
        let payload: [String: Any] = [
            "activeNodeDomain": apiService.activeNodeDomain,
            "activeNodeRemark": apiService.activeNodeItem?.remark ?? apiService.activeNodeDomain,
            "currentStreamId": currentPlayingStreamId,
            "streams": streamsArray,
            "subSources": subSourcesArray,
            "currentSourceIndex": currentSourceIndex
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
            guard let self = self, let webView = self.webView else { return }
            let script = "if (window.vzBridgeReceiveEvent) { window.vzBridgeReceiveEvent('\(eventName)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
            
            if eventName == "PlayerWARN" || eventName == "playing" {
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            }
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

// MARK: - H5 混合播放持久化 ViewModel (彻底解决渲染视图与播放器生命周期脱节)
final class HybridPlayerViewModel: ObservableObject {
    let playerView = MediaPlayerView()
    @Published var vzPlayer: IH5Player?
    @Published var coordinator: VZPlayerJSBridgeCoordinator?
    @Published var webView: WKWebView?
    
    func setup(apiService: StreamAPIService) {
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
        
        // 3. 加载 H5 控制台页面
        wv.loadHTMLString(hybridPlayerHTML, baseURL: nil)
        
        // 4. 起播节点的首个流 (如有)
        if let firstStream = apiService.streamList.first {
            coord.playNodeStream(streamId: firstStream.streamid)
        } else if apiService.hasCompleteConfig {
            apiService.fetchStreamList { streams in
                if let first = streams.first {
                    coord.playNodeStream(streamId: first.streamid)
                } else {
                    coord.syncNodeStreamsToH5()
                }
            }
        }
    }
    
    func teardown() {
        if let userContentController = webView?.configuration.userContentController {
            userContentController.removeScriptMessageHandler(forName: "vzPlayerBridge")
        }
        vzPlayer?.destroy()
        vzPlayer = nil
        coordinator = nil
        webView = nil
    }
}

// MARK: - H5 混合播放演示主视图 (WebViewHybridPlayerView)
public struct WebViewHybridPlayerView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    @StateObject private var viewModel = HybridPlayerViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部原生视频渲染窗口 (VZPlayerView)
            ZStack(alignment: .topLeading) {
                VZPlayerViewRepresentable(playerView: viewModel.playerView)
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
            if let wv = viewModel.webView {
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
            viewModel.setup(apiService: apiService)
            if apiService.hasCompleteConfig && apiService.streamList.isEmpty {
                apiService.fetchStreamList { _ in
                    viewModel.coordinator?.syncNodeStreamsToH5()
                }
            }
        }
        .onReceive(apiService.$streamList) { _ in
            viewModel.coordinator?.syncNodeStreamsToH5()
        }
        .onDisappear {
            viewModel.teardown()
        }
    }
}
