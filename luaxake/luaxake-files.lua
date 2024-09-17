local M = {}
local pl = require "penlight"
local graph = require "luaxake-graph"
local log = logging.new("files")
local mkutils = require "mkutils"

local path = pl.path

local abspath = pl.path.abspath

--- identify, if the file should be ignored
--- @param entry string tested file path
--- @return boolean should_be_ignored if file should be ignored
local function ignore_entry(entry)
  -- files that should be ignored
  if entry:match("^%.") then return true end
  return false
end


--- get file extension 
--- @param relative_path string file path
--- @return string extension
local function get_extension(relative_path)
  return relative_path:match("%.([^%.]+)$")
end

--- normalize directory name to be used in get_files
--- @param dir string
--- @return string
local function prepare_dir(dir)
  return dir:gsub("/$", "")
end

--- get absolute and relative file path, as well as other file metadata
--- @param dir string current directory
--- @param entry string current filename
--- @return metadata
local function get_metadata(dir, entry)
  local relative_path = string.format("%s/%s", dir, entry)
  --- @class metadata 
  --- @field dir string relative directory path of the file 
  --- @field absolute_dir string absolute directory path of the file
  --- @field filename string filename of the file
  --- @field basename string filename without extension
  --- @field extension string file extension
  --- @field relative_path string relative path of the file 
  --- @field absolute_path string absolute path of the file
  --- @field modified number last modification time 
  --- @field dependecies metadata[] list of files the file depends on
  --- @field needs_compilation boolean 
  --- @field exists boolean true if file exists
  --- @field output_files output_file[]
  local metadata = {
    dir = dir,
    absolute_dir = abspath(dir),
    filename = entry,
    relative_path = relative_path,
    absolute_path = abspath(relative_path),
    modified      = path.getmtime(relative_path),
    extension     = get_extension(entry),
    dependecies   = {},
    needs_compilation = false,
    output_files  = {},
  }
  metadata.basename, _ = path.splitext(entry)
  metadata.exists = mkutils.file_exists(metadata.absolute_path)
  return metadata
end

--- get metadata for all files in a directory and it's subdirectories
--- @param dir string path to the directory
--- @param files? table retrieved files
--- @return metadata[]
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
--- @param files metadata[] list of  files to be checked
--- @return metadata[] list of TeX files
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
--- @return boolean is_main true if the file contains \documentclass
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
--- @param files metadata[] list of TeX files to be tested
--- @return metadata[] main_tex_files list of main TeX files
local function filter_main_tex_files(files)
  local t = {}
  for _, metadata in ipairs(files) do
    if is_main_tex_file(metadata.absolute_path, config.documentclass_lines ) then
      log:debug("Found main TeX file: " .. metadata.absolute_path)
      t[#t+1] = metadata
    end
  end
  return t
end

--- Detect if the output file needs recompilation
---@param tex metadata metadata of the main TeX file to be compiled
---@param html metadata metadata of the output file
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
--- @param metadata metadata TeX file metadata
--- @return metadata[] dependecies list of files included from the file
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
--- @param metadata metadata metadata of the TeX file
--- @param extensions table list of extensions
--- @return boolean needs_compilation true if the file needs compilation
--- @return output_file[] list of output files 
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
    --- @class output_file 
    --- @field needs_compilation boolean true if the file needs compilation
    --- @field metadata metadata of the output file 
    --- @field extension string of the output file
    output_files[#output_files+1] = {
      needs_compilation = status,
      metadata          = html_file,
      extension         = extension
    }
  end
  return needs_compilation, output_files
end

--- create sorted table of files that needs to be compiled 
--- @param tex_files metadata[] list of TeX files metadata
--- @return metadata[] to_be_compiled list of files in order to be compiled
local function sort_dependencies(tex_files)
  -- create a dependency graph for files that needs compilation 
  -- the files that include other courses needs to be compiled after changed courses 
  -- at least that is what the original Xake command did. I am not sure if it is really necessary.
  local Graph = graph:new()
  local used = {}
  local to_be_compiled = {}
  -- first add all used files
  for _, metadata in ipairs(tex_files) do
    if metadata.needs_compilation then
      Graph:add_edge("root", metadata.absolute_path)
      used[metadata.absolute_path] = metadata
    end
  end
  -- now add edges to included files which needs to be recompiled
  for _, metadata in pairs(used) do
    local current_name = metadata.absolute_path
    for _, child in ipairs(metadata.dependecies) do
      local name = child.absolute_path
      -- add edge only to files added in the first run, because only these needs compilation
      if used[name] then
        Graph:add_edge(current_name, name)
      end
    end
  end
  -- topographic sort of the graph to get dependency sequence
  local sorted = Graph:sort()
  -- we need to save files in the reversed order, because these needs to be compiled first
  for i = #sorted, 1, -1 do
    local name = sorted[i]
    to_be_compiled[#to_be_compiled+1] = used[name]
  end
  return to_be_compiled
end

--- find TeX files that needs to be compiled in the directory tree
--- @param dir string root directory where we should find TeX files
--- @return metadata[] to_be_compiled list of that need compilation
--- @return metadata[] tex_files list of all TeX files found in the directory tree
local function needing_compilation(dir)
  local files = get_files(dir)
  local tex_files = filter_main_tex_files(get_tex_files(files))
  -- now check which output files needs a compilation
  for _, metadata in ipairs(tex_files) do
    -- get list of included TeX files
    metadata.dependecies = get_tex_dependencies(metadata)
    -- check for the need compilation
    local status, output_files = check_output_files(metadata, config.output_formats)
    metadata.needs_compilation = status
    metadata.output_files = output_files
    log:debug("main tex file", metadata.filename, metadata.absolute_dir, metadata.extension, status)
  end

  -- create ordered list of files that needs to be compiled
  local to_be_compiled = sort_dependencies(tex_files)
  return to_be_compiled, tex_files
end

M.needing_compilation = needing_compilation



return M
