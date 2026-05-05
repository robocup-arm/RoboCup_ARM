# RoboCup_ARM

MATLAB/Simulink 机械臂抓取与分类项目，覆盖视觉识别、目标选择、轨迹规划、抓取执行和自动循环。

## 项目现状（按当前仓库）

- 主模型：`RoboCup_ARM.slx`
- 脚本总量：`scripts/` 下 100+ 个 `.m` 文件
- `modelData/`：场景与机器人数据（`arm_data.mat`、`ur5e_gripper.mat`、`example_world*.mat`、`pose_records.xlsx`）
- `Objects/`：仿真物体网格和贴图（`.fbx`/`.png`）
- `resources/`：MATLAB Project 相关元数据
- `slprj/`：Simulink 构建缓存目录

## 目录说明

- `RoboCup_ARM.slx`：总控仿真模型
- `scripts/run_oneclick.m`：一键启动入口（清理 + startup + sim）
- `scripts/arm_startup.m`：运行环境与 base workspace 参数初始化
- `scripts/vision_core_multi.m`：视觉主入口，输出抓取点/yaw/类别/颜色等
- `scripts/planner_core.m`：IK 与轨迹规划，决定抓取/放置路径
- `scripts/MATLAB_Function*_current.m`：模型中 MATLAB Function Block 对应逻辑桥接
- `scripts/Generate_Robot_Config_current.m`：执行状态机（等待、抓取、放置、回位、视角切换）
- `scripts/user_command_runtime.m`：用户输入与自动循环控制
- `scripts/vision_preview.m`：可视化预览窗口、点击选目标、按键控制
- `scripts/vision_runtime/`：识别几何后处理细分模块（can/bottle/spam/cube/marker）
- `scripts/model/best10_seg_v3.onnx`：分割识别模型

## 端到端流程（当前实现）

1. `run_oneclick.m` 调 `arm_startup.m`，加载路径、模型、默认参数。
2. `vision_core_multi.m` 每帧识别目标并输出 `targetPosList / yawList / classIdList / colorIdList`。
3. `vision_preview.m` 显示 bbox 与抓取中心，支持点击选中 ID。
4. `MATLAB_Function2_current.m` 锁定当前目标并缓存 yaw。
5. `planner_core.m` 基于 yaw 候选和 IK 约束生成 `pickTraj/placeTraj`。
6. `Generate_Robot_Config_current.m` 状态机执行轨迹与夹爪控制。
7. `user_command_runtime.m` 支持自动循环与重置。

## 目标类别与规则

类别 ID（`vision_core_multi.m`）：

- `1 bottle`
- `2 can`
- `3 marker`
- `4 cube`
- `5 spam`

颜色 ID（cube）：

- `1 red`
- `2 yellow`
- `3 green`
- `4 blue`
- `5 purple`

分类规则（`planner_core.m`）：

- `can + spam -> green`
- `bottle + marker -> blue`
- `cube: green/purple -> green`
- `cube: blue/red -> blue`

## 运行方法

### 一键运行

```matlab
run('scripts/run_oneclick.m')
```

### 手动运行

```matlab
run('scripts/arm_startup.m');
sim('RoboCup_ARM');
```

## 预览窗口操作

在 `Vision Preview` 窗口中：

- 鼠标点击：选中目标（优先 bbox 内，其次最近抓取中心）
- `Enter`：执行一次抓取（`USER_PROCEED=true`）
- `Space` 或 `S`：启动自动循环（并递增 `USER_RESET_TOKEN`）
- `X`：停止自动循环
- `Esc`：中止当前流程

## 地图切换

在 `RoboCup_ARM.slx` 中切换 `Test World 1 / Test World 2`（注释/反注释），`Ctrl + D` 更新后运行。

## Cube 边缘防碰策略（当前版本）

实现文件：`scripts/vision_core_multi.m`

- 仅对 `cube` 生效
- 根据目标在 bin 区域内与四边的距离判定最近边
- 近边时强制选择对应 yaw 候选，降低夹爪碰撞风险

关键参数（Base Workspace）：

- `USER_CUBE_EDGE_GUARD_ENABLE`：总开关
- `USER_CUBE_BIN_RECT`：bin 区域 `[xMin xMax yMin yMax]`
- `USER_CUBE_EDGE_MARGIN`：近边阈值（米）
- `USER_CUBE_EDGE_MARGIN_TOL`：阈值容差（米，当前默认在 startup 中设置）
- `USER_CUBE_EDGE_GUARD_DEBUG`：日志开关
- `USER_CUBE_EDGE_GUARD_DEBUG_FAIL`：失败日志开关

调试输出变量：

- `VISION_CUBE_EDGE_GUARD_OK`
- `VISION_CUBE_EDGE_GUARD_REASON`
- `VISION_CUBE_EDGE_GUARD_EDGE`
- `VISION_CUBE_EDGE_GUARD_LAST`

## 关键运行变量（Base Workspace）

- 选择/执行：`USER_SELECTED_ID`、`USER_PROCEED`、`USER_ABORT`
- 自动循环：`USER_AUTO_RUN`、`USER_AUTO_NEED_RESET`
- 视觉使能：`USER_VISION_ENABLE`
- 视角切换：`USER_VIEW_IDX`、`USER_VIEW_IDX_NEXT`、`USER_VIEW_MOVE_PENDING`
- cube 二阶段：`USER_CUBE_PLACE_MODE`、`USER_CUBE_LATCHED_YAW`、`USER_CUBE_WAIT_FRESH_VISION`
- 最近识别结果：`VISION_LAST_*`

## 协作与规范

- 贡献规范见 [CONTRIBUTING.md](CONTRIBUTING.md)
- Issue 模板：`.github/ISSUE_TEMPLATE/`
- PR 模板：`.github/pull_request_template.md`

## 备注

- 仓库包含较多二进制资源（`.mat`、`.fbx`、`.png`、`.slx`）。
- 若后续大文件更新频繁，建议切换到 Git LFS。
