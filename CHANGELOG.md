# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Coordinator 模式：统一管理应用导航逻辑，解耦 ViewController
- 依赖注入容器 (AppContainer)：集中管理全局服务实例，便于单元测试
- 统一播放状态管理 (PlayerState)：idle/loading/playing/paused/buffering/ended/error

### Technical
- 播放器池 (PlayerPool)：线程安全的 AVPlayer 实例管理
- 图片缓存优化：支持 PNG 透明度保留
- 缩略图 URL 构建：自动拼接 Jellyfin API 完整地址
- Keychain 安全存储：API Token 加密存储
- URLBuilder：标准化 URL 构建，处理特殊字符

### Fixed
- 修复登录流程中 await 和 baseURL 设置顺序问题
- 修复 AppContainer.shared 可选性问题
- 修复 PlayerState Equatable 实现
- 修复 VideoCache 类型安全问题
- 修复 CacheSystem.set 方法签名不匹配问题 (#1)
- 修复循环引用风险：AppCoordinator 中闭包捕获问题 (#2)
- 修复 @MainActor 与 Actor 混用问题：CacheSystem statistics 访问 (#3)
- 修复未定义的 Player 类型：PlayerPool 数组类型问题 (#4)
- 修复重复代码：统一 URL 标准化逻辑 (#5)
- 修复未使用的参数：CacheSystem cost 参数问题 (#6)
- 修复可选值强制解包风险：PlayerViewController playerLayer! (#7)
- 修复线程安全：PlayerPool NonSendable 类型跨越 Actor 边界 (#8)
- 修复 LoginViewController.showError 调用参数错误
- 修复 JellyfinAPIClient 协议缺少 baseURL 和 token 的 set 访问器
- 简化 LoginViewController 中的 URL 验证逻辑
- 修复 JellyfinHomeViewController 数组元素缺少逗号的语法错误
- 修复 CacheSystem set 方法 cost 参数注释说明 (#1-警告)
- 修复 PlayerPool.acquirePlayerCore 的 @MainActor 与 Actor 隔离 (#2-警告)
- 添加 PlayerEngine 双状态源问题说明注释 (#3-警告)
- **重构**：统一 PlayerEngine 状态管理，废弃 stateSubject (#3-警告-重构)

## [1.0.0] - 2026-03-30

### Added
- 基础播放功能（播放/暂停/停止）
- 进度条拖拽跳转
- 播放倍速调节
- 全屏/横竖屏切换
- 锁屏控制（后台播放）
- HLS (m3u8) 流媒体支持
- MP4 点播支持
- FLV 直播支持
- 手势控制（亮度/音量/快进快退）
- 网络中断检测与提示
- 无效地址自动拦截
- 播放错误友好提示
- 自动重试机制
- Jellyfin 服务器登录与认证
- 媒体库浏览
- GitHub Actions CI/CD 自动构建
- Assets.xcassets 图标支持

### Technical
- iOS 15.0+ 支持
- 使用系统原生框架（UIKit, AVFoundation, Network）
- MVVM-lite 架构
- 面向协议编程

## [0.0.1] - 2026-01-01

### Added
- 项目初始化
- 基础播放器框架
