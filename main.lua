--  Copyright (C) 2009 Tyson Brown
--  
--  This file is part of KillsToLevel.
--  
--  KillsToLevel is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--  
--  KillsToLevel is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--  
--  You should have received a copy of the GNU General Public License
--  along with KillsToLevel.  If not, see <http://www.gnu.org/licenses/>.

if LibDebug then LibDebug() end

-- Caches the created functions for parsing localized strings.
local readers = {}

-- Takes some text, considers the format pattern used to create it, and tries to return the
-- values used to create text.
local function parse(text, pattern)
  local reader = readers[pattern]
  
  if not reader then
    local index, swap = 0, {}
    
    local function unpattern(p)
      if p == "%" or p == "(" or p == ")" then
        -- Was an escaped character.
        return "%"..p
      end
      
      index = index + 1
      local b, e, i = p:find("(%d+)%$")
      if i then
        -- Pattern includes an index.
        p = p:sub(1, b-1)..p:sub(e+1)
        i = assert(tonumber(i))
      else
        i = index
      end
      
      swap[i] = index
      
      if p == "d" then return "(%d+)" end
      if p == "s" then return "(.-)" end
      
      -- Don't know how to deal with pattern.
      error()
    end
    
    local pat = string.format("^%s$", pattern:gsub("([%(%)])", "%%%1"):gsub("%%(.-[%(%)%%%a])", unpattern))
    
    local linear = true
    
    for i = 1,index do
      if assert(swap[i]) ~= i then
        linear = false
      end
    end
    
    assert(index > 0)
    
    if linear then
      reader = assert(loadstring(("return (...):match(%q)"):format(pat)))
    else
      -- Create a complicated function to rearrange the arguments.
      local command = "local "
      
      for i = 1,index do
        command = command .. ((i > 1 and ", v" or "v") .. i)
      end
      
      command = command .. (" = (...):match(%q)\nreturn "):format(pat)
      
      for i = 1,index do
        command = command .. ((i > 1 and ", v" or "v") .. swap[i])
      end
      
      reader = assert(loadstring(command))
    end
    
    readers[pattern] = reader
  end
  
  return reader(text)
end

local frame = CreateFrame("Frame", "KillsToLevelFrame", UIParent)

frame:ClearAllPoints()
frame:SetFrameStrata("LOW")
frame:SetWidth(180)
frame:SetHeight(24)
frame:SetMovable(true)
frame:SetPoint("CENTER", 0, 0)

local text_frame = frame:CreateFontString()
text_frame:ClearAllPoints()
text_frame:SetPoint("TOPLEFT", 2, -2)
text_frame:SetPoint("BOTTOMRIGHT", -2, 2)
text_frame:SetShadowColor(0,0,0,0.8)
text_frame:SetShadowOffset(1,-1)
text_frame:SetFont(STANDARD_TEXT_FONT, 12)
text_frame:SetTextColor(1, .8, 0)

text_frame:SetText("Fact: 50% of doctors graduated in the bottom half of their class.")

local drag_region = frame:CreateTexture(nil, "BACKGROUND")
drag_region:SetTexture(0,0,0,.5)
drag_region:SetAllPoints()
drag_region:Hide()

local function reAlign()
  local anchor = frame:GetPoint()
  local h_align, v_align
  
  if anchor == "TOPLEFT" then
    h_align, v_align = "LEFT", "TOP"
  end
  
  if anchor == "TOP" then
    h_align, v_align = "CENTER", "TOP"
  end
  
  if anchor == "TOPRIGHT" then
    h_align, v_align = "RIGHT", "TOP"
  end
  
  if anchor == "LEFT" then
    h_align, v_align = "LEFT", "MIDDLE"
  end
  
  if anchor == "CENTER" then
    h_align, v_align = "CENTER", "MIDDLE"
  end
  
  if anchor == "RIGHT" then
    h_align, v_align = "RIGHT", "MIDDLE"
  end
  
  if anchor == "BOTTOMLEFT" then
    h_align, v_align = "LEFT", "BOTTOM"
  end
  
  if anchor == "BOTTOM" then
    h_align, v_align = "CENTER", "BOTTOM"
  end
  
  if anchor == "BOTTOMRIGHT" then
    h_align, v_align = "RIGHT", "BOTTOM"
  end
  
  text_frame:SetJustifyH(h_align)
  text_frame:SetJustifyV(v_align)
end

frame:SetScript("OnDragStart", function(self)
  self:SetScript("OnDragStop", function (self)
    self:SetScript("OnDragStop", nil)
    self:StopMovingOrSizing()
    drag_region:Hide()
    reAlign()
  end)
  
  self:StartMoving()
  drag_region:Show()
end)

frame:RegisterForDrag("LeftButton")

function frame:OnEvent(event, ...)
  return self[event](self, ...)
end

frame:SetScript("OnEvent", frame.OnEvent)

local halflife = 5*60 -- 5 minutes.
local sum, weight, last_update = 0, 0, GetTime()
local expected_kills, displayed_kills = 0, 0

local function groupInfo()
  local mult = 1
  local size = 1
  local player_level = UnitLevel("player")
  local level_sum = player_level
  local highest_level = player_level
  
  if GetNumGroupMembers() > 0 then
    level_sum = 0
    size = 0
    
    for i = 1,40 do
      local id = "raid"..i
      local level = UnitIsVisible(id) and UnitLevel(id)
      if level then
        level_sum = level_sum + level
        highest_level = math.max(highest_level, level)
        size = size + 1
      end
    end
    
    -- Don't actually know the experience multiplier for raids, so this is probably wrong.
    mult = .5
  else
    for i = 1,4 do
      local id = "group"..i
      local level = UnitIsVisible(id) and UnitLevel(id)
      if level then
        level_sum = level_sum + level
        highest_level = math.max(highest_level, level)
        size = size + 1
      end
    end
    
    if size == 3 then mult = 1.166
    elseif size == 4 then mult = 1.3
    elseif size == 5 then mult = 1.4 end
  end
  
  return player_level, level_sum, mult, highest_level
end

local function calcKills()
  local needed = UnitXPMax("player") - UnitXP("player")
  
  local scale = math.pow(0.5, (GetTime()-last_update)/halflife)
  local trust = weight*scale
  
  local player_level, level_sum, mult, highest_level = groupInfo()
  
  local average
  
  if weight == 0 then
    average = highest_level * 5 + 45
  elseif trust < 1 then
    average = sum*scale + (highest_level * 5 + 45)*(1-trust)
  else
    average = sum/weight
  end
  
  average = average * player_level / level_sum * mult
  
  if average <= 0 then
    return 99999, 0
  end
  
  local rested = GetXPExhaustion() or 0
  
  if rested >= needed then
    return math.min(math.ceil(needed*0.5/average), 99999), trust
  else
    return math.min(math.ceil((2*needed-rested)/(2*average)), 99999), trust
  end
end

local ani_speed = 1

local function setCount(num, r, g, b, i)
  r, g, b = 1+r*i-i, 1+g*i-i, 1+b*i-i
  text_frame:SetFormattedText("Kills to Level: |cff%02x%02x%02x%d", r*255, g*255, b*255, num)
end

local ani_pct = 0

function frame:OnUpdate_Animate(delta)
  ani_pct = ani_pct + delta * ani_speed
  
  if ani_pct >= 1 then
    displayed_kills = expected_kills
    setCount(expected_kills, 1, 1, 1, 0)
    self:SetScript("OnUpdate", nil)
    ani_pct = 0
  else
    local value = math.floor(expected_kills*ani_pct+displayed_kills*(1-ani_pct)+0.5)
    local intensity = ani_pct*2-1
    intensity = 1 - intensity * intensity
    
    if displayed_kills > expected_kills then
      setCount(value, 0, 1, 0, intensity)
    else
      setCount(value, 1, 0, 0, intensity)
    end
  end
end

local force_update = false
local old_xp = 0

function frame:OnUpdate_Check()
  -- Wait for the API to start returning the correct values.
  if UnitXP("player") == old_xp then return end
  old_xp = UnitXP("player")
  
  local projected_kills, trust = calcKills()
  
  if trust > 1 then
    trust = 1-1/trust
    
    -- If our number looks really wrong, force it to the correct value.
    if expected_kills * trust > projected_kills or
      expected_kills / trust < projected_kills then
      force_update = true
    end
  end
  
  if force_update then
    expected_kills = projected_kills
    force_update = false
  end
  
  if displayed_kills ~= expected_kills then
    ani_speed = 1/(math.pow(math.abs(displayed_kills-expected_kills), 0.38))
    
    self:SetScript("OnUpdate", self.OnUpdate_Animate)
  else
    self:SetScript("OnUpdate", nil)
  end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")

function frame:PLAYER_ENTERING_WORLD()
  if UnitLevel("player") == MAX_PLAYER_LEVEL then
    self:Hide()
  else
    old_xp = ("player")
    expected_kills = calcKills()
    displayed_kills = expected_kills
    setCount(expected_kills, 1, 1, 1, 0)
    
    self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:Show()
    reAlign()
    
    self:EnableMouse(not InCombatLockdown())
  end
end

frame:RegisterEvent("ADDON_LOADED")

function frame:ADDON_LOADED(addon)
  if addon == "KillsToLevel" then
    self:PLAYER_ENTERING_WORLD()
  end
end

frame:RegisterEvent("PLAYER_REGEN_ENABLED")

function frame:PLAYER_REGEN_ENABLED()
  self:EnableMouse(true)
end

frame:RegisterEvent("PLAYER_REGEN_DISABLED")

function frame:PLAYER_REGEN_DISABLED()
  self:EnableMouse(false)
end

local xpgain_bases = {
  "COMBATLOG_XPGAIN_EXHAUSTION1",
  "COMBATLOG_XPGAIN_EXHAUSTION2",
  "COMBATLOG_XPGAIN_EXHAUSTION4",
  "COMBATLOG_XPGAIN_EXHAUSTION5",
  "COMBATLOG_XPGAIN_FIRSTPERSON"
 }

function frame:CHAT_MSG_COMBAT_XP_GAIN(msg)
  local suffix = ""
  
  if GetNumGroupMembers() > 0 then
    suffix = "_RAID"
  elseif GetNumSubgroupMembers() > 1 then
    suffix = "_GROUP"
  end
  
  for i = 1, #xpgain_bases do
    local _, total, bonus, _, group = parse(msg, assert(_G[xpgain_bases[i]..suffix]))
    if total then
      local player_level, level_sum = groupInfo()
      
      local now = GetTime()
      local scale = math.pow(0.5, (now-last_update)/halflife)
      
      sum = sum * scale + (total - ((tonumber(bonus) or 0) + (tonumber(group) or 0))) / level_sum * player_level
      weight = weight * scale + 1
      last_update = now
      
      -- We normally only subtract 1 from the expected number of kills,
      -- to prevent it from jumping all over the place.
      expected_kills = math.max(1, expected_kills - 1)
      
      self:SetScript("OnUpdate", self.OnUpdate_Check)
      return
    end
  end
  
  -- This was probably a quest reward. Force the count to be updated.
  force_update = true
  self:SetScript("OnUpdate", self.OnUpdate_Check)
end

function frame:PLAYER_LEVEL_UP(level)
  if UnitLevel("player") == MAX_PLAYER_LEVEL then
    self:Hide()
  end
end

function frame:GROUP_ROSTER_UPDATE()
  force_update = true
  old_xp = 0 -- XP didn't change, so set it to 0 so that it thinks it did.
  self:SetScript("OnUpdate", self.OnUpdate_Check)
end
