This package splits the local helper functions from your large recognition script into standalone .m files.

Included:
- All local functions extracted from 粘贴的文本 (1).txt
- run_recognition_frame.m (five-class pipeline)
- detect_all_objects_single_frame.m (segmentation ONNX entry)
- attach_cls_name.m
- run_recognition_frame_adapter.m
- flatten_image_results_local.m

Model path in detect_all_objects_single_frame.m is set to:
E:\Graduation_project\Graduation\Graduation	emplates-robocup-robot-manipulation-challenge-main\MATLAB_Simulink_Templates5\project_v3\RoboCup_ARM\RoboCup_ARM\scripts\modelest10_seg_v3.onnx

Put these files in the same MATLAB path folder as vision_core_multi.m (or add that folder to path).
