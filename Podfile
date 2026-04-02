# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

target 'VideoPlayer' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for VideoPlayer

  # 网络请求（推荐）
  pod 'Alamofire', '~> 5.8'

  # 图片/视频缩略图加载
  pod 'SDWebImage', '~> 5.18'

  # Auto Layout
  pod 'SnapKit', '~> 5.6'

  # 网络状态监听（可选，Project已有Network框架可不用）
  # pod 'ReachabilitySwift', '~> 5.0'

  # 视频缓存扩展（可选）
  # pod 'VIMediaCache', '~> 1.0'

  # 测试框架
  target 'VideoPlayerTests' do
    inherit! :search_paths
    pod 'Quick', '~> 5.0'
    pod 'Nimble', '~> 9.0'
  end

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      # SwiftLint（代码规范）
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'SWIFT_VERSION_5_0'
    end
  end
end
