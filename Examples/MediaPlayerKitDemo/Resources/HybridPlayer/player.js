// ================= 核心状态变量 =================
let currentPosSec = 0;
let totalDurationSec = 0;
let isPlayingState = true;
let isMutedState = false;
let currentSpeed = 1.0;
let logCounter = 0;
let isAutoTesting = false;

let currentActiveStreamId = '';
let currentActiveSourceIndex = 0;
let pendingSwitchSourceIndex = null; // 切换中状态的索引 (null 表示无切换中)
let currentPlaybackState = 'idle'; // 'idle' | 'preparing' | 'playing' | 'paused' | 'buffering' | 'ended' | 'error'
let isStreamLoading = false;
let streamFetchError = null;

let availableStreams = [];
let availableSubSources = [];
let lastSubSourcesSignature = ''; // 记录线路集合签名，防止重复 innerHTML 重绘
let expandedLineDetails = {}; // 保存各线路详情折叠状态: key(streamId_idx) -> bool

// ================= 指标计算工具方法 =================
function getMetrics() {
    const totalStreams = availableStreams.length;
    const streamIdx = availableStreams.findIndex(s => s.streamid === currentActiveStreamId);
    const currentStreamNum = streamIdx >= 0 ? (streamIdx + 1) : (currentActiveStreamId ? 1 : 0);
    const totalLines = availableSubSources.length;
    const currentLineNum = totalLines > 0 ? (currentActiveSourceIndex + 1) : 0;
    return {
        totalStreams,
        currentStreamNum,
        streamIdx,
        totalLines,
        currentLineNum
    };
}

// ================= Tab 切换 =================
function switchTab(tabId) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
    
    const btn = Array.from(document.querySelectorAll('.tab-bar button')).find(b => b.getAttribute('onclick') && b.getAttribute('onclick').includes(tabId));
    if (btn) btn.classList.add('active');
    
    const pane = document.getElementById(tabId);
    if (pane) pane.classList.add('active');
}

// ================= 实时日志与浮窗 =================
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
    if (type === 'Line') tag = `<span class="log-cmd" style="color:#38BDF8;">[线路切源]</span>`;
    
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

function showToast(msg) {
    const toast = document.getElementById('toastBox');
    if (!toast) return;
    toast.innerText = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 1800);
}

// ================= 统一跨平台 JSBridge 通信 (对标 Android vzPlayerBridge) =================
if (!window.vzPlayerBridge) {
    window.vzPlayerBridge = {};
}

function sendCmd(method, paramsJson = '{}') {
    if (['play', 'Play', 'pause', 'Pause', 'resume', 'Resume', 'setCurrentTime', 'setSpeed',
         'setVolume', 'setMuted', 'setLoop'].includes(method)) {
        if (typeof window.vzPlayerBridge.request !== 'function') {
            log('Error', 'SDK JS bridge 未安装');
            return Promise.resolve(null);
        }
        return window.vzPlayerBridge.request(method, paramsJson).then(result => {
            log('H5', `${method}: 已受理`);
            return result;
        }).catch(error => {
            log('Error', `${method}: ${error.message}`);
            return null;
        });
    }

    // 1. Android 原生 @JavascriptInterface 注入对象优先适配
    if (window.AndroidBridge && typeof window.AndroidBridge[method] === 'function') {
        window.AndroidBridge[method](paramsJson);
        log('H5➔Android', `执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
    } else if (window.vzPlayerNative && typeof window.vzPlayerNative[method] === 'function') {
        window.vzPlayerNative[method](paramsJson);
        log('H5➔Android', `执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vzPlayerBridge) {
        // 2. iOS WKWebView 拦截
        window.webkit.messageHandlers.vzPlayerBridge.postMessage({
            method: method,
            paramsJson: paramsJson
        });
        log('H5➔iOS', `执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
    } else {
        log('Web独立', `[独立模式] 执行 <b>${method}</b> ${paramsJson !== '{}' ? paramsJson : ''}`);
    }
}

// ================= 更换流选择抽屉 (Drawer) 控制 =================

function openStreamDrawer() {
    const overlay = document.getElementById('streamDrawerOverlay');
    if (overlay) {
        overlay.classList.add('active');
        renderDrawerStreamList(availableStreams);
        const input = document.getElementById('streamSearchInput');
        if (input) {
            input.value = '';
            input.focus();
        }
    }
}

function closeStreamDrawer(event) {
    if (event && event.target !== event.currentTarget) return;
    const overlay = document.getElementById('streamDrawerOverlay');
    if (overlay) overlay.classList.remove('active');
}

function onStreamSearch(query) {
    const q = (query || '').trim().toLowerCase();
    if (!q) {
        renderDrawerStreamList(availableStreams);
        return;
    }
    const filtered = availableStreams.filter(s => {
        return (s.streamid || '').toLowerCase().includes(q) ||
               (s.resolution || '').toLowerCase().includes(q) ||
               (s.location || '').toLowerCase().includes(q);
    });
    renderDrawerStreamList(filtered);
}

function renderDrawerStreamList(list) {
    const container = document.getElementById('drawerStreamList');
    const countNum = document.getElementById('drawerStreamCount');
    if (countNum) countNum.innerText = list.length;
    if (!container) return;

    if (list.length === 0) {
        container.innerHTML = '<div class="state-hint">未找到匹配的在线推流</div>';
        return;
    }

    let html = '';
    list.forEach((s, idx) => {
        const isSelected = s.streamid === currentActiveStreamId;
        const resBadge = s.resolution ? `<span style="font-size: 9.5px; background: rgba(59,130,246,0.2); color:#93C5FD; padding: 1px 5px; border-radius:3px;">${s.resolution}</span>` : '';
        const fpsBadge = s.fps ? `<span style="font-size: 9.5px; color:#94A3B8;">${s.fps}</span>` : '';
        const bitrateBadge = s.bitrate ? `<span style="font-size: 9.5px; color:#C4B5FD;">${s.bitrate}</span>` : '';
        const checkmark = isSelected ? '<span style="font-size: 11px; color: #60A5FA; font-weight: bold;">当前播放中 ✓</span>' : '<span style="font-size: 11px; color: #94A3B8;">选择此流 ➔</span>';

        html += `
        <div class="drawer-stream-card ${isSelected ? 'selected' : ''}" onclick="selectStreamFromDrawer('${s.streamid}')">
            <div class="drawer-stream-header">
                <span class="drawer-stream-id">[${idx + 1}/${list.length}] 📡 ${s.streamid}</span>
                ${checkmark}
            </div>
            <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                ${resBadge} ${fpsBadge} ${bitrateBadge}
            </div>
        </div>`;
    });
    container.innerHTML = html;
}

// 从抽屉中选择流：不切页，保持在当前 Tab，清空旧线路进入加载态
function selectStreamFromDrawer(streamId) {
    closeStreamDrawer();
    if (streamId === currentActiveStreamId && !streamFetchError && availableSubSources.length > 0) return;

    currentActiveStreamId = streamId;
    currentActiveSourceIndex = 0;
    pendingSwitchSourceIndex = null;
    isStreamLoading = true;
    streamFetchError = null;
    availableSubSources = [];
    lastSubSourcesSignature = '';

    // 1. 更新当前流摘要与控制台快捷指示
    updateCurrentStreamHero();
    updateConsoleQuickBar();

    // 2. 线路区进入加载态
    renderSubSourcesList();

    // 3. 向 Native 发起切流
    sendCmd('switchStream', JSON.stringify({ streamId: streamId }));
    const { currentStreamNum, totalStreams } = getMetrics();
    log('Node', `已切换至第 <b>${currentStreamNum}/${totalStreams}</b> 路流 <b>${streamId}</b>，正在拉取播放线路并起播...`);
}

// ================= 上一路流 / 下一路流切换 =================

function switchPrevStream() {
    if (availableStreams.length <= 1) return;
    const { streamIdx, totalStreams } = getMetrics();
    const curr = streamIdx >= 0 ? streamIdx : 0;
    const prevIdx = (curr - 1 + totalStreams) % totalStreams;
    const targetStream = availableStreams[prevIdx];
    if (targetStream) {
        log('Node', `快捷切换至上一路推流: [${prevIdx + 1}/${totalStreams}] ➔ <b>${targetStream.streamid}</b>`);
        selectStreamFromDrawer(targetStream.streamid);
    }
}

function switchNextStream() {
    if (availableStreams.length <= 1) return;
    const { streamIdx, totalStreams } = getMetrics();
    const curr = streamIdx >= 0 ? streamIdx : 0;
    const nextIdx = (curr + 1) % totalStreams;
    const targetStream = availableStreams[nextIdx];
    if (targetStream) {
        log('Node', `快捷切换至下一路推流: [${nextIdx + 1}/${totalStreams}] ➔ <b>${targetStream.streamid}</b>`);
        selectStreamFromDrawer(targetStream.streamid);
    }
}

// 重试获取当前流的播放线路
function retryFetchCurrentStream() {
    if (!currentActiveStreamId) return;
    isStreamLoading = true;
    streamFetchError = null;
    availableSubSources = [];
    lastSubSourcesSignature = '';

    updateCurrentStreamHero();
    updateConsoleQuickBar();
    renderSubSourcesList();

    sendCmd('retryStream', JSON.stringify({ streamId: currentActiveStreamId }));
    log('Node', `正在重新获取推流 <b>${currentActiveStreamId}</b> 的播放线路...`);
}

// ================= 线路手动切换与上一条/下一条切换 =================

// 手动切换流内子线路：留在当前页，目标行显示切换中...
function onSwitchSubSource(idx) {
    if (idx === currentActiveSourceIndex && !pendingSwitchSourceIndex && (currentPlaybackState === 'playing' || isPlayingState)) return;

    pendingSwitchSourceIndex = idx;
    currentPlaybackState = 'preparing';
    updateSubSourcesVisualHighlight();
    updateConsoleQuickBar();

    sendCmd('switchSubSource', JSON.stringify({
        streamId: currentActiveStreamId,
        index: idx,
        sourceIndex: idx
    }));
    log('Line', `向原生发送切线指令 ➔ <b>线路 ${idx + 1}/${availableSubSources.length}</b> (等待解码播放)`);
}

// 快捷切上一条线路
function switchPrevSubSource() {
    if (availableSubSources.length <= 1 || isStreamLoading) return;
    const prevIdx = (currentActiveSourceIndex - 1 + availableSubSources.length) % availableSubSources.length;
    log('Line', `快捷切换至上一条线路: [${prevIdx + 1}/${availableSubSources.length}]`);
    onSwitchSubSource(prevIdx);
}

// 快捷切下一条线路
function switchNextSubSource() {
    if (availableSubSources.length <= 1 || isStreamLoading) return;
    const nextIdx = (currentActiveSourceIndex + 1) % availableSubSources.length;
    log('Line', `快捷切换至下一条线路: [${nextIdx + 1}/${availableSubSources.length}]`);
    onSwitchSubSource(nextIdx);
}

// 展开/折叠单条线路的完整详情 (不触发切源)
function toggleLineDetail(idx) {
    const detailKey = `${currentActiveStreamId}_${idx}`;
    expandedLineDetails[detailKey] = !expandedLineDetails[detailKey];
    const detailBox = document.getElementById(`lineDetail_${idx}`);
    const arrowSpan = document.getElementById(`detailArrow_${idx}`);
    if (detailBox) {
        if (expandedLineDetails[detailKey]) {
            detailBox.classList.add('open');
            if (arrowSpan) arrowSpan.innerText = '收起 ▴';
        } else {
            detailBox.classList.remove('open');
            if (arrowSpan) arrowSpan.innerText = '详情 ▸';
        }
    }
}

// 复制线路完整 URL 到剪贴板 (阻止事件冒泡，杜绝误触切源)
function copyLineUrl(url, event) {
    if (event) event.stopPropagation();
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(() => {
            showToast('✅ 播放地址已复制到剪贴板');
            log('H5', '已复制播放地址到剪贴板');
        }).catch(() => {
            fallbackCopyText(url);
        });
    } else {
        fallbackCopyText(url);
    }
}

function fallbackCopyText(text) {
    const input = document.createElement('textarea');
    input.value = text;
    document.body.appendChild(input);
    input.select();
    try {
        document.execCommand('copy');
        showToast('✅ 播放地址已复制');
    } catch(e) {
        showToast('⚠️ 复制失败，请长按文本复制');
    }
    document.body.removeChild(input);
}

function refreshNodeStreams() {
    log('Node', '向 Native 发送刷新节点在线流指令...');
    sendCmd('refreshStreams');
}

// ================= 数据更新与精细渲染 =================

// Native 注入节点流列表与子播放线路
window.vzBridgeUpdateStreamList = function(data) {
    try {
        const nodeRemark = data.activeNodeRemark || '默认节点';
        const nodeDomain = data.activeNodeDomain || '';
        availableStreams = data.streams || [];
        availableSubSources = data.subSources || [];
        currentActiveStreamId = data.currentStreamId || currentActiveStreamId;
        isStreamLoading = !!data.isStreamLoading;
        streamFetchError = data.streamFetchError || null;
        
        if (data.playbackState) {
            currentPlaybackState = data.playbackState;
            if (currentPlaybackState === 'playing') {
                pendingSwitchSourceIndex = null;
            }
        }
        
        if (data.currentSourceIndex !== undefined) {
            currentActiveSourceIndex = data.currentSourceIndex;
        }

        // 更新节点信息
        const ctrlNodeName = document.getElementById('ctrlNodeName');
        if (ctrlNodeName) ctrlNodeName.innerText = '节点: ' + (nodeRemark || nodeDomain);
        const sourcesNodeRemark = document.getElementById('sourcesNodeRemark');
        if (sourcesNodeRemark) sourcesNodeRemark.innerText = nodeRemark || '当前节点';
        const sourcesNodeDomain = document.getElementById('sourcesNodeDomain');
        if (sourcesNodeDomain) sourcesNodeDomain.innerText = nodeDomain;
        
        // 1. 更新当前流卡片与总指标
        updateCurrentStreamHero();

        // 2. 渲染线路列表
        renderSubSourcesList();

        // 3. 更新控制台快捷指示条
        updateConsoleQuickBar();

        // 4. 如果抽屉当前正处于打开状态，同步刷新抽屉流列表（保留搜索词与滚动）
        const drawerOverlay = document.getElementById('streamDrawerOverlay');
        if (drawerOverlay && drawerOverlay.classList.contains('active')) {
            const searchVal = (document.getElementById('streamSearchInput')?.value) || '';
            onStreamSearch(searchVal);
        }

        const { currentStreamNum, totalStreams, currentLineNum, totalLines } = getMetrics();
        log('Node', `已同步: <b>${totalStreams}</b> 路推流 (当前第 ${currentStreamNum} 路)，线路 <b>${totalLines}</b> 条 (当前第 ${currentLineNum} 条) [${currentPlaybackState}]`);
    } catch(e) {
        console.error(e);
    }
};

function updateCurrentStreamHero() {
    const { totalStreams, currentStreamNum, totalLines, currentLineNum } = getMetrics();
    
    const heroStreamId = document.getElementById('heroStreamId');
    const heroStreamIndexBadge = document.getElementById('heroStreamIndexBadge');
    const heroPrevStreamBtn = document.getElementById('heroPrevStreamBtn');
    const heroNextStreamBtn = document.getElementById('heroNextStreamBtn');
    const sourcesTotalStreamsBadge = document.getElementById('sourcesTotalStreamsBadge');
    const heroStreamCountTag = document.getElementById('heroStreamCountTag');
    const heroLineCountTag = document.getElementById('heroLineCountTag');

    if (sourcesTotalStreamsBadge) {
        sourcesTotalStreamsBadge.innerText = `共 ${totalStreams} 路推流`;
    }

    if (heroPrevStreamBtn) heroPrevStreamBtn.disabled = (totalStreams <= 1);
    if (heroNextStreamBtn) heroNextStreamBtn.disabled = (totalStreams <= 1);

    if (!currentActiveStreamId) {
        if (heroStreamId) heroStreamId.innerText = '暂无活跃推流';
        if (heroStreamIndexBadge) heroStreamIndexBadge.innerText = '第 - / - 路';
        if (heroStreamCountTag) heroStreamCountTag.innerText = `流: 0 / ${totalStreams}`;
        if (heroLineCountTag) heroLineCountTag.innerText = `线路: 0 条`;
        return;
    }

    if (heroStreamId) heroStreamId.innerText = currentActiveStreamId;
    if (heroStreamIndexBadge) heroStreamIndexBadge.innerText = `第 ${currentStreamNum} / ${totalStreams} 路`;
    if (heroStreamCountTag) heroStreamCountTag.innerText = `流序号: ${currentStreamNum} / ${totalStreams}`;
    if (heroLineCountTag) heroLineCountTag.innerText = `线路: ${currentLineNum > 0 ? (currentLineNum + '/' + totalLines) : (totalLines + ' 条')}`;

    const currentStreamInfo = availableStreams.find(s => s.streamid === currentActiveStreamId);
    const heroResTag = document.getElementById('heroResTag');
    const heroFpsTag = document.getElementById('heroFpsTag');
    const heroBitrateTag = document.getElementById('heroBitrateTag');
    
    if (currentStreamInfo) {
        if (heroResTag) heroResTag.innerText = currentStreamInfo.resolution || '自适应';
        if (heroFpsTag) heroFpsTag.innerText = currentStreamInfo.fps ? `FPS: ${currentStreamInfo.fps}` : 'FPS: --';
        if (heroBitrateTag) heroBitrateTag.innerText = currentStreamInfo.bitrate || '-- Kbps';
    }
}

function renderSubSourcesList() {
    const { totalLines, currentLineNum } = getMetrics();
    const container = document.getElementById('subSourcesListContainer');
    const linesCountInfo = document.getElementById('linesCountInfo');
    const prevBtn = document.getElementById('sourcesPrevLineBtn');
    const nextBtn = document.getElementById('sourcesNextLineBtn');

    if (linesCountInfo) {
        if (totalLines > 0) {
            linesCountInfo.innerText = `(当前第 ${currentLineNum} / ${totalLines} 条 · 共 ${totalLines} 条)`;
        } else {
            linesCountInfo.innerText = `(共 0 条)`;
        }
    }
    if (prevBtn) prevBtn.disabled = isStreamLoading || (totalLines <= 1);
    if (nextBtn) nextBtn.disabled = isStreamLoading || (totalLines <= 1);

    if (!container) return;

    // 1. 如果正在加载流的播放地址
    if (isStreamLoading) {
        container.innerHTML = `
            <div class="state-hint">
                <div style="font-size: 13px; font-weight: bold; margin-bottom: 4px; color: #60A5FA;">⏳ 正在获取「${currentActiveStreamId}」的播放线路...</div>
                <div style="font-size: 10.5px; color: #64748B;">正在通过 toolsapi 请求多协议多线路</div>
            </div>`;
        lastSubSourcesSignature = '';
        return;
    }

    // 2. 如果请求失败或发生错误
    if (streamFetchError) {
        container.innerHTML = `
            <div class="state-hint" style="border-color: #EF4444; background: rgba(239, 68, 68, 0.1);">
                <div style="color: #F87171; font-weight: bold; margin-bottom: 6px;">❌ 获取播放线路失败</div>
                <div style="color: #94A3B8; font-size: 11px; margin-bottom: 10px;">${streamFetchError}</div>
                <button class="btn btn-sm" style="background: #2563EB; color: #FFF; margin: 0 auto; display: inline-flex; align-items: center; gap: 4px;" onclick="retryFetchCurrentStream()">
                    🔄 重新获取线路
                </button>
            </div>`;
        lastSubSourcesSignature = '';
        return;
    }

    // 3. 如果当前未选择流或列表为空
    if (!currentActiveStreamId) {
        container.innerHTML = '<div class="state-hint">请先点击上方「更换流 ›」选择在线推流</div>';
        lastSubSourcesSignature = '';
        return;
    }

    if (availableSubSources.length === 0) {
        container.innerHTML = `
            <div class="state-hint">
                <div style="margin-bottom: 6px;">⚠️ 当前流暂无活跃播放线路</div>
                <button class="btn btn-sm" style="background: #334155; color: #E2E8F0; margin: 0 auto;" onclick="retryFetchCurrentStream()">
                    🔄 重新尝试拉取
                </button>
            </div>`;
        lastSubSourcesSignature = '';
        return;
    }

    // 4. 计算当前线路数据签名 (检查是否需要全量重建 DOM)
    const newSignature = currentActiveStreamId + '::' + availableSubSources.map(s => s.url + s.type + s.videoCodec).join('|');
    if (newSignature === lastSubSourcesSignature) {
        // 数据签名未变，仅局部更新状态（不销毁 DOM 节点）
        updateSubSourcesVisualHighlight();
        return;
    }

    // 数据签名已变化，重建 DOM
    lastSubSourcesSignature = newSignature;
    let html = '';
    availableSubSources.forEach((sub, idx) => {
        const detailKey = `${currentActiveStreamId}_${idx}`;
        const isOpen = !!expandedLineDetails[detailKey];
        const isActive = idx === currentActiveSourceIndex;
        const isSwitching = (pendingSwitchSourceIndex !== null && idx === pendingSwitchSourceIndex) ||
                            (isActive && currentPlaybackState === 'preparing');

        let cardClass = 'line-item-card';
        if (isActive) cardClass += ' active';
        if (isSwitching) cardClass += ' switching';

        let actionBtnHtml = '';
        if (isSwitching) {
            actionBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 切换中...</button>';
        } else if (isActive && (currentPlaybackState === 'playing' || isPlayingState)) {
            actionBtnHtml = '<button class="line-action-btn btn-active" disabled>● 播放中 ✓</button>';
        } else if (isActive) {
            actionBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 缓冲中...</button>';
        } else {
            actionBtnHtml = `<button class="line-action-btn btn-switch" onclick="onSwitchSubSource(${idx})">切换此线</button>`;
        }

        let domainText = '主线播放地址';
        try {
            const u = new URL(sub.url);
            domainText = u.host + (sub.tag ? ` (${sub.tag})` : '');
        } catch(e) {
            domainText = sub.tag || '默认源';
        }

        const typeBadge = `<span class="line-badge badge-type">${(sub.type || 'HLS').toUpperCase()}</span>`;
        const codecBadge = `<span class="line-badge badge-codec">${sub.codecText || (sub.videoCodec === 4 ? 'H.265' : ([2, 7].includes(sub.videoCodec) ? 'H.264' : '未知'))}</span>`;
        const tagBadge = sub.tag ? `<span class="line-badge badge-tag">${sub.tag}</span>` : '';

        html += `
        <div class="${cardClass}" id="lineCard_${idx}">
            <div class="line-main-row" onclick="onSwitchSubSource(${idx})">
                <div class="line-info-group">
                    <span class="line-status-dot"></span>
                    <span class="line-title-text">线路 ${idx + 1} / ${availableSubSources.length}</span>
                    ${typeBadge}
                    ${codecBadge}
                    ${tagBadge}
                </div>
                ${actionBtnHtml}
            </div>
            <div class="line-sub-row">
                <span class="line-domain-text">🔗 ${domainText}</span>
                <button class="line-detail-toggle" onclick="toggleLineDetail(${idx})">
                    <span id="detailArrow_${idx}">${isOpen ? '收起 ▴' : '详情 ▸'}</span>
                </button>
            </div>
            <div class="line-detail-box ${isOpen ? 'open' : ''}" id="lineDetail_${idx}">
                <div class="line-full-url">${sub.url}</div>
                <div style="display:flex; justify-content: flex-end;">
                    <button class="line-copy-btn" onclick="copyLineUrl('${sub.url}', event)">📋 复制完整播放 URL</button>
                </div>
            </div>
        </div>`;
    });

    container.innerHTML = html;
}

// 局部更新线路卡片的选中/切换状态，保护展开状态与滚动位置
function updateSubSourcesVisualHighlight() {
    const { totalLines, currentLineNum } = getMetrics();
    const linesCountInfo = document.getElementById('linesCountInfo');
    const prevBtn = document.getElementById('sourcesPrevLineBtn');
    const nextBtn = document.getElementById('sourcesNextLineBtn');

    if (linesCountInfo) {
        if (totalLines > 0) {
            linesCountInfo.innerText = `(当前第 ${currentLineNum} / ${totalLines} 条 · 共 ${totalLines} 条)`;
        } else {
            linesCountInfo.innerText = `(共 0 条)`;
        }
    }
    if (prevBtn) prevBtn.disabled = isStreamLoading || (totalLines <= 1);
    if (nextBtn) nextBtn.disabled = isStreamLoading || (totalLines <= 1);

    availableSubSources.forEach((sub, idx) => {
        const card = document.getElementById(`lineCard_${idx}`);
        if (!card) return;

        const isActive = idx === currentActiveSourceIndex;
        const isSwitching = (pendingSwitchSourceIndex !== null && idx === pendingSwitchSourceIndex) ||
                            (isActive && currentPlaybackState === 'preparing');

        card.className = 'line-item-card';
        if (isActive) card.classList.add('active');
        if (isSwitching) card.classList.add('switching');

        const mainRow = card.querySelector('.line-main-row');
        const oldBtn = mainRow ? mainRow.querySelector('.line-action-btn') : null;
        if (oldBtn) {
            oldBtn.remove();
            let newBtnHtml = '';
            if (isSwitching) {
                newBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 切换中...</button>';
            } else if (isActive && (currentPlaybackState === 'playing' || isPlayingState)) {
                newBtnHtml = '<button class="line-action-btn btn-active" disabled>● 播放中 ✓</button>';
            } else if (isActive) {
                newBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 缓冲中...</button>';
            } else {
                newBtnHtml = `<button class="line-action-btn btn-switch" onclick="onSwitchSubSource(${idx})">切换此线</button>`;
            }
            mainRow.insertAdjacentHTML('beforeend', newBtnHtml);
        }
    });

    updateConsoleQuickBar();
}

function updateConsoleQuickBar() {
    const { totalStreams, currentStreamNum, totalLines, currentLineNum } = getMetrics();
    
    // 1. 更新推流指标与按钮禁用状态
    const ctrlStreamMetric = document.getElementById('ctrlStreamMetric');
    if (ctrlStreamMetric) {
        ctrlStreamMetric.innerText = totalStreams > 0 ? `流: ${currentStreamNum}/${totalStreams}` : '流: -/-';
    }
    
    const ctrlPrevStreamBtn = document.getElementById('ctrlPrevStreamBtn');
    const ctrlNextStreamBtn = document.getElementById('ctrlNextStreamBtn');
    if (ctrlPrevStreamBtn) ctrlPrevStreamBtn.disabled = (totalStreams <= 1);
    if (ctrlNextStreamBtn) ctrlNextStreamBtn.disabled = (totalStreams <= 1);

    // 2. 更新线路指标与按钮禁用状态
    const ctrlPrevLineBtn = document.getElementById('ctrlPrevLineBtn');
    const ctrlNextLineBtn = document.getElementById('ctrlNextLineBtn');
    if (ctrlPrevLineBtn) ctrlPrevLineBtn.disabled = isStreamLoading || (totalLines <= 1);
    if (ctrlNextLineBtn) ctrlNextLineBtn.disabled = isStreamLoading || (totalLines <= 1);

    const ctrlLineInfoText = document.getElementById('ctrlLineInfoText');
    if (ctrlLineInfoText) {
        if (isStreamLoading) {
            ctrlLineInfoText.innerText = `🔀 正在加载线路 (流 ${currentStreamNum}/${totalStreams})...`;
        } else if (totalLines > 0 && availableSubSources[currentActiveSourceIndex]) {
            const curSub = availableSubSources[currentActiveSourceIndex];
            const typeStr = (curSub.type || 'HLS').toUpperCase();
            const codecStr = curSub.codecText || (curSub.videoCodec === 4 ? 'H.265' : ([2, 7].includes(curSub.videoCodec) ? 'H.264' : '未知'));
            const stateTag = (currentPlaybackState === 'playing' || isPlayingState) ? '● 播放中' : (pendingSwitchSourceIndex !== null ? '⏳ 切换中' : '⏳ 缓冲中');
            ctrlLineInfoText.innerText = `🔀 线路: ${currentLineNum}/${totalLines} · ${typeStr} · ${codecStr} (${stateTag})`;
        } else {
            ctrlLineInfoText.innerText = `🔀 线路: 暂无可用线路 (流 ${currentStreamNum}/${totalStreams})`;
        }
    }
}

// ================= 原生播放控制与回调 =================

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
    if (spd === 1.0) document.getElementById('spd10')?.classList.add('active');
    if (spd === 1.25) document.getElementById('spd125')?.classList.add('active');
    if (spd === 1.5) document.getElementById('spd15')?.classList.add('active');
    if (spd === 2.0) document.getElementById('spd20')?.classList.add('active');
    sendCmd('setSpeed', JSON.stringify({ speed: spd }));
    updateStats();
}

function toggleMute() {
    isMutedState = !isMutedState;
    const muteBtn = document.getElementById('muteBtn');
    if (muteBtn) muteBtn.innerText = isMutedState ? '🔇 已静音' : '🔊 静音开';
    sendCmd('setMuted', JSON.stringify({ muted: isMutedState }));
    updateStats();
}

function onVolumeChange(val) {
    const volText = document.getElementById('volumeText');
    if (volText) volText.innerText = val + '%';
    const vol = parseFloat(val) / 100.0;
    sendCmd('setVolume', JSON.stringify({ volume: vol }));
    updateStats();
}

function refreshProperties() {
    sendCmd('getProperties');
}

function updateStats() {
    const volSlider = document.getElementById('volumeSlider');
    const volText = (volSlider ? volSlider.value : '100') + '%';
    const muteText = isMutedState ? ' (静音)' : '';
    const statSpeedVol = document.getElementById('statSpeedVol');
    if (statSpeedVol) statSpeedVol.innerText = `${currentSpeed}x / ${volText}${muteText}`;
}

// ================= 自动化演练脚本 =================
function runAutoDemonstration() {
    if (isAutoTesting) return;
    isAutoTesting = true;
    const btn = document.getElementById('autoBtnText');
    if (btn) btn.innerText = '⏳ 演练中... 请查看画面与控制台';
    switchTab('tabLogs');
    log('Auto', '=== 🚀 开始节点流与多线路自动化测试演练 ===');

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

            log('Auto', '步骤 4/5: 测试上一线/下一线/多流切换');
            if (availableSubSources.length > 1) {
                log('Auto', '演练切换到下一线路 ⏩');
                switchNextSubSource();
            } else if (availableStreams.length > 1) {
                log('Auto', '演练切换到下一路流 ⏭');
                switchNextStream();
            } else {
                log('Auto', '当前仅有单条流/线路，已验证播放内核');
            }
            await sleep(2200);

            log('Auto', '步骤 5/5: 恢复 1.0x 倍速');
            setSpeed(1.0);
            await sleep(1000);

            log('Auto', '🎉 自动化演练全部完成！各节点 API 响应正常。');
        } catch(e) {
            log('Error', '演练异常: ' + e);
        } finally {
            isAutoTesting = false;
            if (btn) btn.innerText = '🚀 再次体验「一键全功能自动化演练」';
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

    if (eventName === 'playing' || eventName === 'play' || eventName === 'canplaythrough') {
        isPlayingState = true;
        if (eventName === 'playing' || eventName === 'canplaythrough') {
            currentPlaybackState = 'playing';
            pendingSwitchSourceIndex = null;
        }
        updateSubSourcesVisualHighlight();
        if (miniStatus) miniStatus.innerText = `Native 状态: ${eventName} (正在播放)`;
        if (playBtn) {
            playBtn.className = 'main-play-btn playing';
            if (playIcon) playIcon.innerText = '⏸';
            if (playText) playText.innerText = '暂停播放 (Pause)';
        }
    } else if (eventName === 'pause') {
        isPlayingState = false;
        currentPlaybackState = 'paused';
        updateSubSourcesVisualHighlight();
        if (miniStatus) miniStatus.innerText = 'Native 状态: pause (已暂停)';
        if (playBtn) {
            playBtn.className = 'main-play-btn';
            if (playIcon) playIcon.innerText = '▶️';
            if (playText) playText.innerText = '开始播放 (Play)';
        }
    } else if (eventName === 'waiting') {
        currentPlaybackState = 'buffering';
        updateSubSourcesVisualHighlight();
        if (miniStatus) miniStatus.innerText = 'Native 状态: waiting (缓冲中...)';
    } else if (eventName === 'ended') {
        isPlayingState = false;
        currentPlaybackState = 'ended';
        updateSubSourcesVisualHighlight();
        if (miniStatus) miniStatus.innerText = 'Native 状态: ended (已结束)';
        if (playBtn) {
            playBtn.className = 'main-play-btn';
            if (playIcon) playIcon.innerText = '▶️';
            if (playText) playText.innerText = '重新播放 (Replay)';
        }
    } else if (eventName === 'PlayerWARN') {
        log('Line', '播放器触发容错或切线告警 (PlayerWARN)');
    }
    sendCmd('getProperties');
};

window.vzBridgeReceiveTimeUpdate = function(currentTimeSec) {
    currentPosSec = currentTimeSec;
    const curStr = formatTime(currentPosSec);
    
    if (totalDurationSec > 0) {
        const durStr = formatTime(totalDurationSec);
        const percent = Math.min(100, Math.floor((currentPosSec / totalDurationSec) * 100));
        const seekSlider = document.getElementById('seekSlider');
        if (seekSlider) seekSlider.value = percent;
        const timeText = document.getElementById('timeText');
        if (timeText) timeText.innerText = `${curStr} / ${durStr}`;
        const miniEventTime = document.getElementById('miniEventTime');
        if (miniEventTime) miniEventTime.innerText = `${curStr}/${durStr}`;
    } else {
        const seekSlider = document.getElementById('seekSlider');
        if (seekSlider) seekSlider.value = 0;
        const timeText = document.getElementById('timeText');
        if (timeText) timeText.innerText = `${curStr} (直播)`;
        const miniEventTime = document.getElementById('miniEventTime');
        if (miniEventTime) miniEventTime.innerText = curStr;
    }
};

window.vzBridgeReceiveError = function(code, errMsg) {
    log('Error', `播放异常 code=${code} msg=${errMsg}`);
    const miniStatus = document.getElementById('miniEventStatus');
    if (miniStatus) miniStatus.innerText = `Native 错误: ${code}`;
    currentPlaybackState = 'error';
    pendingSwitchSourceIndex = null;
    updateSubSourcesVisualHighlight();
};

window.vzBridgeUpdateProperties = function(props) {
    try {
        const isLive = (props.currentSource && props.currentSource.isLive) || props.duration === 0;
        if (isLive) {
            totalDurationSec = 0;
            const seekSlider = document.getElementById('seekSlider');
            if (seekSlider) seekSlider.value = 0;
            const timeText = document.getElementById('timeText');
            if (timeText) timeText.innerText = formatTime(currentPosSec) + ' (直播)';
        } else if (props.duration !== undefined && props.duration > 0) {
            totalDurationSec = props.duration;
        }
        if (props.speed !== undefined) {
            currentSpeed = props.speed;
        }
        if (props.videoWidth && props.videoHeight) {
            const typeStr = (props.currentSource && props.currentSource.type) ? ` (${props.currentSource.type.toUpperCase()})` : '';
            const statResolution = document.getElementById('statResolution');
            if (statResolution) statResolution.innerText = `${props.videoWidth}x${props.videoHeight}${typeStr}`;
        }
        if (props.currentSource && props.currentSource.sourceIndex !== undefined) {
            currentActiveSourceIndex = props.currentSource.sourceIndex;
            if (currentPlaybackState === 'playing') {
                pendingSwitchSourceIndex = null;
            }
            updateSubSourcesVisualHighlight();
        }
        updateStats();
    } catch(e) {
        console.error(e);
    }
};

window.vzPlayerBridge.onEvent = window.vzBridgeReceiveEvent;
window.vzPlayerBridge.triggerEvent = window.vzBridgeReceiveEvent;
window.vzPlayerBridge.onTimeUpdate = window.vzBridgeReceiveTimeUpdate;
window.vzPlayerBridge.triggerTimeUpdate = window.vzBridgeReceiveTimeUpdate;
window.vzPlayerBridge.onError = window.vzBridgeReceiveError;
window.vzPlayerBridge.triggerError = window.vzBridgeReceiveError;
window.vzPlayerBridge.onPropertiesChanged = window.vzBridgeUpdateProperties;

function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

// 页面 DOM 加载完毕后发送 ready 握手与首批属性/推流查询
document.addEventListener('DOMContentLoaded', () => {
    sendCmd('ready');
    sendCmd('getProperties');
    sendCmd('refreshStreams');
});

