local M = {}
local lfs = require "lfs"
local error_logparser = require("make4ht-errorlogparser")
local pl = require "penlight"
local mkutils = require("mkutils")
local path = pl.path


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

local function copy_table(tbl)
  local t = {}
  for k,v in pairs(tbl) do 
    if type(v) == "table" then
      t[k] = copy_table(v)
    else
      t[k] = v 
    end
  end
  return t
end

--- run a command
--- @param file metadata file on which the command should be run
--- @return number status returned by the command
--- @return string output from the command
local function compile(file, compilers)
  local current_dir = lfs.currentdir()
  lfs.chdir(file.absolute_dir)
  local output_files = file.output_files
  for _, output in ipairs(output_files) do
    local extension = output.extension
    local command_metadata = compilers[extension]
    if command_metadata and output.needs_compilation then
      local command_template = command_metadata.command
      -- we need to make a copy of file metadata to insert some additional fields without modification of the original
      local tpl_table = copy_table(file)
      tpl_table.output_file = file.filename:gsub("tex$", extension)
      local command = prepare_command(tpl_table, command_template)
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

--- remove temporary files
---@param basefile metadata 
---@param extensions table list of extensions of files to be removed
local function clean(basefile, extensions)
  local basename = path.splitext(basefile.absolute_path)
  for _, ext in ipairs(extensions) do
    local filename = basename .. "." .. ext
    if mkutils.file_exists(filename) then
      log:debug("Removing temp file: " .. filename)
      os.remove(filename)
    end
  end
end

M.compile = compile
M.clean   = clean

return M
