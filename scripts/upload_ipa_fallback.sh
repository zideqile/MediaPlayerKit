#!/usr/bin/env bash
# ==============================================================================
# scripts/upload_ipa_fallback.sh
#
# 兜底分发上传脚本：
# 当 GitHub Actions 线上自动上传步骤失败或跳过时，
# 本脚本可从 GitHub CI 下载最新的 MediaPlayerKitDemo-iOS.ipa 并转传至目标分发服务器。
#
# 注意：本脚本不硬编码上传地址或 Token，统一从环境变量或项目根目录 .github_token 读取。
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. 加载本地凭据与环境变量配置 (若存在)
if [ -f "$PROJECT_ROOT/.github_token" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/.github_token"
fi

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-zideqile}"
GITHUB_REPO="${GITHUB_REPO:-MediaPlayerKit}"
IOS_APP_UPLOAD_URL="${IOS_APP_UPLOAD_URL:-}"

# 2. 参数解析
TARGET_RUN_ID=""
FORCE_UPLOAD=false

for arg in "$@"; do
  case "$arg" in
    --force|-f)
      FORCE_UPLOAD=true
      ;;
    --help|-h)
      echo "用法: $0 [RUN_ID] [--force]"
      echo "示例:"
      echo "  $0                  # 检查最新 CI 构建，若线上上传未成功则执行兜底下载转传"
      echo "  $0 --force          # 强制从最新 CI 构建下载产物并重新上传"
      echo "  $0 34329827865      # 指定构建 Run ID 执行兜底"
      exit 0
      ;;
    *)
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        TARGET_RUN_ID="$arg"
      fi
      ;;
  esac
done

# 3. 校验必要环境变量
if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ 错误: 未设置 GITHUB_TOKEN，无法通过 GitHub API 获取构建产物。"
  echo "请在环境变量中导出 GITHUB_TOKEN 或在项目根目录创建 .github_token 文件。"
  exit 1
fi

if [ -z "$IOS_APP_UPLOAD_URL" ]; then
  echo "❌ 错误: 未设置 IOS_APP_UPLOAD_URL，无法上传到目标服务器。"
  echo "请在环境变量中导出 IOS_APP_UPLOAD_URL 或在 .github_token 中配置。"
  exit 1
fi

# 4. 获取目标 Workflow Run ID
if [ -z "$TARGET_RUN_ID" ]; then
  echo "🔍 正在从 GitHub 查询最新一次 CI 构建记录..."
  TARGET_RUN_ID=$(curl -s --max-time 15 \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/actions/runs?branch=main&per_page=1" \
    | jq -r '.workflow_runs[0].id // empty')
  
  if [ -z "$TARGET_RUN_ID" ]; then
    echo "❌ 未能获取到 main 分支的 CI 构建记录。"
    exit 1
  fi
fi

echo "📦 目标构建 Run ID: $TARGET_RUN_ID"

# 5. 检查线上是否已上传成功（若非强制模式）
if [ "$FORCE_UPLOAD" = false ]; then
  UPLOAD_STEP_CONCLUSION=$(curl -s --max-time 15 \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/actions/runs/$TARGET_RUN_ID/jobs" \
    | jq -r '.jobs[0].steps[] | select(.name == "Upload IPA to Remote Distribution Server") | .conclusion // "unknown"')

  if [ "$UPLOAD_STEP_CONCLUSION" = "success" ]; then
    echo "✅ 经检查，线上构建已在 CI 流水线中自动上传成功！"
    echo "如需强制重新下载并二次转传，请附加参数: $0 $TARGET_RUN_ID --force"
    exit 0
  else
    echo "⚠️ 线上上传步骤状态为 [$UPLOAD_STEP_CONCLUSION]，立即启动本地兜底转传流程..."
  fi
else
  echo "⚡ 强制模式已开启，直接执行下载转传流程..."
fi

# 6. 查询构建产物 (Artifacts)
echo "📥 正在获取构建产物列表..."
ARTIFACT_INFO=$(curl -s --max-time 15 \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/actions/runs/$TARGET_RUN_ID/artifacts" \
  | jq -r '.artifacts[] | select(.name == "MediaPlayerKitDemo-iOS") | {id, size_in_bytes, archive_download_url} | @base64')

if [ -z "$ARTIFACT_INFO" ]; then
  echo "❌ 错误: 在构建 #$TARGET_RUN_ID 中未找到 MediaPlayerKitDemo-iOS 构建产物！"
  exit 1
fi

DOWNLOAD_URL=$(echo "$ARTIFACT_INFO" | base64 -d | jq -r '.archive_download_url')

# 7. 创建临时目录并下载解压
TMP_DIR=$(mktemp -d -t mpk_ipa_fallback_XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "⬇️ 正在从 GitHub 下载 IPA 归档包..."
curl -s -L --max-time 300 \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$DOWNLOAD_URL" -o "$TMP_DIR/artifact.zip"

echo "📂 正在解压产物..."
unzip -q "$TMP_DIR/artifact.zip" -d "$TMP_DIR/extracted"

IPA_FILE="$TMP_DIR/extracted/MediaPlayerKitDemo-iOS.ipa"
if [ ! -f "$IPA_FILE" ]; then
  echo "❌ 错误: 解压后未找到 MediaPlayerKitDemo-iOS.ipa 文件！"
  exit 1
fi

IPA_SIZE=$(ls -lh "$IPA_FILE" | awk '{print $5}')
echo "✅ 成功获取 IPA 文件，大小: $IPA_SIZE"

# 8. 上传至目标分发服务器
echo "🚀 正在上传至远程分发服务器 (兜底通道)..."
HTTP_RESPONSE=$(curl -s --connect-timeout 30 --retry 3 --retry-delay 2 -w "\n%{http_code}" \
  -X POST "$IOS_APP_UPLOAD_URL" \
  -F "file=@$IPA_FILE")

HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')

echo "服务器响应内容: $RESPONSE_BODY"
echo "HTTP 响应状态码: $HTTP_STATUS"

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "🎉 兜底上传成功 (HTTP $HTTP_STATUS)！"
else
  echo "❌ 兜底上传失败，HTTP 状态码: $HTTP_STATUS"
  exit 1
fi
