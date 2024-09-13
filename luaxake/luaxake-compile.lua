local M = {}
local lfs = require "lfs"


--- fill command template with file information
--- @param file metadata file on which the command should be run
--- @param command string command template
--- @return string command 
local function prepare_command(file, command_template)
  -- replace placeholders like @{filename} with the correspoinding keys from the metadata table
  return command_template:gsub("@{(.-)}", file)
end

--- run a command
--- @param file metadata file on which the command should be run
--- @param command_template string command template
--- @return number status returned by the command
--- @return string output from the command
local function compile(file, command_template)
  local current_dir = lfs.currentdir()
  lfs.chdir(file.absolute_dir)
  local command = prepare_command(file, command_template)
  -- we reuse this file from make4ht's mkutils.lua
  local f = io.popen(command, "r")
  local output = f:read("*all")
  -- rc will contain return codes of the executed command
  local rc =  {f:close()}
  -- the status code is on the third position 
  -- https://stackoverflow.com/a/14031974/2467963
  local status = rc[3]
  lfs.chdir(current_dir)
  return status, output
end

M.compile = compile

return M
