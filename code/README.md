# RoboCup_ARM

MATLAB/Simulink mechanical arm project for RoboCup object recognition, picking, and sorting.

## Team

This project is developed by the **JSIC team at Queen Mary University of London**.

- Team name: **NexusPrime**
- Team leader: **Jonathan Loo**
- Members: **Ziqi Guo, Yifu Feng, Siyuan Zhu**

## Important Notes

- The score shown in the demo video is **manually counted by our team according to the competition rules**, and is provided only as a reference for the committee's official scoring.
- A project technical PPT (covering underlying logic and implementation details) is included in this GitHub repository. Please refer to that PPT for deeper technical details.

## Repository Layout

At repository root:

- `video/`: demo video (`.mp4`).
- `code/`: all project code, docs, and technical PPT.

Inside `code/`:

- `RoboCup_ARM.slx`: main Simulink model.
- `scripts/run_oneclick.m`: one-click run entry.
- `scripts/arm_startup.m`: runtime/base-workspace initialization.
- `scripts/vision_core_multi.m`: multi-object vision and yaw candidates.
- `scripts/planner_core.m`: IK and pick/place trajectory planning.
- `scripts/Generate_Robot_Config_current.m`: execution state machine.
- `scripts/vision_preview.m`: preview UI and keyboard control.
- `scripts/model/best10_seg_v3.onnx`: segmentation model.
- `modelData/`: world/model data.
- `Objects/`: simulation meshes/textures.
- `RoboCup_ARM_Challenge_2026.pptx`: technical presentation.

## Code Execution Dependencies

### Python

Install Python dependencies from `code/`:

```bash
pip install -r requirement.txt
```

### MATLAB Toolboxes

Please install:

- `MATLAB`
- `Simulink`
- `Stateflow`
- `Robotics System Toolbox`
- `Computer Vision Toolbox`
- `Image Processing Toolbox`
- `Simulink 3D Animation`
- `Parallel Computing Toolbox`

## How To Run

Step 1: Open MATLAB and set current folder to this directory:
- `.../RoboCup_ARM/code`

Step 2: Start the project (two methods):

Method A (recommended):

```matlab
run('scripts/run_oneclick.m')
```

Method B:

```matlab
run('scripts/arm_startup.m');
sim('RoboCup_ARM');
```

Step 3: Start auto grasp (important):
- Wait for `Vision Preview` window
- Click `Vision Preview` once to focus
- Press `Space` (or `S`) to arm/start auto grasp loop
