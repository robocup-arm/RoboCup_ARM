function [selectedId, proceed, abort] = UserCommand()
%#codegen
coder.extrinsic('user_command_runtime');

selectedId = double(0);
proceed = false;
abort = false;

sid = double(0);
pr = false;
ab = false;

[sid, pr, ab] = user_command_runtime();

selectedId = double(sid);
proceed = logical(pr);
abort = logical(ab);
end
