-- Enhance lfd-generated SVG with source location metadata for click-to-navigate

local M = {}

-- Parse LF file to find reactor definitions and their line numbers
function M.find_reactor_locations(filepath)
  local locations = {}

  local file = io.open(filepath, "r")
  if not file then
    return locations
  end

  local line_num = 0
  for line in file:lines() do
    line_num = line_num + 1

    -- Match reactor definitions
    local reactor_name = line:match("^%s*reactor%s+(%w+)")
    if reactor_name then
      locations[reactor_name] = line_num
    end

    -- Match main reactor
    if line:match("^%s*main%s+reactor") then
      locations["Main"] = line_num
      -- Also store the filename without extension
      local filename = vim.fn.fnamemodify(filepath, ":t:r")
      locations[filename] = line_num
    end
  end

  file:close()
  return locations
end

-- Enhance SVG with click handlers and source location data
function M.enhance_svg(svg_path, source_file)
  -- Read the SVG
  local file = io.open(svg_path, "r")
  if not file then
    return false, "Could not read SVG file"
  end

  local svg_content = file:read("*all")
  file:close()

  -- Get reactor locations from source file
  local locations = M.find_reactor_locations(source_file)

  -- Simple approach: find text elements with reactor names and add attributes to their parent <g>
  local enhanced_svg = svg_content

  for reactor_name, line_num in pairs(locations) do
    -- Escape special characters for pattern matching
    local escaped_name = reactor_name:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")

    -- Pattern to find: <g transform...><text...>ReactorName</text></g>
    -- We'll look for text elements containing the reactor name
    -- Capture the opening tag WITHOUT the closing >
    local pattern = "(<g transform=[^>]+)>%s*(<text[^>]+>[^<]*" .. escaped_name .. "[^<]*</text>)"

    local replacement = string.format(
      '%%1 data-element="%s" data-line="%d" data-col="0" class="lf-interactive-element">%%2',
      reactor_name,
      line_num
    )

    -- Try to replace - use gsub which returns the new string and count
    local new_svg, count = enhanced_svg:gsub(pattern, replacement)

    if count > 0 then
      enhanced_svg = new_svg
      print(string.format("Enhanced %s (line %d) - %d replacements", reactor_name, line_num, count))
    else
      -- Fallback: try without transform requirement
      local fallback_pattern = "(<g[^>]*)>%s*(<text[^>]+>[^<]*" .. escaped_name .. "[^<]*</text>)"
      new_svg, count = enhanced_svg:gsub(fallback_pattern, replacement, 1) -- Only first match

      if count > 0 then
        enhanced_svg = new_svg
        print(string.format("Enhanced %s (line %d) with fallback - %d replacements", reactor_name, line_num, count))
      end
    end
  end

  -- Add a CSS style for hover effects and interactivity
  local style_block = [[
<style>
  .lf-interactive-element {
    cursor: pointer !important;
  }
  .lf-interactive-element:hover rect {
    stroke: #4ec9b0 !important;
    stroke-width: 3 !important;
    filter: drop-shadow(0 0 6px rgba(78, 201, 176, 0.8));
  }
  .lf-interactive-element:hover path[fill="#f2f2f2"],
  .lf-interactive-element:hover path[fill="#ffffff"] {
    fill: #e8f4f1 !important;
  }
  .lf-interactive-element:active rect {
    stroke: #7fe9c5 !important;
    fill: #d4ebe5 !important;
  }
</style>
]]

  -- Insert style block after opening svg tag
  enhanced_svg = enhanced_svg:gsub("(<svg[^>]*>)", "%1\n" .. style_block)

  -- Write enhanced SVG back
  local out_file = io.open(svg_path, "w")
  if not out_file then
    return false, "Could not write enhanced SVG"
  end

  out_file:write(enhanced_svg)
  out_file:close()

  return true
end

return M
