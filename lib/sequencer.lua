local Lattice = require('lattice')
local ControlSpec = require('controlspec')
local UIState = include('lib/ui/util/devices')

local Sequencer = {}

local NUM_OUTPUTS = 4
local METER = 4
local MAX_LENGTH = 32
local DEFAULT_LENGTH = 8
local MIN_VALUE = 0
local MAX_VALUE = 6
local MIN_VOLTS = -5
local MAX_VOLTS = 10
local MIN_SEPARATION = 0.01

function Sequencer:new()
  i = {}
  setmetatable(i, self)
  self.__index = self

  i.values = {}
  i.value_indices = {}
  i.patterns = {}
  i:_init_values()
  i:_init_lattice()

  return i
end

function Sequencer:_init_values()
  for o = 1,NUM_OUTPUTS do
    self.values[o] = {}
    for i = 1,DEFAULT_LENGTH do
      self.values[o][i] = util.round(util.linlin(1, DEFAULT_LENGTH, MIN_VALUE, MAX_VALUE, i))
    end
    self.value_indices[o] = 0
  end
end

function Sequencer:_init_lattice()
  self.lattice = Lattice:new({
    meter=METER
  })
  local s = self
  for o = 1,NUM_OUTPUTS do
    self.patterns[o] = self.lattice:new_pattern({
      action = function(t) s:_lattice_action(o, t) end
    })
  end
end

function Sequencer:init_params()
  local s = self
  for o = 1,NUM_OUTPUTS do
    params:add_group('Output '..o, 10)
    params:add_option(o..'_enabled', 'Enabled', {'On', 'Off'})
    params:set_action(o..'_enabled', function(val) s:_update_pattern(o, {enabled=(val==1)}) end)
    params:add_number(o..'_start_point', 'Start Point', 1, MAX_LENGTH - 1, 1)
    params:add_number(o..'_end_point', 'End Point', 2, MAX_LENGTH, 8)
    -- TODO: direction
    params:add_number(o..'_div_numerator', 'Clock Div: Numerator', 1, nil, 1)
    params:set_action(o..'_div_numerator', function(val) s:_update_pattern(o, {numerator=val}) end)
    params:add_number(o..'_div_denominator', 'Clock Div: Denominator', 1, nil, 1)
    params:set_action(o..'_div_denominator', function(val) s:_update_pattern(o, {denominator=val}) end)
    params:add_number(o..'_swing', 'Swing', 0, 100, 50)
    params:set_action(o..'_swing', function(val) s:_update_pattern(o, {swing=val}) end)
    params:add_taper(o..'_delay', 'Delay', 0, 100, 0, 0, '%')
    params:set_action(o..'_delay', function(val) s:_update_pattern(o, {delay=val}) end)
    params:add_option(o..'_slew_shape', 'Slew Shape', {'Sine', 'Triangle', 'Square'})
    params:set_action(o..'_slew_shape', function(val) s:_update_slew_shape(o, val) end)
    params:add_control(o..'_min_volts', "Min Volts", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", MIN_SEPARATION, MIN_VOLTS, 'V'))
    params:set_action(o..'_min_volts', function(value)
      if params:get(o..'_max_volts') < value + MIN_SEPARATION then
        params:set(o..'_max_volts', value + MIN_SEPARATION)
      end
    end)
    params:add_control(o..'_max_volts', "Max Volts", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", MIN_SEPARATION, -MIN_VOLTS, 'V'))
    params:set_action(o..'_max_volts', function(value)
      if params:get(o..'_min_volts') > value - MIN_SEPARATION then
        params:set(o..'_min_volts', value - MIN_SEPARATION)
      end
    end)
  end
end

function Sequencer:_update_pattern(output, values)
  local enabled = values.enabled == nil and params:get(output..'_enabled')==1 or values.enabled
  self.patterns[output].enabled = enabled
  local numerator = values.numerator == nil and params:get(output..'_div_numerator') or values.numerator
  local denominator = values.denominator == nil and params:get(output..'_div_denominator') or values.denominator
  if denominator == nil then
    denominator = 1
  end
  self.patterns[output]:set_division(numerator/denominator/METER)
  local swing = values.swing == nil and params:get(output..'_swing') or values.swing
  self.patterns[output]:set_swing(swing)
  local delay = values.delay == nil and params:get(output..'_delay') or values.delay
  self.patterns[output]:set_delay(delay/100)
end

local slew_option_to_crow = {
  'sine', -- Sine
  'linear', -- Triangle
  'now', -- Square. Consider 'wait'? But that breaks things...
}
function Sequencer:_update_slew_shape(output, slew_shape)
  crow.output[output].shape = slew_option_to_crow[slew_shape]
end

function Sequencer:_get_time_to_next_step(output, cur)
  -- TODO: swing, delay, more?
  return clock:get_beat_sec() * (METER * self.patterns[output].division)
end

function Sequencer:_lattice_action(output, step)
  local length = params:get(output..'_end_point') - params:get(output..'_start_point') + 1
  local index_past_start = self.value_indices[output] - params:get(output..'_start_point')
  while index_past_start < 0 do
    index_past_start = index_past_start + length
  end
  local new_index_past_start = (index_past_start + 1) % length
  local value_index = new_index_past_start + params:get(output..'_start_point')
  local value = self.values[output][value_index]
  local volts = 0
  if value ~= nil then
    volts = util.linlin(MIN_VALUE, MAX_VALUE, params:get(output..'_min_volts'), params:get(output..'_max_volts'), value)
  end
  local slew = self:_get_time_to_next_step(output, step)
  crow.output[output].slew = slew
  crow.output[output].volts = volts
  self.value_indices[output] = value_index
end

function Sequencer:start()
  self.lattice:start()
  UIState.screen_dirty = true
end

function Sequencer:stop()
  self.lattice:stop()
  UIState.screen_dirty = true
end

function Sequencer:get_is_playing()
  return self.lattice.enabled
end

function Sequencer:set_value(output, x, value)
  self.values[output][x] = value
end

function Sequencer:get_value(output, x)
  return self.values[output][x]
end

function Sequencer:set_playhead(output, x)
  -- TODO
end

function Sequencer:get_playhead(output, x)
  -- TODO
end

function Sequencer:cleanup()
  self:stop()
  -- TODO: write values to file
end

return Sequencer
