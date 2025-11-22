-- Simple parser to extract structure from LF files for diagram generation
-- This creates a basic representation without full AST parsing

local M = {}

-- Parse an LF file and extract diagram structure
function M.parse_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file"
  end

  local content = file:read("*all")
  file:close()

  return M.parse_content(content, filepath)
end

-- Parse LF content and extract structure
function M.parse_content(content, filename)
  local structure = {
    filename = filename or "unknown",
    target = nil,
    reactors = {},
    main_reactor = nil,
  }

  -- Extract target
  local target = content:match("target%s+(%w+)")
  structure.target = target

  -- Find all reactor definitions
  for reactor_text in content:gmatch("(main%s+reactor.-\n%s*})") do
    local reactor = M.parse_reactor(reactor_text, true)
    if reactor then
      structure.main_reactor = reactor
      table.insert(structure.reactors, reactor)
    end
  end

  for reactor_text in content:gmatch("(reactor%s+%w+.-\n%s*})") do
    if not reactor_text:match("^main%s+reactor") then
      local reactor = M.parse_reactor(reactor_text, false)
      if reactor then
        table.insert(structure.reactors, reactor)
      end
    end
  end

  return structure
end

-- Parse a single reactor definition
function M.parse_reactor(text, is_main)
  local reactor = {
    name = nil,
    is_main = is_main,
    inputs = {},
    outputs = {},
    instances = {},
    connections = {},
    reactions = {},
    line = 1, -- Will be set by caller if needed
  }

  -- Extract reactor name
  if is_main then
    reactor.name = "Main"
  else
    reactor.name = text:match("reactor%s+(%w+)")
  end

  if not reactor.name then
    return nil
  end

  -- Extract inputs
  for input_def in text:gmatch("input%s+([%w_]+)%s*:%s*([%w_]+)") do
    table.insert(reactor.inputs, { name = input_def, type = "input" })
  end

  -- Extract outputs
  for output_def in text:gmatch("output%s+([%w_]+)%s*:%s*([%w_]+)") do
    table.insert(reactor.outputs, { name = output_def, type = "output" })
  end

  -- Extract reactor instances (e.g., h = new Hello())
  for instance_name, reactor_type in text:gmatch("([%w_]+)%s*=%s*new%s+(%w+)%(") do
    table.insert(reactor.instances, {
      name = instance_name,
      type = reactor_type,
    })
  end

  -- Extract connections (e.g., h.out -> w.in)
  for from_inst, from_port, to_inst, to_port in text:gmatch("([%w_]+)%.([%w_]+)%s*%->%s*([%w_]+)%.([%w_]+)") do
    table.insert(reactor.connections, {
      from = { instance = from_inst, port = from_port },
      to = { instance = to_inst, port = to_port },
    })
  end

  -- Count reactions
  local reaction_count = 0
  for _ in text:gmatch("reaction%(") do
    reaction_count = reaction_count + 1
  end
  reactor.reaction_count = reaction_count

  return reactor
end

-- Find line number for a reactor in content
function M.find_reactor_line(content, reactor_name)
  local lines = vim.split(content, "\n")
  for i, line in ipairs(lines) do
    if reactor_name == "Main" then
      if line:match("^%s*main%s+reactor") then
        return i
      end
    else
      if line:match("^%s*reactor%s+" .. reactor_name) then
        return i
      end
    end
  end
  return 1
end

-- Generate SVG from structure
function M.generate_svg(structure)
  local svg_parts = {}

  -- SVG header
  table.insert(svg_parts, '<svg width="1000" height="800" xmlns="http://www.w3.org/2000/svg">')

  -- Defs for markers
  table.insert(svg_parts, [[
    <defs>
      <marker id="arrowhead" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
        <polygon points="0 0, 10 3, 0 6" fill="#858585" />
      </marker>
    </defs>
  ]])

  -- Find the main reactor
  local main = structure.main_reactor
  if not main then
    table.insert(svg_parts, '<text x="500" y="400" text-anchor="middle" fill="#888">No main reactor found</text>')
    table.insert(svg_parts, '</svg>')
    return table.concat(svg_parts, "\n")
  end

  -- Calculate layout
  local num_instances = #main.instances
  local main_width = math.max(600, num_instances * 200 + 100)
  local main_height = 600

  -- Draw main reactor container
  local main_x = (1000 - main_width) / 2
  local main_y = 100

  table.insert(svg_parts, string.format([[
    <g class="lf-reactor" data-element="%s" data-line="%d" data-col="0">
      <rect x="%d" y="%d" width="%d" height="%d" rx="8" class="lf-reactor"/>
      <text x="%d" y="%d" text-anchor="middle" class="lf-label" font-size="18" font-weight="bold">%s</text>
  ]], main.name, main.line or 17, main_x, main_y, main_width, main_height,
      main_x + main_width / 2, main_y + 30, main.name))

  -- Draw reactor instances inside main
  local instance_y = main_y + 80
  local instance_spacing = main_width / (num_instances + 1)

  local instance_positions = {}

  for i, instance in ipairs(main.instances) do
    local inst_x = main_x + instance_spacing * i - 100
    local inst_y = instance_y
    local inst_w = 200
    local inst_h = 150

    -- Find the reactor definition to get its line number
    local reactor_def = nil
    for _, r in ipairs(structure.reactors) do
      if r.name == instance.type then
        reactor_def = r
        break
      end
    end

    local line_num = 1
    if reactor_def then
      -- Try to find the line number in the original content
      line_num = reactor_def.line or 1
    end

    -- Store position for connection drawing
    instance_positions[instance.name] = {
      x = inst_x,
      y = inst_y,
      w = inst_w,
      h = inst_h,
      reactor = reactor_def,
    }

    table.insert(svg_parts, string.format([[
      <g class="lf-reactor" data-element="%s" data-line="%d" data-col="2">
        <rect x="%d" y="%d" width="%d" height="%d" rx="6" class="lf-reactor"/>
        <text x="%d" y="%d" text-anchor="middle" class="lf-label" font-size="14" font-weight="bold">%s</text>
        <text x="%d" y="%d" text-anchor="middle" class="lf-label" font-size="11" fill="#888">%s</text>
    ]], instance.name, line_num, inst_x, inst_y, inst_w, inst_h,
        inst_x + inst_w / 2, inst_y + 25, instance.name,
        inst_x + inst_w / 2, inst_y + 45, instance.type))

    -- Draw ports for this instance
    if reactor_def then
      -- Input ports (left side)
      local port_spacing = inst_h / (#reactor_def.inputs + 1)
      for j, port in ipairs(reactor_def.inputs) do
        local port_y = inst_y + port_spacing * j
        table.insert(svg_parts, string.format([[
          <circle cx="%d" cy="%d" r="6" class="lf-port"/>
          <text x="%d" y="%d" text-anchor="end" class="lf-label" font-size="10">%s</text>
        ]], inst_x, port_y, inst_x - 10, port_y + 4, port.name))
      end

      -- Output ports (right side)
      port_spacing = inst_h / (#reactor_def.outputs + 1)
      for j, port in ipairs(reactor_def.outputs) do
        local port_y = inst_y + port_spacing * j
        table.insert(svg_parts, string.format([[
          <circle cx="%d" cy="%d" r="6" class="lf-port"/>
          <text x="%d" y="%d" text-anchor="start" class="lf-label" font-size="10">%s</text>
        ]], inst_x + inst_w, port_y, inst_x + inst_w + 10, port_y + 4, port.name))
      end
    end

    table.insert(svg_parts, "  </g>")
  end

  -- Draw connections
  for _, conn in ipairs(main.connections) do
    local from_pos = instance_positions[conn.from.instance]
    local to_pos = instance_positions[conn.to.instance]

    if from_pos and to_pos then
      -- Simple connection from right of source to left of target
      local from_x = from_pos.x + from_pos.w
      local from_y = from_pos.y + from_pos.h / 2
      local to_x = to_pos.x
      local to_y = to_pos.y + to_pos.h / 2

      -- Draw curved connection
      local mid_x = (from_x + to_x) / 2
      table.insert(svg_parts, string.format([[
        <path d="M %d %d C %d %d, %d %d, %d %d"
              class="lf-connection"
              stroke="#858585"
              stroke-width="2"
              fill="none"
              marker-end="url(#arrowhead)"/>
        <text x="%d" y="%d" text-anchor="middle" class="lf-label" font-size="9" fill="#888">%s→%s</text>
      ]], from_x, from_y, mid_x, from_y, mid_x, to_y, to_x, to_y,
          mid_x, (from_y + to_y) / 2 - 5, conn.from.port, conn.to.port))
    end
  end

  -- Close main reactor group
  table.insert(svg_parts, "  </g>")

  -- Add file info
  table.insert(svg_parts, string.format([[
    <text x="500" y="760" text-anchor="middle" class="lf-label" fill="#888" font-size="12">
      Diagram for: %s (Target: %s)
    </text>
    <text x="500" y="780" text-anchor="middle" class="lf-label" fill="#666" font-size="11">
      Click elements to navigate to code
    </text>
  ]], structure.filename or "unknown", structure.target or "unknown"))

  table.insert(svg_parts, '</svg>')

  return table.concat(svg_parts, "\n")
end

-- Main function to generate diagram from file
function M.generate_diagram_from_file(filepath)
  local structure, err = M.parse_file(filepath)
  if not structure then
    return nil, err
  end

  -- Read file again to find line numbers
  local file = io.open(filepath, "r")
  if file then
    local content = file:read("*all")
    file:close()

    -- Find line numbers for reactors
    if structure.main_reactor then
      structure.main_reactor.line = M.find_reactor_line(content, "Main")
    end
    for _, reactor in ipairs(structure.reactors) do
      if not reactor.is_main then
        reactor.line = M.find_reactor_line(content, reactor.name)
      end
    end
  end

  local svg = M.generate_svg(structure)
  return svg, structure
end

return M
