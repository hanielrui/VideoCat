# Contributing Guide

欢迎贡献代码！请遵循以下指南。

## 开发环境

- Xcode 15.0+
- iOS 15.0+ 部署目标
- Swift 5.0+

## 提交规范

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]
[optional footer]
```

**Type 类型**:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具链更新

**示例**:
```
feat(player): 添加播放速度记忆功能

修复了退出播放后速度不记忆的问题

Closes #123
```

## 代码规范

1. **命名**: 使用驼峰命名法
2. **注释**:复杂逻辑需添加注释
3. **格式化**: 使用 Xcode 默认格式化
4. **提交前**: 确保代码编译通过

## Pull Request 流程

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -am 'Add xxx'`)
4. 推送分支 (`git push origin feature/xxx`)
5. 创建 Pull Request

## 问题反馈

- 使用 GitHub Issues 报告 Bug
- 使用 Discussions 讨论功能

## 许可证

贡献的代码将采用 MIT 许可证。
