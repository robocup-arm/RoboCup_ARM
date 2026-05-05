# Contributing Guide

## Branch 建议

- 功能开发：`feat/<short-name>`
- 缺陷修复：`fix/<short-name>`
- 文档调整：`docs/<short-name>`

## 提交信息建议

- `feat: ...` 新功能
- `fix: ...` 缺陷修复
- `refactor: ...` 重构
- `docs: ...` 文档
- `chore: ...` 维护类调整

## 提交前检查清单

- 关键脚本无语法错误（建议 `checkcode`）
- `scripts/run_oneclick.m` 能正常启动
- 地图切换 (`Test World 1/2`) 不引入回归
- 不提交临时文件与本地缓存

## Pull Request 要求

- 描述变更目的与影响范围
- 列出验证步骤和结果
- 若改动分类/规划/视觉逻辑，请附关键日志或截图
- 避免将无关改动混入同一 PR

## 大文件与资源

- 尽量避免重复提交大型二进制资源
- 如需频繁更新大文件，建议迁移到 Git LFS
