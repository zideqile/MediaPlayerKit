Pod::Spec.new do |s|
  s.name             = 'MediaPlayerKit'
  s.version          = '1.0.0'
  s.summary          = 'A high-performance modern multimedia player SDK for iOS based on KSPlayer, FFmpeg, VideoToolbox, and Metal.'
  s.homepage         = 'https://github.com/your-org/MediaPlayerKit'
  s.license          = { :type => 'LGPL-2.1', :file => 'LICENSE' }
  s.author           = { 'Your Team' => 'dev@your-company.com' }
  s.source           = { :git => 'https://github.com/your-org/MediaPlayerKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/MediaPlayerKit/**/*.{swift,h,m,mm,c,cpp}'
  s.resources = 'Sources/MediaPlayerKit/Rendering/Shaders.metal'
  
  s.frameworks = 'AVFoundation', 'VideoToolbox', 'Metal', 'MetalKit', 'AudioToolbox', 'CoreMedia', 'Accelerate'
  s.libraries = 'c++', 'z', 'bz2', 'iconv'

  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '-DENABLE_METAL_RENDER -DENABLE_HARDWARE_ACCELERATION',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
