-- post-process HTML files created by TeX4ht to a form suitable for Ximera
local M = {}
local log = logging.new("transform-html")
local domobject = require "luaxml-domobject"

--- find metadata for the HTML file
---@param file metadata
---@return metadata|nil html file
---@return string? error
local function find_html_file(file)
  -- file metadata passed to the process function are for the TeX file 
  -- we need to find metadata for the output HTML file
  for _, output in ipairs(file.output_files) do
    if output.extension == "html" then
      return output.metadata
    end
  end
  return nil, "Cannot find output HTML file metadata"
end


--- load DOM from a HTML file
---@param filename string
---@return DOM_Object|nil dom
---@return string? error_message
local function load_html(filename)
  local f = io.open(filename, "r")
  if not f then return nil, "Cannot open HTML file: " .. (filename or "") end
  local content = f:read("*a")
  f:close()
  return domobject.html_parse(content)
end

--- Post-process HTML files
---@param file metadata 
---@return boolean status
---@return string? msg
local function process(file)
  -- we must find metadata for the HTML file, because `file` is metadata of the TeX file
  local html_file, msg = find_html_file(file)
  if not html_file then return false, msg end
  local dom, msg = load_html(html_file.absolute_path)
  if not dom then return false, msg end
  for _, meta in ipairs(dom:query_selector("meta[name='description']")) do
    if meta:get_attribute("content") == "xourse" then
      log:status("hello xourse!")
    end
  end


  return true
end

M.process = process

return M
