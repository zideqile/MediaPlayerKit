#!/bin/bash
# ==============================================================================
# FFmpeg 极简裁剪与 XCFramework 构建脚本 (iOS / iOS Simulator)
# 遵循 LGPL 2.1+ 开源许可，严格禁用所有 GPL 模块
# 输出包体积预估：~4.5MB
# ==============================================================================

set -e

FFMPEG_VERSION="7.0.2"
FFMPEG_SRC="ffmpeg-${FFMPEG_VERSION}"
BUILD_DIR="$(pwd)/build"
OUTPUT_DIR="$(pwd)/output"

echo "=== 开始编译精简版 FFmpeg for iOS ==="

# 1. 基础编译参数配置（白名单极简模式）
COMMON_FLAGS=(
    --enable-cross-compile
    --target-os=darwin
    --disable-everything
    --disable-programs
    --disable-doc
    --disable-avdevice
    --disable-postproc
    --disable-avfilter
    --disable-gpl
    --disable-version3
    --disable-nonfree
    --enable-avformat
    --enable-avcodec
    --enable-swresample
    --enable-hwaccel=h264_videotoolbox
    --enable-hwaccel=hevc_videotoolbox
    --enable-demuxer=mov,mp4,m4a,flv,hls,matroska,ts,aac,mp3,wav
    --enable-parser=h264,hevc,aac,opus,mp3,mpegaudio
    --enable-decoder=aac,mp3,opus,flac,pcm_s16le,pcm_f32le
    --enable-protocol=file,http,https,tcp,tls
    --enable-pic
    --enable-small
    --enable-optimizations
)

build_arch() {
    local ARCH=$1
    local SDK=$2
    local PLATFORM=$3
    local HOST=$4

    echo "--> 正在编译 ${PLATFORM} (${ARCH})..."
    local SYSROOT=$(xcrun --sdk ${SDK} --show-sdk-path)
    local CC=$(xcrun --sdk ${SDK} -f clang)
    local CFLAGS="-arch ${ARCH} -isysroot ${SYSROOT} -mios-version-min=14.0 -fembed-bitcode-marker"
    local LDFLAGS="-arch ${ARCH} -isysroot ${SYSROOT}"

    local PREFIX="${BUILD_DIR}/${PLATFORM}-${ARCH}"
    mkdir -p "${PREFIX}"

    pushd "${FFMPEG_SRC}" > /dev/null
    ./configure \
        --prefix="${PREFIX}" \
        --arch="${ARCH}" \
        --cc="${CC}" \
        --sysroot="${SYSROOT}" \
        --extra-cflags="${CFLAGS}" \
        --extra-ldflags="${LDFLAGS}" \
        "${COMMON_FLAGS[@]}"

    make clean
    make -j$(sysctl -n hw.ncpu || nproc)
    make install
    popd > /dev/null
}

echo "提示：此脚本用于在 macOS 编译机上生成 FFmpeg.xcframework。"
echo "构建流程：真机(arm64) + 模拟器(arm64, x86_64) -> xcodebuild -create-xcframework"
