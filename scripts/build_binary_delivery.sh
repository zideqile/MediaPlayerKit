#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ "$(uname -s)" != Darwin ]; then
  echo '需要 macOS、Xcode 和 XcodeGen；Linux 无法生成 iOS XCFramework。' >&2
  exit 1
fi
: "${1:?用法: bash scripts/build_binary_delivery.sh 构建号}"
command -v xcodegen >/dev/null
xcodebuild -version
OUT="$ROOT/build/binary-delivery"
if [ -e "$OUT" ]; then
  echo 'build/binary-delivery 已存在，请先移走旧产物，避免混入不同版本。' >&2
  exit 1
fi
mkdir -p "$OUT/SDK" "$OUT/Audit" "$OUT/Licenses"
python3 scripts/generate_versions.py --build --build-number "$1" --manifest "$OUT/version-manifest.json"
# Prevent local Xcode build phase from changing the shared build timestamp between slices.
export CI=true
xcodegen generate
mkdir -p MediaPlayerKitDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved MediaPlayerKitDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -resolvePackageDependencies -project MediaPlayerKitDemo.xcodeproj -scheme MediaPlayerKit \
  -clonedSourcePackagesDirPath "$OUT/SourcePackages" -onlyUsePackageVersionsFromResolvedFile
for platform in device simulator; do
  if [ "$platform" = device ]; then destination='generic/platform=iOS'; else destination='generic/platform=iOS Simulator'; fi
  xcodebuild archive -project MediaPlayerKitDemo.xcodeproj -scheme MediaPlayerKit \
    -configuration Release -destination "$destination" -archivePath "$OUT/$platform.xcarchive" \
    -clonedSourcePackagesDirPath "$OUT/SourcePackages" -onlyUsePackageVersionsFromResolvedFile \
    SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO \
    | tee "$OUT/Audit/$platform-build.log"
  framework="$OUT/$platform.xcarchive/Products/Library/Frameworks/MediaPlayerKit.framework"
  xcrun otool -L "$framework/MediaPlayerKit" > "$OUT/Audit/$platform-linked-libraries.txt"
done
xcodebuild -create-xcframework \
  -framework "$OUT/device.xcarchive/Products/Library/Frameworks/MediaPlayerKit.framework" \
  -framework "$OUT/simulator.xcarchive/Products/Library/Frameworks/MediaPlayerKit.framework" \
  -output "$OUT/SDK/MediaPlayerKit.xcframework"
python3 scripts/inspect_xcframework.py "$OUT/SDK/MediaPlayerKit.xcframework" > "$OUT/Audit/dependency-audit.json"
cp -R delivery/Docs delivery/Sample "$OUT/"
cp delivery/README.md Package.resolved "$OUT/"
cp docs/Logging.md docs/Versioning.md "$OUT/Docs/"
python3 - <<'PY'
from pathlib import Path
import shutil, hashlib
out = Path('build/binary-delivery')
s = Path('Examples/MediaPlayerKitDemo/Views/H5URLPlayerView.swift').read_text()
(out/'Sample/H5URLPlayerView.swift').write_text(s.split('/// Keep both H5 samples')[0])
shutil.copy('Examples/MediaPlayerKitDemo/Resources/URLHybridPlayer/url-player.html', out/'Sample/url-player.html')
for checkout in (out/'SourcePackages/checkouts').iterdir():
    for p in checkout.iterdir():
        if p.is_file() and p.name.lower().startswith(('license', 'copying', 'notice')):
            shutil.copy(p, out/'Licenses'/f'{checkout.name}-{p.name}')
paths = [p for folder in ['SDK','Docs','Sample','Licenses'] for p in (out/folder).rglob('*') if p.is_file()]
paths += [out/'version-manifest.json', out/'Package.resolved']
(out/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out)}\n' for p in sorted(paths)))
(out/'CANDIDATE.txt').write_text('尚未完成第三方依赖闭包检查、纯二进制消费编译和真机验收，不得作为正式包交付。\n')
PY
printf '%s\n' "候选产物：$OUT；按 Docs/Acceptance.md 完成依赖、消费工程和真机验收后才能交付。"
