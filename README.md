# VideoPlayer

iOS 视频播放器，支持 Jellyfin 服务器流媒体播放，基于 AVFoundation 构建。

## 功能清单

### 基础播放
- ✅ 播放/暂停/停止
- ✅ 进度条拖拽跳转
- ✅ 播放倍速调节
- ✅ 全屏/横竖屏切换
- ✅ 锁屏控制（后台播放）

### 多格式兼容
- ✅ **HLS (m3u8) 流媒体** ← Jellyfin 播放
- ✅ MP4 点播
- ✅ FLV 直播

### 手势控制
- 左侧上下滑动：调节亮度
- 右侧上下滑动：调节音量
- 水平滑动：快进/快退

### 异常处理
- ✅ 网络中断检测与提示
- ✅ 无效地址自动拦截
- ✅ 播放错误友好提示
- ✅ 自动重试机制

## 项目结构

```
VideoPlayer/
├── App/
│   └── AppDelegate.swift           # 应用入口
├── Features/
│   ├── BaseViewController.swift    # 基类控制器
│   ├── LoginViewController.swift   # 登录页面
│   ├── JellyfinHomeViewController.swift  # 媒体列表
│   └── MediaItemTableViewCell.swift      # 媒体项单元格
├── Network/
│   ├── JellyfinAPI.swift           # Jellyfin API 封装
│   ├── NetworkManager.swift       # 网络请求管理
│   ├── NetworkMonitor.swift       # 网络状态监控
│   ├── RequestDispatcher.swift    # 请求分发器
│   ├── URLBuilder.swift           # URL 构建器
│   └── Models.swift              # 数据模型
├── Player/
│   ├── PlayerViewController.swift # 播放器控制器
│   ├── PlayerCore.swift            # 播放核心引擎
│   ├── PlayerControlsView.swift   # 播放控制栏
│   ├── PlayerView.swift           # 播放器视图
│   ├── GestureManager.swift       # 手势管理
│   └── PlayerProtocols.swift      # 播放协议定义
├── Utils/
│   ├── Constants.swift            # 常量定义
│   ├── LoadingView.swift          # 加载视图
│   └── Logger.swift              # 日志系统
└── Info.plist                     # 应用配置
```

## 技术栈

| 技术 | 说明 |
|------|------|
| UIKit | UI 框架 |
| AVFoundation | 音视频播放 |
| Network Framework | 网络状态监控 |
| Combine | 响应式编程（可选） |

## 依赖

- iOS 15.0+
- 无需第三方依赖，使用系统原生框架

## 快速开始

1. 克隆项目
2. 用 Xcode 打开 `VideoPlayer.xcodeproj`
3. 运行到 iOS 设备或模拟器
4. 在登录页面输入 Jellyfin 服务器地址和凭据
5. 浏览媒体库并选择视频播放

## Jellyfin 配置

支持自托管 Jellyfin 服务器：
- 服务器地址：支持 IP 或域名
- 认证方式：用户名 + 密码
- 自动保存登录态

## 架构设计

### 设计模式
- **MVVM-lite**: 轻量级视图模型
- **Protocol-Oriented**: 面向协议编程
- **Dependency Injection**: 依赖注入（便于单元测试）

### 核心模块

| 模块 | 职责 |
|------|------|
| PlayerCore | 封装 AVPlayer，提供播放控制 |
| NetworkManager | 统一网络请求管理 |
| JellyfinAPI | Jellyfin 业务逻辑封装 |
| GestureManager | 手势识别与反馈 |

## 常见问题

### Q: 为什么无法播放视频？
A: 请检查：
1. Jellyfin 服务器是否正常运行
2. 网络连接是否正常
3. 账号是否已登录

### Q: 支持哪些视频格式？
A: 主要支持 HLS (m3u8)，也支持 MP4、FLV 等常见格式

### Q: 如何实现后台播放？
A: 应用已配置后台音频模式，锁屏后仍可继续播放

## 许可证

MIT License
