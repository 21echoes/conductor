-- Conductor
--  an LFO designer
--  for grid & crow
--
-- LFO is clocked via system
-- (per-output clock division
--  configured in params)
--
-- Norns
-- -----
-- K2 stops playback
-- K3 resumes playback
--
-- Grid
-- ----
-- Grid "zoomed out":
-- Every 2 rows
--  controls 1 crow output
-- 1st row in pair shows the
--  LFO shape via brightness.
--  You can also hold buttons
--  to set start & end points.
-- 2nd row in pair:
--  left buttons paginate
--  right buttons:
--    play/pause
--    mute/unmute
--    zoom in
--
-- Grid "zoomed in":
-- Top 7 rows set voltage level
-- Last row:
--  Left buttons paginate
--  Mid buttons switch tracks
--  Right buttons:
--    play/pause
--    mute/unmute
--    zoom out
--
--
-- Additional per-output params
-- in params menu:
--  * enable/disable
--  * swing
--  * delay
--  * slew shape
--  * min & max voltage
--
--
-- v0.0.2 @21echoes
local current_version = "0.0.2"

local Sequencer = include('lib/sequencer')
local UIState = include('lib/ui/util/devices')
local GridUI = include('lib/ui/grid')
local Label = include("lib/ui/util/label")

local sequencer
local ui_refresh_metro
local fps = 60
local stop_label
local play_label

function init()
  math.randomseed(os.time())
  init_params()
  init_sequencer()
  GridUI.init(sequencer)
  UIState.init_screen({
    refresh_callback = function() redraw() end
  })
  init_ui()
  params:bang()
  init_ui_metro()
  sequencer:start()
end

function init_params()
  params:add_separator('Conductor')
end

function init_sequencer()
  sequencer = Sequencer:new()
  sequencer:init_params()
end

function init_ui()
  stop_label = Label.new({x=0, y=63, text="STOP", font_size=16})
  play_label = Label.new({x=64, y=63, text="PLAY", font_size=16})
end

function init_ui_metro()
  ui_refresh_metro = metro.init()
  if ui_refresh_metro == nil then
    print("unable to start ui refresh metro")
  end
  ui_refresh_metro.event = UIState.refresh
  ui_refresh_metro.time = 1/fps
  ui_refresh_metro:start()
end

function key(n, z)
  if z ~= 1 then return end
  if n == 2 then
    sequencer:stop()
  elseif n == 3 then
    sequencer:start()
  end
end

function enc(n, delta)
  -- TODO?
end

function redraw()
  screen.clear()

  if sequencer:get_is_playing() then
    play_label.level = 15
    stop_label.level = 6
  else
    play_label.level = 6
    stop_label.level = 15
  end
  stop_label:redraw()
  play_label:redraw()

  screen.update()
end

function clock.transport.start()
  if sequencer then
    sequencer:start()
  end
end

function clock.transport.stop()
  if sequencer then
    sequencer:stop()
  end
end

function cleanup()
  params:write()
  sequencer:cleanup()
  GridUI.cleanup()
  if ui_refresh_metro then
    metro.free(ui_refresh_metro.id)
    ui_refresh_metro = nil
  end
end
