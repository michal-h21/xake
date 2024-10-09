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


local html_cache = {}

--- load DOM from a HTML file
---@param filename string
---@return DOM_Object|nil dom
---@return string? error_message
local function load_html(filename)
  -- cache DOM objects
  if not html_cache[filename] then 
    local f = io.open(filename, "r")
    if not f then return nil, "Cannot open HTML file: " .. (filename or "") end
    local content = f:read("*a")
    f:close()
    html_cache[filename] = domobject.html_parse(content)
  end
  return html_cache[filename]
end

--- detect if the HTML file is xourse
---@param dom DOM_Object
---@return boolean
local function is_xourse(dom, html_file)
  local metas = dom:query_selector("meta[name='description']")
  if #metas == 0 then
    log:warning("Cannot find any meta[description] tags in " .. html_file.absolute_path)
  end
  for _, meta in ipairs(metas) do
    if meta:get_attribute("content") == "xourse" then
      return true
    end
  end
  return false
end

local function is_element_empty(element)
  -- detect if element is empty or contains only blank spaces
  local children = element:get_children()
  if #children > 1 then return false 
  elseif #children == 1 then
    if children[1]:is_text() then
      if children[1]._text:match("^%s*$") then
        return true
      end
      return false
    end
    return false
  end
  return true
  
end

--- Remove empty paragraphs
---@param dom DOM_Object
local function remove_empty_paragraphs(dom)
  for _, par in ipairs(dom:query_selector("p")) do
    if is_element_empty(par) then
      log:debug("Removing empty par")
      par:remove_node()
    end
  end
end


--- Transform Xourse files
---@param dom DOM_Object
---@param file metadata
---@return DOM_Object
local function transform_xourse(dom, file)
  log:debug("strange", file.filename, file.basename)
  for _, dependency in ipairs(file.dependecies) do
    log:debug("dependency", dependency.relative_path, dependency.filename, dependency.basename)
  end
  return dom
end

--- return sha256 digest of a file
---@param filename string
---@return string|nil hash
---@return unknown? error
local function hash_file(filename)
  -- Xake used sha1, but we don't have it in Texlua. On the other hand, sha256 is built-in
  local f = io.open(filename, "r")
  if not f then return nil, "Cannot open TeX dependency for hashing: " .. (filename or "") end
  local content = f:read("*a")
  f:close()
  -- the digest return binary code, we need to convert it to hexa code
  local bincode = sha2.digest256(content)
  local hexs = {}
  for char in bincode:gmatch(".") do
    hexs[#hexs+1] = string.format("%X", string.byte(char))
  end
  return table.concat(hexs)
end



--- Add metadata with TeX file dependencies to the HTML DOM
---@param dom DOM_Object
---@param file metadata
---@return DOM_Object
local function add_dependencies(dom, file)
  -- we will add also TeX file of the current HTML file
  local t = {file}
  -- copy dependencies, as we have an extra entry of the current file
  for _, x in ipairs(file.dependecies) do t[#t+1] = x end
  local head = dom:query_selector("head")[1]
  if not head then log:error("Cannot find head element " .. file.absolute_path:gsub("tex$", "html")) end
  for _, dependency in ipairs(file.dependecies) do
    log:debug("dependency", dependency.relative_path, dependency.filename, dependency.basename)
    local hash, msg = hash_file(dependency.absolute_path)
    if not hash then 
      log:warning(msg) 
    else
      local content = hash .. " " .. dependency.filename
      local meta = head:create_element("meta", {name = "dependency", content = content})
      local newline = head:create_text_node("\n")
      head:add_child_node(meta)
      head:add_child_node(newline)
    end

  end
  return dom
end

--- Save DOM to file
---@param dom DOM_Object
---@param filename string
local function save_html(dom, filename)
  local f = io.open(filename, "w")
  if not f then
    return nil, "Cannot save updated HTML: " .. (filename or "")
  end
  f:write(dom:serialize())
  f:close()
  return true
end

--- Post-process HTML files
---@param file metadata 
---@return boolean status
---@return string? msg
local function process(file)
  -- we must find metadata for the HTML file, because `file` is metadata of the TeX file
  local html_file, msg = find_html_file(file)
  if not html_file then return false, msg end
  local html_name = html_file.absolute_path
  local dom, msg = load_html(html_name)
  if not dom then return false, msg end
  remove_empty_paragraphs(dom)
  add_dependencies(dom, file)
  if is_xourse(dom, html_file) then
    transform_xourse(dom, file)
  end

  return save_html(dom, html_name)
end

M.process = process

return M
