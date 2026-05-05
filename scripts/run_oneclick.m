% One-click startup for project_v3_copy.
% Usage: run('scripts/run_oneclick.m')

thisDir = fileparts(mfilename("fullpath"));
projectDir = fileparts(thisDir);

if ~strcmpi(pwd, projectDir)
    cd(projectDir);
end

bdclose("all");
clear functions;
clear vision_core_multi;
rehash;
if exist(fullfile(projectDir, "slprj"), "dir") == 7
    try
        rmdir(fullfile(projectDir, "slprj"), "s");
    catch
    end
end
run(fullfile(projectDir, "scripts", "arm_startup.m"));
sim("RoboCup_ARM");
