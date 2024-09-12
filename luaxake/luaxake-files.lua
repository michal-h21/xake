local M = {}
local pl = require "penlight"
-- local graph = require "luaxake-graph"
local log = logging.new("files")
local mkutils = require "mkutils"

local path = pl.path

local abspath = pl.path.abspath

--- identify, if the file should be ignored
---@param entry string
---@return boolean
local function ignore_entry(entry)
  -- files that should be ignored
  if entry:match("^%.") then return true end 
  return false
end


local function get_extension(relative_path)
  return relative_path:match("%.([^%.]+)$")
end

--- normalize directory name to be used in get_files
---@param dir string
---@return string
local function prepare_dir(dir)
  return dir:gsub("/$", "")
end

--- get absolute and relative file path, as well as other file metadata
--- @param dir string current directory
--- @param entry string current filename
--- @return table
local function get_metadata(dir, entry)
  local relative_path = string.format("%s/%s", dir, entry)
  local metadata = {
    dir = dir,
    absolute_dir = abspath(dir),
    filename = entry,
    relative_path = relative_path,
    absolute_path = abspath(relative_path),
    extension     = get_extension(relative_path),
    modified      = path.getmtime(relative_path)
  }
  metadata.exists = mkutils.file_exists(metadata.absolute_path)
  return metadata
end

--- get metadata for all files in a directory and it's subdirectories
---@param dir string path to the directory
---@param files? table retrieved files
---@return table
local function get_files(dir, files)
  dir = prepare_dir(dir)
  files = files or {}
  for entry in path.dir(dir) do
    if not ignore_entry(entry) then
      local metadata = get_metadata(dir, entry)
      local relative_path = metadata.relative_path
      if path.isdir(relative_path) then
        files = get_files(relative_path, files)
      elseif path.isfile(relative_path) then
        files[#files+1] = metadata
      end
    end
  end
  return files
end

--- filter TeX files from array of files
---@param files table
---@return table
local function get_tex_files(files)
  local tbl = {}
  for _, file in ipairs(files) do
    if file.extension == "tex" then
      tbl[#tbl+1] = file
    end
  end
  return tbl
end

--- test if the TeX file can be compiled standalone
--- @param filename string name of the tested TeX file
--- @param linecount number number of lines that should be tested
--- @return boolean
local function is_main_tex_file(filename, linecount)
  -- we assume that the main TeX file contains \documentclass near beginning of the file 
  linecount = linecount or 30 -- number of lines that will be read
  local line_no = 0
  for line in io.lines(filename) do
    line_no = line_no + 1
    if line_no > linecount then break end
    if line:match("^%s*\\documentclass") then return true end
  end
  return false
end

--- get list of compilable TeX files 
--- @param files table list of TeX files to be tested
--- @return table
local function filter_main_tex_files(files)
  local t = {}
  for _, metadata in ipairs(files) do
    if is_main_tex_file(metadata.absolute_path) then
      log:debug("Found main TeX file: " .. metadata.absolute_path)
      t[#t+1] = metadata
    end
  end
  return t
end

--- Detect if the output file needs recompilation
---@param tex table metadata of the main TeX file to be compiled
---@param html table metadata of the output file
---@return boolean
local function is_up_to_date(tex, html)
  -- if the output file doesn't exist, it needs recompilation
  if not html.exists then return true end
  -- test if the output file is older if the main file or any dependency
  local status = tex.modified > html.modified
  for _,subfile in ipairs(tex.dependecies or {}) do
    status = status or subfile.modified > html.modified
  end
  return status
end

local input_commands = {input=true, activity=true, include=true, includeonly=true}

--- get list of files included in the given TeX file
--- @param metadata table TeX file metadata
--- @return table
local function get_tex_dependencies(metadata)
  local filename = metadata.absolute_path
  local current_dir = metadata.absolute_dir
  local f = io.open(filename, "r")
  local dependecies = {}
  if f then
    local content = f:read("*a")
    f:close()
    -- loop over all LaTeX commands with arguments
    for command, argument in content:gmatch("\\(%w+)%s*{([^%}]+)}") do
      -- add dependency if the current command is \input like
      if input_commands[command] then
        local metadata = get_metadata(current_dir, argument)
        if not metadata.exists then
          -- the .tex extension may be missing, so try to read it again
          metadata = get_metadata(current_dir, argument .. ".tex")
        end
        if metadata.exists then
          log:debug("dependency: ", metadata.absolute_path)
          dependecies[#dependecies+1] = metadata
        end
      end
    end
  end
  return dependecies
end


--- check if any output file needs a compilation
---@param metadata table metadata of the TeX file
---@param extensions table list of extensions
---@return table
local function check_output_files(metadata, extensions)
  local output_files = {}
  local tex_file = metadata.relative_path
  local needs_compilation = false
  for _, extension in ipairs(extensions) do
    local html_file = get_metadata(metadata.dir, tex_file:gsub("tex$", extension))
    -- detect if the HTML file needs recompilation
    local status = is_up_to_date(metadata, html_file)
    needs_compilation = needs_compilation or status
    log:debug("needs compilation", html_file.absolute_path, status)
    output_files[#output_files+1] = {
      needs_compilation = status,
      metadata          = html_file,
      extension         = extension
    }
  end
  return needs_compilation, output_files
end

local function needing_compilation(dir)
  local files = get_files(dir)
  local tex_files = filter_main_tex_files(get_tex_files(files))
  -- now check which output files needs a compilation
  for _, metadata in ipairs(tex_files) do
    -- get list of included TeX files
    metadata.dependecies = get_tex_dependencies(metadata)
    -- check for the need compilation
    local status, output_files = check_output_files(metadata, {"html", "pdf"})
    metadata.needs_compilation = status 
    metadata.output_files = output_files
    log:debug("main tex file", metadata.filename, metadata.absolute_dir, metadata.extension, status)
  end
  return tex_files
end

M.needing_compilation = needing_compilation



return M
