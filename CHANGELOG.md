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
