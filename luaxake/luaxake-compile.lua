local M = {}
local lfs = require "lfs"
local error_logparser = require("make4ht-errorlogparser")


local log = logging.new("compile")



--- fill command template with file information
--- @param file metadata file on which the command should be run
--- @param command string command template
--- @return string command 
local function prepare_command(file, command_template)
  -- replace placeholders like @{filename} with the correspoinding keys from the metadata table
  return command_template:gsub("@{(.-)}", file)
end


local function test_log_file(filename)
  local f = io.open(filename, "r")
  if not f then 
    log:error("Cannot open log file: " .. filename)
    return nil 
  end
  local content = f:read("*a")
  f:close()
  return error_logparser.parse(content)
end

--- run a command
--- @param file metadata file on which the command should be run
--- @return number status returned by the command
--- @return string output from the command
local function compile(file)
  local current_dir = lfs.currentdir()
  lfs.chdir(file.absolute_dir)
  local output_files = file.output_files
  for _, output in ipairs(output_files) do
    local extension = output.extension
    local command_metadata = config.compilers[extension]
    if command_metadata and output.needs_compilation then
      local command_template = command_metadata.command
      local command = prepare_command(file, command_template)
      log:debug("command " .. command)
      -- we reuse this file from make4ht's mkutils.lua
      local f = io.popen(command, "r")
      local output = f:read("*all")
      -- rc will contain return codes of the executed command
      local rc =  {f:close()}
      -- the status code is on the third position 
      -- https://stackoverflow.com/a/14031974/2467963
      local status = rc[3]
      if status ~= command_metadata.status then
        log:error("Command returned wrong status number: " .. (status or ""))
      end
      if command_metadata.check_log then
        local errors = test_log_file(file.basename .. ".log")
      end
    end
  end
  lfs.chdir(current_dir)
  return status, output
end

M.compile = compile

return M
