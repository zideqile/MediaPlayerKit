import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTML 嵌入式 H5 播放控制器页面模板 (流与线路中心化架构 + 独立选流抽屉 + 紧凑线路管理)
private let hybridPlayerHTML: String = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>IH5Player 节点混合控制台</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", Arial, sans-serif; -webkit-tap-highlight-color: transparent; }
        html, body { height: 100%; width: 100%; background-color: #0B0F19; color: #F8FAFC; font-size: 13px; overflow: hidden; display: flex; flex-direction: column; position: relative; }
        
        /* 1. 主内容区域容器 (置于上方，自适应占满所有可用空间) */
        .tab-content-container { flex: 1; min-height: 0; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 10px 12px; position: relative; }
        .tab-pane { display: none; height: 100%; }
        .tab-pane.active { display: flex; flex-direction: column; animation: fadeIn 0.15s ease-in-out; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(3px); } to { opacity: 1; transform: translateY(0); } }

        /* 2. 底部 Tab 导航栏 (贴近大拇指操作区，单手轻松切换) */
        .tab-bar { display: flex; background: #1E293B; border-top: 1px solid #334155; padding: 6px 6px 8px 6px; gap: 6px; flex-shrink: 0; z-index: 10; }
        .tab-btn { flex: 1; padding: 8px 2px; text-align: center; font-size: 12px; font-weight: 600; color: #94A3B8; background: transparent; border: none; border-radius: 8px; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; gap: 4px; }
        .tab-btn.active { background: #2563EB; color: #FFFFFF; font-weight: 700; box-shadow: 0 2px 8px rgba(37, 99, 235, 0.4); }
        .tab-badge { font-size: 9.5px; background: rgba(255, 255, 255, 0.25); padding: 1px 5px; border-radius: 6px; }

        /* 通用卡片 */
        .card { background: #1E293B; border-radius: 10px; padding: 10px; margin-bottom: 8px; border: 1px solid #334155; }
        
        /* 迷你实时事件横幅 */
        .mini-event-banner { background: #0F172A; border: 1px solid #3B82F6; border-radius: 8px; padding: 7px 10px; margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between; font-size: 11px; flex-shrink: 0; }
        .mini-event-text { color: #60A5FA; font-weight: 600; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        
        /* 节点与流状态指示条 */
        .node-chip { background: rgba(59, 130, 246, 0.12); border: 1px solid #3B82F6; border-radius: 8px; padding: 6px 10px; margin-bottom: 8px; font-size: 11px; }
        .node-chip-row1 { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
        .node-name { color: #93C5FD; font-weight: 700; display: flex; align-items: center; gap: 4px; }
        .node-chip-row2 { display: flex; align-items: center; justify-content: space-between; padding-top: 4px; border-top: 1px dashed rgba(59, 130, 246, 0.25); font-size: 11px; }

        /* 主播放大按钮 */
        .main-play-btn { width: 100%; height: 42px; border-radius: 10px; border: none; font-size: 14.5px; font-weight: 700; color: #FFFFFF; background: #2563EB; display: flex; align-items: center; justify-content: center; gap: 8px; cursor: pointer; margin-bottom: 8px; flex-shrink: 0; transition: all 0.15s; box-shadow: 0 4px 10px rgba(37, 99, 235, 0.35); }
        .main-play-btn.playing { background: #D97706; box-shadow: 0 4px 10px rgba(217, 119, 6, 0.35); }
        .main-play-btn:active { transform: scale(0.98); }

        /* 快捷按钮网格 */
        .btn-grid-4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 8px; flex-shrink: 0; }
        .btn { background: #334155; color: #F1F5F9; border: none; border-radius: 8px; padding: 9px 4px; font-size: 12px; font-weight: 600; cursor: pointer; text-align: center; transition: all 0.15s; display: flex; align-items: center; justify-content: center; gap: 4px; }
        .btn:active { background: #2563EB; color: #FFF; transform: scale(0.96); }
        .btn.active { background: #2563EB; color: #FFF; border: 1px solid #60A5FA; font-weight: 700; }
        .btn-sm { padding: 4px 8px; font-size: 11px; border-radius: 6px; }

        /* 滑块控制器 */
        .slider-box { background: #0F172A; border-radius: 8px; padding: 7px 10px; margin-bottom: 8px; border: 1px solid #334155; flex-shrink: 0; }
        .slider-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; font-size: 11.5px; }
        .slider-row input[type=range] { flex: 1; accent-color: #3B82F6; height: 5px; border-radius: 3px; }

        /* 属性指标网格 */
        .stat-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; font-size: 11px; margin-top: 2px; flex-shrink: 0; }
        .stat-box { background: #0F172A; padding: 6px 8px; border-radius: 6px; border: 1px solid #334155; }
        .stat-label { color: #94A3B8; font-size: 10px; margin-bottom: 2px; }
        .stat-val { font-family: ui-monospace, SFMono-Regular, monospace; font-weight: 700; color: #38BDF8; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

        /* ================= TAB 2: 流与线路专属样式 ================= */
        
        /* 当前流摘要大卡片 */
        .current-stream-hero { background: linear-gradient(135deg, #1E293B, #0F172A); border: 1.5px solid #3B82F6; border-radius: 10px; padding: 11px 12px; margin-bottom: 10px; flex-shrink: 0; box-shadow: 0 3px 10px rgba(0, 0, 0, 0.25); }
        .hero-top-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
        .hero-title-label { font-size: 10.5px; font-weight: 700; color: #93C5FD; text-transform: uppercase; letter-spacing: 0.5px; }
        .hero-switch-btn { background: #2563EB; color: #FFF; border: none; border-radius: 6px; padding: 5px 10px; font-size: 11.5px; font-weight: 700; cursor: pointer; display: flex; align-items: center; gap: 4px; transition: all 0.15s; box-shadow: 0 2px 6px rgba(37, 99, 235, 0.35); }
        .hero-switch-btn:active { transform: scale(0.96); background: #1D4ED8; }
        .hero-stream-id { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 13px; font-weight: 700; color: #FFFFFF; word-break: break-all; margin-bottom: 6px; }
        .hero-tags-row { display: flex; align-items: center; flex-wrap: wrap; gap: 5px; font-size: 10.5px; }
        .hero-tag { background: rgba(59, 130, 246, 0.18); color: #93C5FD; padding: 2px 6px; border-radius: 4px; border: 1px solid rgba(59, 130, 246, 0.3); font-weight: 600; }
        .hero-tag.live { background: rgba(16, 185, 129, 0.2); color: #34D399; border-color: rgba(16, 185, 129, 0.4); }

        /* 线路列表头部工具栏 */
        .lines-header-bar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; flex-shrink: 0; }
        .lines-title { font-size: 12px; font-weight: 700; color: #C4B5FD; display: flex; align-items: center; gap: 5px; }
        .next-line-btn { background: #4C1D95; color: #E9D5FF; border: 1px solid #7C3AED; border-radius: 6px; padding: 4px 10px; font-size: 11px; font-weight: 700; cursor: pointer; transition: all 0.15s; display: flex; align-items: center; gap: 4px; }
        .next-line-btn:active { transform: scale(0.96); background: #6D28D9; color: #FFF; }
        .next-line-btn:disabled { opacity: 0.4; cursor: not-allowed; }

        /* 紧凑型线路卡片列表 */
        .lines-list-box { display: flex; flex-direction: column; gap: 8px; }
        .line-item-card { background: #1E293B; border: 1.5px solid #334155; border-radius: 9px; padding: 9px 11px; transition: all 0.2s; }
        .line-item-card.active { border-color: #8B5CF6; background: rgba(139, 92, 246, 0.14); box-shadow: 0 0 12px rgba(139, 92, 246, 0.25); }
        .line-item-card.switching { border-color: #F59E0B; background: rgba(245, 158, 11, 0.12); }
        
        .line-main-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        .line-info-group { display: flex; align-items: center; gap: 6px; flex: 1; min-width: 0; }
        .line-status-dot { width: 8px; height: 8px; border-radius: 50%; background: #64748B; flex-shrink: 0; }
        .line-item-card.active .line-status-dot { background: #10B981; box-shadow: 0 0 6px #10B981; }
        .line-item-card.switching .line-status-dot { background: #F59E0B; animation: pulse 1s infinite alternate; }
        @keyframes pulse { from { opacity: 0.4; } to { opacity: 1; } }

        .line-title-text { font-size: 12.5px; font-weight: 700; color: #F1F5F9; white-space: nowrap; }
        .line-badge { font-size: 9.5px; font-weight: 700; padding: 2px 6px; border-radius: 4px; }
        .badge-type { background: #334155; color: #F8FAFC; }
        .badge-codec { background: rgba(139, 92, 246, 0.25); color: #DDD6FE; border: 1px solid rgba(139, 92, 246, 0.35); }
        .badge-tag { background: rgba(100, 116, 139, 0.2); color: #94A3B8; font-size: 9px; }

        /* 线路操作按钮 */
        .line-action-btn { padding: 4px 10px; border-radius: 6px; font-size: 11px; font-weight: 700; border: none; cursor: pointer; transition: all 0.15s; white-space: nowrap; }
        .line-action-btn.btn-switch { background: #334155; color: #E2E8F0; border: 1px solid #475569; }
        .line-action-btn.btn-switch:active { background: #8B5CF6; color: #FFF; transform: scale(0.96); }
        .line-action-btn.btn-active { background: #8B5CF6; color: #FFFFFF; cursor: default; box-shadow: 0 2px 6px rgba(139, 92, 246, 0.4); }
        .line-action-btn.btn-switching { background: #D97706; color: #FFFFFF; cursor: wait; }

        /* 线路第二行 (域名与详情折叠触发器) */
        .line-sub-row { display: flex; align-items: center; justify-content: space-between; margin-top: 5px; font-size: 11px; color: #94A3B8; }
        .line-domain-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: ui-monospace, SFMono-Regular, monospace; color: #CBD5E1; }
        .line-detail-toggle { background: transparent; border: none; color: #60A5FA; font-size: 11px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 2px; padding: 2px 4px; }
        .line-detail-toggle:active { opacity: 0.7; }

        /* 线路折叠详情区 */
        .line-detail-box { display: none; margin-top: 7px; padding-top: 7px; border-top: 1px dashed #334155; animation: fadeIn 0.15s ease-in-out; }
        .line-detail-box.open { display: block; }
        .line-full-url { background: #020617; border: 1px solid #334155; border-radius: 6px; padding: 6px 8px; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 10px; color: #94A3B8; word-break: break-all; margin-bottom: 6px; user-select: all; -webkit-user-select: all; }
        .line-copy-btn { background: #334155; color: #E2E8F0; border: 1px solid #475569; border-radius: 6px; padding: 4px 10px; font-size: 10.5px; font-weight: 600; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; }
        .line-copy-btn:active { background: #2563EB; color: #FFF; }

        /* ================= 独立更换流选择抽屉 (Drawer / Modal) ================= */
        .stream-drawer-overlay { display: none; position: absolute; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.75); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); z-index: 50; animation: fadeIn 0.15s ease-in-out; }
        .stream-drawer-overlay.active { display: flex; flex-direction: column; justify-content: flex-end; }
        .stream-drawer-content { background: #0F172A; border-top: 2px solid #3B82F6; border-radius: 14px 14px 0 0; padding: 12px; max-height: 88%; display: flex; flex-direction: column; box-shadow: 0 -10px 25px rgba(0, 0, 0, 0.6); animation: slideUp 0.2s ease-out; }
        @keyframes slideUp { from { transform: translateY(100%); } to { transform: translateY(0); } }

        .drawer-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; flex-shrink: 0; }
        .drawer-title { font-size: 13.5px; font-weight: 700; color: #F1F5F9; display: flex; align-items: center; gap: 6px; }
        .drawer-close-btn { background: #334155; border: none; color: #94A3B8; font-size: 13px; font-weight: bold; border-radius: 50%; width: 26px; height: 26px; cursor: pointer; display: flex; align-items: center; justify-content: center; }
        .drawer-close-btn:active { background: #EF4444; color: #FFF; }

        .drawer-search-box { margin-bottom: 8px; flex-shrink: 0; }
        .drawer-search-input { width: 100%; background: #1E293B; border: 1px solid #334155; border-radius: 8px; padding: 8px 10px; color: #FFFFFF; font-size: 12px; outline: none; }
        .drawer-search-input:focus { border-color: #3B82F6; }

        .drawer-stream-list { flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch; display: flex; flex-direction: column; gap: 7px; padding-bottom: 10px; }
        .drawer-stream-card { background: #1E293B; border: 1.5px solid #334155; border-radius: 8px; padding: 9px 11px; cursor: pointer; transition: all 0.15s; }
        .drawer-stream-card:active { transform: scale(0.98); background: rgba(59, 130, 246, 0.15); }
        .drawer-stream-card.selected { border-color: #3B82F6; background: rgba(59, 130, 246, 0.2); }
        
        .drawer-stream-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
        .drawer-stream-id { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 12px; font-weight: 700; color: #38BDF8; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 210px; }
        
        /* 状态占位提示 */
        .state-hint { text-align: center; color: #94A3B8; padding: 18px 12px; font-size: 11.5px; background: #0F172A; border-radius: 8px; border: 1px dashed #334155; }

        /* 日志盒子 */
        .log-box { background: #020617; border-radius: 8px; padding: 10px; flex: 1; min-height: 200px; overflow-y: auto; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 11px; border: 1px solid #334155; }
        .log-item { margin-bottom: 6px; line-height: 1.4; border-bottom: 1px solid rgba(51, 65, 85, 0.3); padding-bottom: 4px; }
        .log-time { color: #64748B; margin-right: 4px; }
        .log-event { color: #34D399; font-weight: bold; }
        .log-error { color: #F87171; font-weight: bold; }
        .log-cmd { color: #60A5FA; font-weight: 600; }
        .log-auto { color: #FBBF24; font-weight: bold; }

        /* 演练指南卡片 */
        .guide-box { background: linear-gradient(135deg, #1E293B, #0F172A); border: 1.5px solid #3B82F6; border-radius: 10px; padding: 14px; margin-bottom: 10px; }
        .auto-btn { width: 100%; background: linear-gradient(90deg, #2563EB, #4F46E5); color: #FFFFFF; border: none; border-radius: 8px; padding: 12px; font-size: 14px; font-weight: 700; cursor: pointer; text-align: center; box-shadow: 0 3px 8px rgba(37, 99, 235, 0.4); margin-top: 10px; }
        .auto-btn:active { transform: scale(0.98); }

        /* Toast 提示浮窗 */
        .toast { position: fixed; bottom: 65px; left: 50%; transform: translateX(-50%); background: rgba(15, 23, 42, 0.95); border: 1px solid #3B82F6; color: #FFF; padding: 6px 14px; border-radius: 20px; font-size: 11.5px; font-weight: 600; z-index: 100; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5); opacity: 0; pointer-events: none; transition: opacity 0.2s; }
        .toast.show { opacity: 1; }
    </style>
</head>
<body>

    <!-- Toast 浮窗 -->
    <div class="toast" id="toastBox">已复制到剪贴板</div>

    <!-- 1. 内容区域容器 (置于上方，垂直方向最大化展开) -->
    <div class="tab-content-container">

        <!-- ================= TAB 1: 核心控制台 ================= -->
        <div class="tab-pane active" id="tabControls">
            
            <!-- 实时事件吸顶迷你横幅 -->
            <div class="mini-event-banner">
                <div class="mini-event-text">
                    <span>⚡️</span><span id="miniEventStatus">Native 状态: preparing (准备就绪)</span>
                </div>
                <span style="font-size: 10px; color: #94A3B8;" id="miniEventTime">00:00</span>
            </div>

            <!-- 节点、推流与当前线路快捷条 -->
            <div class="node-chip">
                <div class="node-chip-row1">
                    <span class="node-name">📡 <span id="ctrlNodeName">节点: 未连接</span></span>
                    <span style="font-family: ui-monospace, monospace; font-weight: 700; color: #38BDF8;" id="ctrlStreamId">Stream: -</span>
                </div>
                <div class="node-chip-row2">
                    <span style="color: #CBD5E1;" id="ctrlLineInfoText">🔀 当前线路: 1 / 1 · HLS · H.264</span>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn btn-sm" style="background:#2563EB; color:#FFF;" onclick="switchTab('tabSources')">切线路 ›</button>
                        <button class="btn btn-sm next-line-btn" id="ctrlNextLineBtn" onclick="switchNextSubSource()">下一线 ⏩</button>
                    </div>
                </div>
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

        <!-- ================= TAB 2: 流与线路 (当前流置顶 + 线路直接可切 + 独立换流抽屉) ================= -->
        <div class="tab-pane" id="tabSources">
            
            <!-- 节点头部 -->
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; flex-shrink: 0;">
                <div style="font-size: 11.5px; color: #94A3B8;">
                    当前节点: <b style="color: #60A5FA;" id="sourcesNodeRemark">默认节点</b> (<span id="sourcesNodeDomain">-</span>)
                </div>
                <button class="btn btn-sm" onclick="refreshNodeStreams()">🔄 刷新节点</button>
            </div>

            <!-- 1. 当前流摘要置顶卡片 -->
            <div class="current-stream-hero" id="currentStreamHero">
                <div class="hero-top-row">
                    <span class="hero-title-label">📡 当前在线推流</span>
                    <button class="hero-switch-btn" onclick="openStreamDrawer()">更换流 ›</button>
                </div>
                <div class="hero-stream-id" id="heroStreamId">暂无活跃流</div>
                <div class="hero-tags-row" id="heroTagsRow">
                    <span class="hero-tag live">在线直播</span>
                    <span class="hero-tag" id="heroResTag">自适应</span>
                    <span class="hero-tag" id="heroFpsTag">V:--/A:--</span>
                    <span class="hero-tag" id="heroBitrateTag">-- Kbps</span>
                </div>
            </div>

            <!-- 2. 播放线路列表头部工具栏 -->
            <div class="lines-header-bar">
                <div class="lines-title">
                    <span>🔀 播放线路</span>
                    <span style="font-size: 11px; color: #94A3B8; font-weight: normal;">(<span id="linesCountNum">0</span> 条)</span>
                </div>
                <button class="next-line-btn" id="sourcesNextLineBtn" onclick="switchNextSubSource()">
                    <span>下一线路 ⏩</span>
                </button>
            </div>

            <!-- 3. 播放线路列表容器 (紧凑展示，完整 URL 折叠) -->
            <div class="lines-list-box" id="subSourcesListContainer">
                <div class="state-hint">⏳ 正在获取该流的可用播放线路...</div>
            </div>

        </div>

        <!-- ================= TAB 3: 实时事件流日志 ================= -->
        <div class="tab-pane" id="tabLogs">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; flex-shrink: 0;">
                <span style="font-size: 12px; color: #94A3B8;">实时记录 VZH5EventListener 广播事件：</span>
                <button class="btn btn-sm" onclick="clearLogs()">清空日志</button>
            </div>
            <div class="log-box" id="logBox">
                <div class="log-item"><span class="log-time">[Init]</span><span class="log-cmd">🚀 JSBridge 准备就绪，已建立事件与属性双向管道...</span></div>
            </div>
        </div>

        <!-- ================= TAB 4: 演练与指南 ================= -->
        <div class="tab-pane" id="tabGuide">
            <div class="guide-box">
                <div style="font-size: 13.5px; font-weight: 700; color: #60A5FA; margin-bottom: 6px;">💡 混合架构与多线路调度</div>
                <div style="font-size: 12px; color: #CBD5E1; line-height: 1.55; margin-bottom: 10px;">
                    上方视频由 <b>iOS 原生 Metal / AVPlayer</b> 硬件加速渲染；<br>
                    下方由 <b>WKWebView</b> 承载 H5 控制台。通过 <code>StreamAPIService</code> 动态拉取当前节点的在线流与真实播放地址，支持 <b>多协议 (HLS/FLV)</b>、<b>多编码 (H.264/H.265)</b> 毫秒级无缝切线与容错轮询。
                </div>
                <div style="font-size: 12.5px; font-weight: 700; color: #FBBF24; margin-bottom: 4px;">🚀 懒人体验：一键自动全流程演练</div>
                <div style="font-size: 11.5px; color: #94A3B8; margin-bottom: 8px;">
                    点击下方按钮，将全自动按顺序执行：起播首选流 ➔ Seek 5s ➔ 1.5x 倍速 ➔ 静音测试 ➔ 多线路切换 ➔ 恢复 1.0x。
                </div>
                <button class="auto-btn" onclick="runAutoDemonstration()">
                    <span id="autoBtnText">立即开始「一键全功能自动化演练」</span>
                </button>
            </div>
        </div>

        <!-- ================= 独立更换流选择抽屉 (限制在下方 H5 内，不遮视频) ================= -->
        <div class="stream-drawer-overlay" id="streamDrawerOverlay" onclick="closeStreamDrawer(event)">
            <div class="stream-drawer-content" onclick="event.stopPropagation()">
                <div class="drawer-header">
                    <div class="drawer-title">
                        <span>📡 选择在线推流</span>
                        <span style="font-size: 11px; color: #94A3B8; font-weight: normal;">(<span id="drawerStreamCount">0</span> 条可用)</span>
                    </div>
                    <button class="drawer-close-btn" onclick="closeStreamDrawer()">✕</button>
                </div>
                <div class="drawer-search-box">
                    <input type="text" class="drawer-search-input" id="streamSearchInput" placeholder="🔍 搜索 streamId 或分辨率..." oninput="onStreamSearch(this.value)">
                </div>
                <div class="drawer-stream-list" id="drawerStreamList">
                    <div class="state-hint">正在加载节点推流列表...</div>
                </div>
            </div>
        </div>

    </div>

    <!-- 2. 最下方 Tab 导航栏 (贴合大拇指操作区，单手轻松切换) -->
    <div class="tab-bar">
        <button class="tab-btn active" onclick="switchTab('tabControls')">🎮 控制台</button>
        <button class="tab-btn" onclick="switchTab('tabSources')">📺 流与线路</button>
        <button class="tab-btn" onclick="switchTab('tabLogs')">📡 实时日志<span class="tab-badge" id="logCountBadge">0</span></button>
        <button class="tab-btn" onclick="switchTab('tabGuide')">🚀 自动演练</button>
    </div>

    <script>
        // 状态变量
        let currentPosSec = 0;
        let totalDurationSec = 0;
        let isPlayingState = true;
        let isMutedState = false;
        let currentSpeed = 1.0;
        let logCounter = 0;
        let isAutoTesting = false;

        let currentActiveStreamId = '';
        let currentActiveSourceIndex = 0;
        let pendingSwitchSourceIndex = null; // 切换中状态索引
        let availableStreams = [];
        let availableSubSources = [];
        let expandedLineDetails = {}; // 保存各线路详情折叠状态 idx -> bool

        // Tab 切换
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

        // ================= 更换流选择抽屉 (Drawer) 控制 =================

        function openStreamDrawer() {
            const overlay = document.getElementById('streamDrawerOverlay');
            if (overlay) {
                overlay.classList.add('active');
                renderDrawerStreamList(availableStreams);
                document.getElementById('streamSearchInput').value = '';
                document.getElementById('streamSearchInput').focus();
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
            list.forEach(s => {
                const isSelected = s.streamid === currentActiveStreamId;
                const resBadge = s.resolution ? `<span style="font-size: 9.5px; background: rgba(59,130,246,0.2); color:#93C5FD; padding: 1px 5px; border-radius:3px;">${s.resolution}</span>` : '';
                const fpsBadge = s.fps ? `<span style="font-size: 9.5px; color:#94A3B8;">${s.fps}</span>` : '';
                const bitrateBadge = s.bitrate ? `<span style="font-size: 9.5px; color:#C4B5FD;">${s.bitrate}</span>` : '';
                const checkmark = isSelected ? '<span style="font-size: 11px; color: #60A5FA; font-weight: bold;">当前播放中 ✓</span>' : '<span style="font-size: 11px; color: #94A3B8;">选择此流 ➔</span>';

                html += `
                <div class="drawer-stream-card ${isSelected ? 'selected' : ''}" onclick="selectStreamFromDrawer('${s.streamid}')">
                    <div class="drawer-stream-header">
                        <span class="drawer-stream-id">📡 ${s.streamid}</span>
                        ${checkmark}
                    </div>
                    <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                        ${resBadge} ${fpsBadge} ${bitrateBadge}
                    </div>
                </div>`;
            });
            container.innerHTML = html;
        }

        // 从抽屉中选择流：不切页，保持在 Tab 2，清空旧线路进入加载态
        function selectStreamFromDrawer(streamId) {
            closeStreamDrawer();
            if (streamId === currentActiveStreamId) return;

            currentActiveStreamId = streamId;
            currentActiveSourceIndex = 0;
            pendingSwitchSourceIndex = null;
            availableSubSources = [];

            // 1. 更新 Tab 2 当前流摘要
            updateCurrentStreamHero();

            // 2. 线路区显示加载态
            const subContainer = document.getElementById('subSourcesListContainer');
            if (subContainer) {
                subContainer.innerHTML = '<div class="state-hint">⏳ 正在获取该流的真实播放线路...</div>';
            }

            // 3. 向 Native 发起切流
            sendCmd('switchStream', JSON.stringify({ streamId: streamId }));
            log('Node', `已切换至在线推流 <b>${streamId}</b>，正在解析播放线路并起播...`);
        }

        // ================= 线路手动切换与管理 =================

        // 手动切换流内子线路：留在当前页，目标行显示切换中...
        function onSwitchSubSource(idx) {
            if (idx === currentActiveSourceIndex) return;

            pendingSwitchSourceIndex = idx;
            updateSubSourcesVisualHighlight();

            sendCmd('switchSubSource', JSON.stringify({ index: idx, sourceIndex: idx }));
            log('Line', `向原生发送切线指令 ➔ <b>线路 ${idx + 1}</b> (等待解码播放)`);
        }

        // 快捷切下一条线路
        function switchNextSubSource() {
            if (availableSubSources.length <= 1) return;
            const nextIdx = (currentActiveSourceIndex + 1) % availableSubSources.length;
            onSwitchSubSource(nextIdx);
        }

        // 展开/折叠单条线路的完整详情 (不触发切源)
        function toggleLineDetail(idx) {
            expandedLineDetails[idx] = !expandedLineDetails[idx];
            const detailBox = document.getElementById(`lineDetail_${idx}`);
            const arrowSpan = document.getElementById(`detailArrow_${idx}`);
            if (detailBox) {
                if (expandedLineDetails[idx]) {
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
                
                if (data.currentSourceIndex !== undefined) {
                    currentActiveSourceIndex = data.currentSourceIndex;
                    pendingSwitchSourceIndex = null;
                }

                // 更新节点信息
                document.getElementById('ctrlNodeName').innerText = '节点: ' + (nodeRemark || nodeDomain);
                document.getElementById('sourcesNodeRemark').innerText = nodeRemark || '当前节点';
                document.getElementById('sourcesNodeDomain').innerText = nodeDomain;
                
                // 1. 更新当前流英雄卡片
                updateCurrentStreamHero();

                // 2. 渲染线路列表 (保留已展开的详情项)
                renderSubSourcesList();

                // 3. 更新控制台快捷指示条
                updateConsoleQuickBar();

                log('Node', `已同步: <b>${availableStreams.length}</b> 条推流，当前流含 <b>${availableSubSources.length}</b> 条播放线路`);
            } catch(e) {
                console.error(e);
            }
        };

        function updateCurrentStreamHero() {
            const heroStreamId = document.getElementById('heroStreamId');
            const heroResTag = document.getElementById('heroResTag');
            const heroFpsTag = document.getElementById('heroFpsTag');
            const heroBitrateTag = document.getElementById('heroBitrateTag');

            if (!currentActiveStreamId) {
                if (heroStreamId) heroStreamId.innerText = '暂无活跃流';
                return;
            }

            if (heroStreamId) heroStreamId.innerText = currentActiveStreamId;
            const currentStreamInfo = availableStreams.find(s => s.streamid === currentActiveStreamId);
            
            if (currentStreamInfo) {
                if (heroResTag) heroResTag.innerText = currentStreamInfo.resolution || '自适应';
                if (heroFpsTag) heroFpsTag.innerText = currentStreamInfo.fps || 'V:--/A:--';
                if (heroBitrateTag) heroBitrateTag.innerText = currentStreamInfo.bitrate || '-- Kbps';
            }
        }

        function renderSubSourcesList() {
            const container = document.getElementById('subSourcesListContainer');
            const countNum = document.getElementById('linesCountNum');
            const nextBtn = document.getElementById('sourcesNextLineBtn');
            const ctrlNextBtn = document.getElementById('ctrlNextLineBtn');

            if (countNum) countNum.innerText = availableSubSources.length;
            if (nextBtn) nextBtn.disabled = availableSubSources.length <= 1;
            if (ctrlNextBtn) ctrlNextBtn.disabled = availableSubSources.length <= 1;

            if (!container) return;

            if (!currentActiveStreamId) {
                container.innerHTML = '<div class="state-hint">请先点击上方「更换流 ›」选择在线推流</div>';
                return;
            }

            if (availableSubSources.length === 0) {
                container.innerHTML = '<div class="state-hint">⚠️ 当前流暂无可用的播放地址，请尝试刷新或更换流</div>';
                return;
            }

            let html = '';
            availableSubSources.forEach((sub, idx) => {
                const isActive = idx === currentActiveSourceIndex;
                const isSwitching = idx === pendingSwitchSourceIndex;
                const isOpen = !!expandedLineDetails[idx];

                let cardClass = 'line-item-card';
                if (isActive) cardClass += ' active';
                if (isSwitching) cardClass += ' switching';

                let actionBtnHtml = '';
                if (isActive) {
                    actionBtnHtml = '<button class="line-action-btn btn-active" disabled>● 播放中 ✓</button>';
                } else if (isSwitching) {
                    actionBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 切换中...</button>';
                } else {
                    actionBtnHtml = `<button class="line-action-btn btn-switch" onclick="onSwitchSubSource(${idx})">切换</button>`;
                }

                // 提取域名或简要路径
                let domainText = '主线播放地址';
                try {
                    const u = new URL(sub.url);
                    domainText = u.host + (sub.tag ? ` (${sub.tag})` : '');
                } catch(e) {
                    domainText = sub.tag || '默认源';
                }

                const typeBadge = `<span class="line-badge badge-type">${(sub.type || 'HLS').toUpperCase()}</span>`;
                const codecBadge = `<span class="line-badge badge-codec">${sub.codecText || 'H.264'}</span>`;
                const tagBadge = sub.tag ? `<span class="line-badge badge-tag">${sub.tag}</span>` : '';

                html += `
                <div class="${cardClass}" id="lineCard_${idx}">
                    <div class="line-main-row">
                        <div class="line-info-group">
                            <span class="line-status-dot"></span>
                            <span class="line-title-text">线路 ${idx + 1}</span>
                            ${typeBadge}
                            ${codecBadge}
                            ${tagBadge}
                        </div>
                        ${actionBtnHtml}
                    </div>
                    <div class="line-sub-row">
                        <span class="line-domain-text">${domainText}</span>
                        <button class="line-detail-toggle" onclick="toggleLineDetail(${idx})">
                            <span id="detailArrow_${idx}">${isOpen ? '收起 ▴' : '详情 ▸'}</span>
                        </button>
                    </div>
                    <div class="line-detail-box ${isOpen ? 'open' : ''}" id="lineDetail_${idx}">
                        <div class="line-full-url">${sub.url}</div>
                        <button class="line-copy-btn" onclick="copyLineUrl('${sub.url}', event)">📋 复制播放地址</button>
                    </div>
                </div>`;
            });

            container.innerHTML = html;
        }

        // 仅刷新线路高亮与操作按钮样式 (不破坏整页 DOM 与展开折叠状态)
        function updateSubSourcesVisualHighlight() {
            availableSubSources.forEach((sub, idx) => {
                const card = document.getElementById(`lineCard_${idx}`);
                if (!card) return;

                const isActive = idx === currentActiveSourceIndex;
                const isSwitching = idx === pendingSwitchSourceIndex;

                card.className = 'line-item-card' + (isActive ? ' active' : '') + (isSwitching ? ' switching' : '');
                
                const btnContainer = card.querySelector('.line-main-row');
                if (btnContainer) {
                    const oldBtn = btnContainer.querySelector('.line-action-btn');
                    if (oldBtn) oldBtn.remove();

                    let newBtnHtml = '';
                    if (isActive) {
                        newBtnHtml = '<button class="line-action-btn btn-active" disabled>● 播放中 ✓</button>';
                    } else if (isSwitching) {
                        newBtnHtml = '<button class="line-action-btn btn-switching" disabled>⏳ 切换中...</button>';
                    } else {
                        newBtnHtml = `<button class="line-action-btn btn-switch" onclick="onSwitchSubSource(${idx})">切换</button>`;
                    }
                    btnContainer.insertAdjacentHTML('beforeend', newBtnHtml);
                }
            });

            updateConsoleQuickBar();
        }

        function updateConsoleQuickBar() {
            const ctrlStreamId = document.getElementById('ctrlStreamId');
            const ctrlLineInfoText = document.getElementById('ctrlLineInfoText');
            
            if (ctrlStreamId) ctrlStreamId.innerText = 'Stream: ' + (currentActiveStreamId || '-');

            if (ctrlLineInfoText) {
                if (availableSubSources.length > 0 && availableSubSources[currentActiveSourceIndex]) {
                    const curSub = availableSubSources[currentActiveSourceIndex];
                    const typeStr = (curSub.type || 'HLS').toUpperCase();
                    const codecStr = curSub.codecText || 'H.264';
                    ctrlLineInfoText.innerText = `🔀 当前线路: ${currentActiveSourceIndex + 1} / ${availableSubSources.length} · ${typeStr} · ${codecStr}`;
                } else {
                    ctrlLineInfoText.innerText = `🔀 当前线路: 暂无可用线路`;
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

                    log('Auto', '步骤 4/5: 测试流内多线路/多流切换');
                    if (availableSubSources.length > 1) {
                        const targetSubIdx = (currentActiveSourceIndex + 1) % availableSubSources.length;
                        log('Auto', `演练切换到当前流的 线路 ${targetSubIdx + 1}`);
                        onSwitchSubSource(targetSubIdx);
                    } else if (availableStreams.length > 1) {
                        const nextStream = availableStreams.find(s => s.streamid !== currentActiveStreamId) || availableStreams[0];
                        log('Auto', `演练切换到推流 ${nextStream.streamid}`);
                        selectStreamFromDrawer(nextStream.streamid);
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
                pendingSwitchSourceIndex = null;
                updateSubSourcesVisualHighlight();
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
            } else if (eventName === 'PlayerWARN') {
                // 播放器发生内核或线路自动回退
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
                    pendingSwitchSourceIndex = null;
                    updateSubSourcesVisualHighlight();
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
            case "switchNextSubSource":
                // 切换到下一条线路
                player.sendEvent("NEXT_SOURCE", paramsJson: "{}")
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
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
