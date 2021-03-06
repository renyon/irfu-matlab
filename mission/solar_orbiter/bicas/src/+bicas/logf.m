%
% Wrapper around bicas.log but prints with pattern+parameters.
%
%
% ARGUMENTS
% =========
% msgStr   : Log message, in the form of "format" argument to sprintf.
% varargin : Variables used in msgStr
%
%
% Author: Erik P G Johansson, IRF-U, Uppsala, Sweden
% First created 2019-07-26
%
function logf(logLevel, msgStr, varargin)
    
    bicas.log( logLevel, sprintf(msgStr, varargin{:}) );
    
end