local UIState = require('conductor/lib/ui/util/devices')

-- Make sure there's only one copy
if _Grid ~= nil then return _Grid end

local NUM_OUTPUTS = 4
local MAX_LENGTH = 32
local MAX_VALUE = 6
local MIN_VALUE = 0

local HEIGHT = 8
local CLICK_TIME = 0.7

local MAX_VALUE_LEVEL = 15
local MIN_VALUE_LEVEL = 5
local INACTIVE_VALUE_LEVEL = 3
-- TODO: not one playpos, as different tracks have different clock divs
-- maybe... blinking? ugh
-- local PLAYPOS_LEVEL = 7
local ACTIVE_ALT_LEVEL = 15
local INACTIVE_ALT_LEVEL = 4
local ACTIVE_PAGE_LEVEL = 15
local INACTIVE_PAGE_LEVEL = 4
local CLEAR_LEVEL = 0

local Overview = {}
local OneTrack = {track=1}

local Grid = {
  connected_grid = nil,
  grid_width = 16,
  page_numbers = {1, 1, 1, 1}, -- length NUM_OUTPUTS
  held_keys_down = {nil, nil, nil, nil}, -- length NUM_OUTPUTS
  mode = Overview,
}

function Grid.init(sequencer)
  local device = grid.connect()
  UIState.init_grid({
    device = device,
    key_callback = function(x, y, state) Grid._key_callback(sequencer, x, y, state) end,
    refresh_callback = function(my_grid) Grid._refresh_callback(sequencer, my_grid) end,
    width_changed_callback = function(new_width) Grid._width_changed_callback(sequencer, new_width) end,
  })
end

function Grid._key_callback(sequencer, x, y, state)
  Grid.mode.key_callback(sequencer, x, y, state)
  UIState.grid_dirty = true
  UIState.flash_event()
end

function Grid._refresh_callback(sequencer, my_grid)
  Grid.connected_grid = my_grid
  for x=1,Grid.grid_width do
    for y=1,HEIGHT do
      Grid.mode.refresh_grid_button(sequencer, x, y)
    end
  end
end

function Grid._width_changed_callback(sequencer, new_width)
  Grid.grid_width = new_width
  Grid.page_numbers = {1,1,1,1} -- length NUM_OUTPUTS
  UIState.grid_dirty = true
end

function Grid.cleanup()
  if Grid.connected_grid and Grid.connected_grid.device then
    Grid.connected_grid:all(0)
    Grid.connected_grid:refresh()
  end
end

function Grid._sequencer_pos(output, grid_x)
  local page_number = Grid.page_numbers[output]
  return grid_x + (Grid.grid_width * (page_number - 1))
end

function Grid._last_page_number()
  return math.ceil(MAX_LENGTH / Grid.grid_width)
end

------------------
-- Trigger mode --
------------------
-- 4 pairs of 2 rows
-- in each pair, row 1 is the values
-- clicking a value: jump playhead to cell
-- hold a value, click another value: set start and end points
-- row 2, rightmost cell: enter OneTrack mode
-- row 2, second from rightmost cell: mute/unmute track
-- row 2, thirrd from rightmost cell: play/pause track
-- row 2, leftmost N cells: scroll to page N

function Overview.refresh_grid_button(sequencer, x, y)
  local output = math.ceil(y / 2)
  local is_values_row = (y % 2) == 1
  if is_values_row then
    local sequencer_x = Grid._sequencer_pos(output, x)
    local value = sequencer:get_value(output, sequencer_x)
    if value ~= nil then
      local is_active_value = sequencer_x >= params:get(output..'_start_point') and sequencer_x <= params:get(output..'_end_point')
      if is_active_value then
        local level = util.linlin(MIN_VALUE, MAX_VALUE, MIN_VALUE_LEVEL, MAX_VALUE_LEVEL, value)
        Grid.connected_grid:led(x, y, util.round(level))
      else
        Grid.connected_grid:led(x, y, INACTIVE_VALUE_LEVEL)
      end
    else
      Grid.connected_grid:led(x, y, CLEAR_LEVEL)
    end
  else
    if x == Grid.grid_width then -- Jump to OneTrack
      Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
    elseif x == Grid.grid_width - 1 then -- mute/unmute
      if params:get(output..'_muted') == 1 then
        Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
      else
        Grid.connected_grid:led(x, y, INACTIVE_ALT_LEVEL)
      end
    elseif x == Grid.grid_width - 2 then -- play/pause
      if params:get(output..'_playing') == 1 then
        Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
      else
        Grid.connected_grid:led(x, y, INACTIVE_ALT_LEVEL)
      end
    else -- Show page N
      local page_number = Grid.page_numbers[output]
      if x == page_number then
        Grid.connected_grid:led(x, y, ACTIVE_PAGE_LEVEL)
      elseif x <= Grid._last_page_number() then
        Grid.connected_grid:led(x, y, INACTIVE_PAGE_LEVEL)
      else
        Grid.connected_grid:led(x, y, CLEAR_LEVEL)
      end
    end
  end
end

function Overview.key_callback(sequencer, x, y, state)
  local output = math.ceil(y / 2)
  local is_values_row = (y % 2) == 1
  if is_values_row then
    local sequencer_x = Grid._sequencer_pos(output, x)
    if state == 1 then
      if not Grid.held_keys_down[output] then
        Grid.held_keys_down[output] = {sequencer_x, util.time()}
      end
    else
      local was_click = true
      if Grid.held_keys_down[output] then
        local was_release = Grid.held_keys_down[output][1] == sequencer_x
        if was_release then
          local time_between = util.time() - Grid.held_keys_down[output][2]
          if time_between > CLICK_TIME then
            was_click = false
          end
        else
          was_click = false
          local new_start_point = math.min(sequencer_x, Grid.held_keys_down[output][1])
          local new_end_point = math.max(sequencer_x, Grid.held_keys_down[output][1])
          params:set(output..'_start_point', new_start_point)
          params:set(output..'_end_point', new_end_point)
        end
        Grid.held_keys_down[output] = nil
      end
      if was_click then
        sequencer:set_playhead(output, sequencer_x)
      end
    end
  else
    if state == 1 then
      if x == Grid.grid_width then -- Jump to OneTrack
        Grid.held_keys_down = {nil, nil, nil, nil} -- length NUM_OUTPUTS
        OneTrack.track = output
        Grid.mode = OneTrack
      elseif x == Grid.grid_width - 1 then -- mute/unmute
        if params:get(output..'_muted') == 1 then
          params:set(output..'_muted', 2)
        else
          params:set(output..'_muted', 1)
        end
      elseif x == Grid.grid_width - 2 then -- play/pause
        if params:get(output..'_playing') == 1 then
          params:set(output..'_playing', 2)
        else
          params:set(output..'_playing', 1)
        end
      else -- Show page N
        if x <= Grid._last_page_number() then
          Grid.page_numbers[output] = x
        end
      end
    end
  end
end

------------------------
-- OneTrack mode --
------------------------
-- top 7 rows are the values in sequence
-- bottom row is meta:
-- page buttons, then jump buttons, then pause & mute & back button at the end
-- page buttons let you jump to page N
-- jump buttons let you jump to *track* N
-- back button takes back to Overview

function OneTrack._can_fit_track_jump()
  return (Grid._last_page_number() + 1 + NUM_OUTPUTS + 1 + 3) <= Grid.grid_width
end

function OneTrack.refresh_grid_button(sequencer, x, y)
  if y == HEIGHT then
    if x == Grid.grid_width then -- Back to Overview
      Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
    elseif x == Grid.grid_width - 1 then -- mute/unmute
      if params:get(OneTrack.track..'_muted') == 1 then
        Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
      else
        Grid.connected_grid:led(x, y, INACTIVE_ALT_LEVEL)
      end
    elseif x == Grid.grid_width - 2 then -- play/pause
      if params:get(OneTrack.track..'_playing') == 1 then
        Grid.connected_grid:led(x, y, ACTIVE_ALT_LEVEL)
      else
        Grid.connected_grid:led(x, y, INACTIVE_ALT_LEVEL)
      end
    elseif x <= Grid._last_page_number() then
      local page_number = Grid.page_numbers[OneTrack.track]
      if x == page_number then
        Grid.connected_grid:led(x, y, ACTIVE_PAGE_LEVEL)
      elseif x <= Grid._last_page_number() then
        Grid.connected_grid:led(x, y, INACTIVE_PAGE_LEVEL)
      else
        Grid.connected_grid:led(x, y, CLEAR_LEVEL)
      end
    elseif OneTrack._can_fit_track_jump() then
      local track_number = x - (Grid._last_page_number() + 1)
      if track_number >= 1 and track_number <= NUM_OUTPUTS then
        if track_number == OneTrack.track then
          Grid.connected_grid:led(x, y, ACTIVE_PAGE_LEVEL)
        else
          Grid.connected_grid:led(x, y, INACTIVE_PAGE_LEVEL)
        end
      else
        Grid.connected_grid:led(x, y, CLEAR_LEVEL)
      end
    else
      Grid.connected_grid:led(x, y, CLEAR_LEVEL)
    end
  else
    local sequencer_x = Grid._sequencer_pos(OneTrack.track, x)
    local value = sequencer:get_value(OneTrack.track, sequencer_x)
    local y_for_value = nil
    if value ~= nil then
      -- util.linlin doesn't let you map to a range where dlo>dhi,
      -- so this is adapted from util.linlin without that "bug"
      y_for_value = (value-MIN_VALUE) / (MAX_VALUE-MIN_VALUE) * (1-(HEIGHT-1)) + (HEIGHT-1)
    end
    if y == y_for_value then
      local is_active_value = sequencer_x >= params:get(OneTrack.track..'_start_point') and sequencer_x <= params:get(OneTrack.track..'_end_point')
      if is_active_value then
        Grid.connected_grid:led(x, y, MAX_VALUE_LEVEL)
      else
        Grid.connected_grid:led(x, y, INACTIVE_VALUE_LEVEL)
      end
    else
      Grid.connected_grid:led(x, y, CLEAR_LEVEL)
    end
  end
end

function OneTrack.key_callback(sequencer, x, y, state)
  if y == HEIGHT then
    if state == 1 then
      if x == Grid.grid_width then
        Grid.held_keys_down = {nil, nil, nil, nil} -- length NUM_OUTPUTS
        Grid.mode = Overview
      elseif x == Grid.grid_width - 1 then -- mute/unmute
        if params:get(OneTrack.track..'_muted') == 1 then
          params:set(OneTrack.track..'_muted', 2)
        else
          params:set(OneTrack.track..'_muted', 1)
        end
      elseif x == Grid.grid_width - 2 then -- play/pause
        if params:get(OneTrack.track..'_playing') == 1 then
          params:set(OneTrack.track..'_playing', 2)
        else
          params:set(OneTrack.track..'_playing', 1)
        end
      elseif x <= Grid._last_page_number() then
        Grid.page_numbers[OneTrack.track] = x
      elseif OneTrack._can_fit_track_jump() then
        OneTrack.track = x - (Grid._last_page_number() + 1)
      end
    end
  else
    local sequencer_x = Grid._sequencer_pos(OneTrack.track, x)
    if state == 1 then
      if not Grid.held_keys_down[OneTrack.track] then
        Grid.held_keys_down[OneTrack.track] = {sequencer_x, util.time()}
      end
    else
      local was_click = true
      if Grid.held_keys_down[OneTrack.track] then
        local was_release = Grid.held_keys_down[OneTrack.track][1] == sequencer_x
        if was_release then
          local time_between = util.time() - Grid.held_keys_down[OneTrack.track][2]
          if time_between > CLICK_TIME then
            was_click = false
          end
        else
          was_click = false
          local new_start_point = math.min(sequencer_x, Grid.held_keys_down[OneTrack.track][1])
          local new_end_point = math.max(sequencer_x, Grid.held_keys_down[OneTrack.track][1])
          params:set(OneTrack.track..'_start_point', new_start_point)
          params:set(OneTrack.track..'_end_point', new_end_point)
        end
        Grid.held_keys_down[OneTrack.track] = nil
      end
      if was_click then
        -- util.linlin doesn't let you map to a range where dlo>dhi,
        -- so this is adapted from util.linlin without that "bug"
        local value = (y - (HEIGHT - 1)) / (1 - (HEIGHT - 1)) * (MAX_VALUE-MIN_VALUE) + MIN_VALUE
        sequencer:set_value(OneTrack.track, sequencer_x, value)
      end
    end
  end
end

-- Make sure there's only one copy
if _Grid == nil then
  _Grid = Grid
end
return _Grid
