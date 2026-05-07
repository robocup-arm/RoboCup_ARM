# RoboCup_ARM

MATLAB/Simulink mechanical arm project for RoboCup object recognition, picking, and sorting.

## Team

This project is developed by the **JSIC team at Queen Mary University of London**.

- Team name: **NexusPrime**
- Team leader: **Jonathan Loo**
- Members: **Ziqi Guo, Yifu Feng, Siyuan Zhu**

## Important Notes

- The score shown in the demo video is **manually counted by our team according to the competition rules**, and is provided only as a reference for the committee's official scoring.
- A project technical PPT (covering underlying logic and implementation details) is included in this GitHub repository, and we will continue to complete and update it. Please refer to that PPT for deeper technical details.

## Python Dependencies

Install Python dependencies before running the vision pipeline:

```bash
pip install -r requirement.txt
```

Required packages are defined in [requirement.txt](requirement.txt).

## MATLAB Toolboxes

Please install these MATLAB products before running this project:

- `MATLAB`
- `Simulink`
- `Stateflow`
- `Robotics System Toolbox`
- `Computer Vision Toolbox`
- `Image Processing Toolbox`
- `Simulink 3D Animation`
- `Parallel Computing Toolbox`

## Rule Quick View

### 1) Class IDs
- `1 = bottle`
- `2 = can`
- `3 = marker`
- `4 = cube`
- `5 = spam`

### 2) Cube Color IDs
- `1 = red`
- `2 = yellow`
- `3 = green`
- `4 = blue`
- `5 = purple`

### 3) Sorting Rules
- `can + spam -> green bin`
- `bottle + marker -> blue bin`
- `cube green/purple -> green bin`
- `cube blue/red -> blue bin`
- `cube unknown color -> blue bin (default)`

### 4) Pick Trigger
- Manual: click target in preview, then press `Enter`.
- Auto: press `Space` or `S` to arm auto loop.

### 5) Auto Target Selection
- Auto mode prefers the front-most target in image (`center2D.y` larger first).

### 6) Cube Two-Stage Flow
- Stage 1: cube goes to scale first.
- Stage 2: cube goes from scale to target bin.
- Stage 2 reuses latched cube class/color/yaw to reduce drift.

### 7) Cube Edge Guard (yaw force near bin edge)
- Applies to `cube` only.
- Uses bin rectangle and nearest-edge distance.
- Force yaw when `dClear <= USER_CUBE_EDGE_MARGIN + USER_CUBE_EDGE_MARGIN_TOL`.

### 8) Most Useful Debug Vars
- `VISION_CUBE_EDGE_GUARD_OK`
- `VISION_CUBE_EDGE_GUARD_REASON`
- `VISION_CUBE_EDGE_GUARD_EDGE`
- `VISION_CUBE_EDGE_GUARD_LAST`

## Repository Layout

- `RoboCup_ARM.slx`: main Simulink model.
- `scripts/run_oneclick.m`: one-click run entry.
- `scripts/arm_startup.m`: runtime/base-workspace initialization.
- `scripts/vision_core_multi.m`: multi-object vision and yaw candidates.
- `scripts/planner_core.m`: IK and pick/place trajectory planning.
- `scripts/Generate_Robot_Config_current.m`: execution state machine.
- `scripts/user_command_runtime.m`: manual/auto command logic.
- `scripts/vision_preview.m`: preview UI, click select, key control.
- `scripts/vision_runtime/`: recognition geometry submodules.
- `scripts/model/best10_seg_v3.onnx`: segmentation model.
- `modelData/`: world/model data.
- `Objects/`: simulation meshes/textures.
- `resources/`: MATLAB project metadata.

## Runtime Flow

1. `run_oneclick.m` -> startup + model run.
2. `vision_core_multi.m` outputs `targetPosList/yawList/classIdList/colorIdList`.
3. `vision_preview.m` shows targets and accepts user input.
4. `MATLAB_Function2_current.m` latches selected target and yaw.
5. `planner_core.m` generates `pickTraj/placeTraj`.
6. `Generate_Robot_Config_current.m` executes arm/gripper state machine.

## How To Run

```matlab
run('scripts/run_oneclick.m')
```

Or:

```matlab
run('scripts/arm_startup.m');
sim('RoboCup_ARM');
```

## Auto Grasp Start (Important)

This is an **auto-grasp task**. After startup:

1. Wait for the `Vision Preview` window to appear.
2. Click the `Vision Preview` window once to ensure it is focused.
3. Press `Space` (or `S`) to arm/start auto grasp loop.

If you skip step 2, keyboard input may go to another window and auto grasp will not start.

## Preview Controls

- Mouse click: select target.
- `Enter`: proceed once.
- `Space` or `S`: arm auto loop.
- `X`: disarm auto loop.
- `Esc`: abort current flow.

## World Switching

In `RoboCup_ARM.slx`, toggle comment state of `Test World 1` and `Test World 2`, then press `Ctrl + D`.

## Key Parameters (Base Workspace)

- `USER_CUBE_BIN_RECT`: cube edge-guard active rectangle `[xMin xMax yMin yMax]`.
- `USER_CUBE_EDGE_MARGIN`: near-edge threshold (m).
- `USER_CUBE_EDGE_MARGIN_TOL`: threshold tolerance (m).
- `USER_CUBE_EDGE_GUARD_DEBUG`: edge-guard log on/off.
- `USER_CUBE_EDGE_GUARD_DEBUG_FAIL`: print failed edge-guard cases.

## Collaboration

- See `CONTRIBUTING.md`.
- Issue templates: `.github/ISSUE_TEMPLATE/`.
- PR template: `.github/pull_request_template.md`.
