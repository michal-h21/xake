local M = {}
local pl = require "penlight"
local log = logging.new("files")

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

--- get metadata for all files in a directory and it's subdirectories
---@param dir string path to the directory
---@param files? table retrieved files
---@return table
local function get_files(dir, files)
  local dir = prepare_dir(dir)
  local files = files or {}
  for entry in path.dir(dir) do
    if not ignore_entry(entry) then
      local relative_path = string.format("%s/%s", dir, entry)
      if path.isdir(relative_path) then
        files = get_files(relative_path, files)
      elseif path.isfile(relative_path) then
        local metadata = {
          relative_path = relative_path,
          absolute_path = abspath(relative_path),
          extension     = get_extension(relative_path),
          modified      = path.getmtime(relative_path)
        }
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

--- Detect if the HTML file needs recompilation
---@param tex string
---@param html string
---@return boolean?
---@return boolean
local function is_up_to_date(tex, html)
  if not path.isfile(html) then return nil, true end
  return path.getmtime(tex) < (path.getmtime(html) or 0)
end

local input_commands = {input=true, activity=true, include=true, includeonly=true}

local function get_tex_dependencies(filename, current_dir)
  local f = io.open(filename, "r")
  local dependecies = {}
  if f then
    local content = f:read("*a")
    f:close()
    -- loop over all LaTeX commands with arguments
    for command, argument in content:gmatch("\\(%w+)%s*{([^%}]+)}") do
      -- add dependency if the current command is \input like
      if input_commands[command] then
        local filename = path.relpath(argument, current_dir)
        if not path.isfile(filename) then
          filename = filename .. ".tex"
        end
        print(filename)
        if path.isfile(filename) then
          dependecies[#dependecies+1] = filename
          print(filename)
        end
      end
    end
    
  end
  return dependecies
end

local function needing_compilation(dir)
  local files = get_files(dir)
  local tex_files = get_tex_files(files)
  local dirty = {}
  for _, metadata in ipairs(tex_files) do
    local tex_file = metadata.relative_path
    local html_file = tex_file:gsub("tex$", "html")
    -- detect if the HTML file needs recompilation
    local good, err = is_up_to_date(tex_file, html_file)
    if err == nil then
      dirty[tex_file] = not good
    else
      dirty[tex_file] = true
    end
    metadata.dependecies = get_tex_dependencies(tex_file, dir)
    log:debug(metadata.relative_path, metadata.absolute_path, metadata.extension, good, dirty[tex_file])
  end
end

M.needing_compilation = needing_compilation



return M
