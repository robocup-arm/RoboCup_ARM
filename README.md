# RoboCup_ARM

基于 MATLAB/Simulink 的 RoboCup 机械臂抓取与分类项目，包含视觉识别、目标选择、轨迹规划与仿真执行全流程。

## 主要能力

- 多目标识别：`can / bottle / spam / marker / cube`
- 抓取目标选择与锁定
- UR5e 轨迹规划与执行
- 分类放置（蓝桶/绿桶）
- Cube 二阶段流程（秤台中转 + 分类放置）
- Cube 边缘防碰策略（近边强制 yaw）

## 目录结构

- `RoboCup_ARM.slx`：主仿真模型
- `scripts/arm_startup.m`：启动与运行时参数初始化
- `scripts/run_oneclick.m`：一键运行入口
- `scripts/vision_core_multi.m`：视觉主流程与 yaw 候选策略
- `scripts/planner_core.m`：抓取/放置轨迹规划
- `scripts/vision_runtime/`：识别与几何处理子模块
- `modelData/`：模型与场景数据
- `Objects/`：仿真对象资源

## 环境要求

- MATLAB（建议与 Simulink 3D Simulation 工具链匹配）
- Simulink
- Robotics System Toolbox（UR5e IK/轨迹相关）
- 可用的 Sim3D/UE 运行环境（`arm_startup.m` 会尝试自动对齐路径）

## 快速开始

在 MATLAB 命令窗口执行：

```matlab
run('scripts/run_oneclick.m')
```

或手动执行：

```matlab
run('scripts/arm_startup.m');
sim('RoboCup_ARM');
```

## 地图切换

在 `RoboCup_ARM.slx` 中切换 `Test World 1 / Test World 2` 的注释状态（Comment/Uncomment），`Ctrl + D` 更新后运行。

## 关键运行参数（Base Workspace）

- `USER_CUBE_BIN_RECT`：cube 边缘策略作用区域 `[xMin xMax yMin yMax]`
- `USER_CUBE_EDGE_MARGIN`：近边阈值（米）
- `USER_CUBE_EDGE_MARGIN_TOL`：阈值容差（米）
- `USER_CUBE_EDGE_GUARD_DEBUG`：是否输出边缘策略调试日志
- `USER_CUBE_EDGE_GUARD_DEBUG_FAIL`：是否输出失败日志

## 分类规则

- Cans + Spam -> 绿桶
- Bottles + Markers -> 蓝桶
- Cubes：Green + Purple -> 绿桶；Blue + Red -> 蓝桶

## 协作开发

- 提交前建议先运行核心流程冒烟测试
- 规范见 [CONTRIBUTING.md](CONTRIBUTING.md)
- 问题反馈和需求请使用 GitHub Issue 模板

## 仓库说明

本仓库当前包含较多仿真资源和数据文件。若后续仓库体积继续增长，建议启用 Git LFS 管理大文件（如 `.mat`、`.slx`）。
