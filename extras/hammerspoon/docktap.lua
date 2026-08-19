--[[
  Docktap — click the focused app’s Dock icon to minimize, like Windows.
  Companion to the Astucore Docktap.app. Safe to run alongside it: if the
  app is already handling clicks this module still no-ops when the icon
  isn’t the frontmost app with visible windows.
]]

local M = {}

local tap
local cache = { items = {}, frame = nil, at = 0 }
local armed = nil
local lastActionAt = 0
local lastActionPID = nil

local CACHE_TTL = 0.35
local MAX_TRAVEL = 10
local MAX_CLICK = 0.55
local MIN_GAP = 0.18

local function axAttr(el, name)
  if not el then return nil end
  local ok, val = pcall(function() return el:attributeValue(name) end)
  if ok then return val end
  return nil
end

local function dockApp()
  local apps = hs.application.applicationsForBundleID("com.apple.dock")
  return apps and apps[1] or nil
end

local function refreshCache(force)
  local now = hs.timer.secondsSinceEpoch()
  if not force and (now - cache.at) < CACHE_TTL and #cache.items > 0 then
    return
  end
  local dock = dockApp()
  if not dock then return end
  local root = hs.axuielement.applicationElement(dock)
  if not root then return end

  local items = {}
  local listFrame = nil
  local function walk(el, depth)
    if not el or depth > 6 then return end
    local role = axAttr(el, "AXRole")
    local sub = axAttr(el, "AXSubrole")
    if role == "AXList" then
      local pos = axAttr(el, "AXPosition")
      local size = axAttr(el, "AXSize")
      if pos and size then
        listFrame = hs.geometry.rect(pos.x, pos.y, size.w, size.h)
      end
    end
    if role == "AXDockItem" and sub == "AXApplicationDockItem" then
      local title = axAttr(el, "AXTitle") or ""
      local pos = axAttr(el, "AXPosition")
      local size = axAttr(el, "AXSize")
      local url = axAttr(el, "AXURL")
      local running = axAttr(el, "AXIsApplicationRunning")
      if pos and size then
        items[#items + 1] = {
          title = title,
          url = url and tostring(url) or nil,
          frame = hs.geometry.rect(pos.x, pos.y, size.w, size.h),
          running = running == true,
        }
      end
      return
    end
    for _, child in ipairs(axAttr(el, "AXChildren") or {}) do
      walk(child, depth + 1)
    end
  end
  walk(root, 0)
  cache.items = items
  cache.frame = listFrame
  cache.at = now
end

local function hit(point)
  refreshCache(false)
  if cache.frame then
    local f = cache.frame
    if point.x < f.x - 36 or point.x > f.x + f.w + 36
        or point.y < f.y - 48 or point.y > f.y + f.h + 48 then
      return nil
    end
  end
  for _, item in ipairs(cache.items) do
    local f = item.frame
    if point.x >= f.x - 4 and point.x <= f.x + f.w + 4
        and point.y >= f.y - 4 and point.y <= f.y + f.h + 4 then
      return item
    end
  end
  return nil
end

local function matches(item, app)
  if not item or not app then return false end
  local name = app:name() or ""
  if item.title ~= "" and item.title == name then return true end
  local path = app:path()
  if path and item.url then
    local a = tostring(item.url):gsub("file://", ""):gsub("%%20", " ")
    if a == path or a:gsub("/$", "") == path:gsub("/$", "") then
      return true
    end
  end
  return item.title == name
end

local function visibleWindows(app)
  local out = {}
  for _, win in ipairs(app:allWindows() or {}) do
    if win:isStandard() and not win:isMinimized() and win:isVisible() then
      local f = win:frame()
      if f and f.w >= 80 and f.h >= 60 then
        out[#out + 1] = win
      end
    end
  end
  return out
end

local function modifiers(e)
  local f = e:getFlags()
  return f.cmd or f.alt or f.ctrl or f.shift
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function minimizeApp(app)
  local n = 0
  for _, win in ipairs(visibleWindows(app)) do
    win:minimize()
    n = n + 1
  end
  return n
end

local function eventPoint(e)
  -- CGEvent / hs.eventtap points are top-left global (Quartz), matching AXPosition.
  return e:location()
end

local function onDown(e)
  armed = nil
  if modifiers(e) then return end
  local point = eventPoint(e)
  refreshCache(true)
  local item = hit(point)
  if not item then
    return
  end
  if not item.running then return end
  local front = hs.application.frontmostApplication()
  if not front or not matches(item, front) then return end
  if front:isHidden() then return end
  local wins = visibleWindows(front)
  if #wins == 0 then return end
  local now = hs.timer.secondsSinceEpoch()
  local pid = front:pid()
  if pid == lastActionPID and (now - lastActionAt) < MIN_GAP then return end
  armed = {
    pid = pid,
    title = item.title,
    point = point,
    at = now,
  }
  print(string.format("Docktap: armed %s pid=%s at %.0f,%.0f", item.title, tostring(pid), point.x, point.y))
end

local function onUp(e)
  if not armed then return end
  local pending = armed
  armed = nil
  if modifiers(e) then return end
  local point = e:location()
  local now = hs.timer.secondsSinceEpoch()
  if (now - pending.at) > MAX_CLICK then return end
  if dist(point, pending.point) > MAX_TRAVEL then return end
  local item = hit(point)
  if not item or item.title ~= pending.title then return end
  local front = hs.application.frontmostApplication()
  if not front or front:pid() ~= pending.pid then return end
  lastActionAt = now
  lastActionPID = pending.pid
  hs.timer.doAfter(0.07, function()
    local app = hs.application.applicationForPID(pending.pid)
    if not app then return end
    if #visibleWindows(app) == 0 then return end
    local n = minimizeApp(app)
    print(string.format("Docktap: minimize %s (%d window(s))", pending.title, n))
  end)
end

function M.start()
  if tap then tap:stop() end
  refreshCache(true)
  tap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.leftMouseUp,
    hs.eventtap.event.types.leftMouseDragged,
  }, function(e)
    local t = e:getType()
    if t == hs.eventtap.event.types.leftMouseDown then
      onDown(e)
    elseif t == hs.eventtap.event.types.leftMouseUp then
      onUp(e)
    elseif t == hs.eventtap.event.types.leftMouseDragged and armed then
      if dist(e:location(), armed.point) > MAX_TRAVEL then
        armed = nil
      end
    end
    return false
  end)
  tap:start()
  hs.timer.doEvery(1.5, function() refreshCache(false) end)
  print(string.format("Docktap (Hammerspoon): on, %d dock app tiles", #cache.items))
end

function M.stop()
  if tap then tap:stop(); tap = nil end
  armed = nil
end

function M.status()
  refreshCache(true)
  return {
    items = #cache.items,
    running = tap ~= nil,
  }
end

return M
