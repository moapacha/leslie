-- leslie
-- a rotating speaker
-- for monome norns
--
-- a tiny pixel-art Leslie cabinet
-- with horn + bass rotors, doppler,
-- AM tremolo, stereo pan, and
-- chorale / tremolo / brake modes.
--
-- E1 . . input drive
-- E2 . . throb (AM depth)
-- E3 . . width (stereo)
-- K2 . . slow / fast
-- K3 . . brake
-- K1 hold . edit mode:
--   E1 doppler  E2 speed (current mode)  E3 crossover

engine.name = "Leslie"

-- mode state
local MODE_SLOW, MODE_FAST, MODE_BRAKE = 1, 2, 3
local mode = MODE_SLOW
local prev_mode = MODE_SLOW
local mode_names = { "slow", "fast", "brake" }

-- displayed (smoothed) rates, for animating the rotors on screen.
-- the engine smooths internally with Lag; we mirror that here so
-- the on-screen drum visibly spins up / down with the audio.
local horn_cur = 0
local bass_cur = 0
local horn_phase = 0
local bass_phase = 0

local screen_dirty = true
local anim_id
local k1_held = false

-- ---------------------------------------------------------------
-- params
-- ---------------------------------------------------------------

local function add_params()
  params:add_separator("leslie")

  params:add_group("rates", 6)
  params:add_control("horn_slow", "horn slow", controlspec.new(0.1, 3.0, "lin", 0.01, 0.8, "hz"))
  params:add_control("horn_fast", "horn fast", controlspec.new(1.0, 12.0, "lin", 0.01, 6.8, "hz"))
  params:add_control("bass_slow", "bass slow", controlspec.new(0.1, 3.0, "lin", 0.01, 0.7, "hz"))
  params:add_control("bass_fast", "bass fast", controlspec.new(1.0, 10.0, "lin", 0.01, 5.6, "hz"))
  params:add_control("horn_accel", "horn accel", controlspec.new(0.05, 5.0, "lin", 0.01, 0.5, "s"))
  params:set_action("horn_accel", function(v) engine.hornAccel(v) end)
  params:add_control("bass_accel", "bass accel", controlspec.new(0.1, 5.0, "lin", 0.01, 1.2, "s"))
  params:set_action("bass_accel", function(v) engine.bassAccel(v) end)
  params:set_action("horn_slow", function() if mode == MODE_SLOW then push_speeds() end end)
  params:set_action("horn_fast", function() if mode == MODE_FAST then push_speeds() end end)
  params:set_action("bass_slow", function() if mode == MODE_SLOW then push_speeds() end end)
  params:set_action("bass_fast", function() if mode == MODE_FAST then push_speeds() end end)

  params:add_group("doppler & AM", 4)
  params:add_control("horn_dopp", "horn doppler", controlspec.new(0, 0.005, "lin", 0.0001, 0.0012, "s"))
  params:set_action("horn_dopp", function(v) engine.hornDopp(v) end)
  params:add_control("bass_dopp", "bass doppler", controlspec.new(0, 0.010, "lin", 0.0001, 0.0022, "s"))
  params:set_action("bass_dopp", function(v) engine.bassDopp(v) end)
  params:add_control("horn_am", "horn throb", controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("horn_am", function(v) engine.hornAm(v) end)
  params:add_control("bass_am", "bass throb", controlspec.new(0, 1, "lin", 0.01, 0.4))
  params:set_action("bass_am", function(v) engine.bassAm(v) end)

  params:add_group("output", 4)
  params:add_control("width", "stereo width", controlspec.new(0, 1, "lin", 0.01, 1.0))
  params:set_action("width", function(v) engine.width(v) end)
  params:add_control("drive", "drive", controlspec.new(0.25, 4, "lin", 0.01, 1.0))
  params:set_action("drive", function(v) engine.drive(v) end)
  params:add_control("mix", "wet/dry", controlspec.new(0, 1, "lin", 0.01, 1.0))
  params:set_action("mix", function(v) engine.mix(v) end)
  params:add_control("xfreq", "crossover", controlspec.new(200, 2000, "exp", 1, 800, "hz"))
  params:set_action("xfreq", function(v) engine.xfreq(v) end)
end

-- push the right rate values to the engine for the current mode.
-- brake is a separate engine flag that multiplies rate by ~0.
function push_speeds()
  if mode == MODE_SLOW then
    engine.hornRate(params:get("horn_slow"))
    engine.bassRate(params:get("bass_slow"))
    engine.brake(0)
  elseif mode == MODE_FAST then
    engine.hornRate(params:get("horn_fast"))
    engine.bassRate(params:get("bass_fast"))
    engine.brake(0)
  elseif mode == MODE_BRAKE then
    -- keep the last rate values but engage brake
    engine.brake(1)
  end
end

local function set_mode(m)
  if m ~= MODE_BRAKE then prev_mode = m end
  mode = m
  push_speeds()
  screen_dirty = true
end

-- ---------------------------------------------------------------
-- init
-- ---------------------------------------------------------------

function init()
  add_params()

  -- audio routing for an effect: input is read by SoundIn in the engine,
  -- so we just kill the direct passthrough so the user doesn't hear dry+wet.
  audio.level_monitor(0)

  params:bang()
  set_mode(MODE_SLOW)

  -- 30fps animation: lerp displayed rates toward target, accumulate phase
  anim_id = clock.run(function()
    local last = util.time()
    while true do
      clock.sleep(1/30)
      local now = util.time()
      local dt = now - last
      last = now

      local target_h, target_b
      if mode == MODE_BRAKE then
        target_h, target_b = 0, 0
      elseif mode == MODE_FAST then
        target_h = params:get("horn_fast")
        target_b = params:get("bass_fast")
      else
        target_h = params:get("horn_slow")
        target_b = params:get("bass_slow")
      end

      local h_acc = params:get("horn_accel")
      local b_acc = params:get("bass_accel")
      -- one-pole lerp matching Lag time-constant: alpha = 1 - exp(-dt / tau)
      horn_cur = horn_cur + (target_h - horn_cur) * (1 - math.exp(-dt / h_acc))
      bass_cur = bass_cur + (target_b - bass_cur) * (1 - math.exp(-dt / b_acc))

      horn_phase = (horn_phase + horn_cur * dt) % 1
      bass_phase = (bass_phase - bass_cur * dt) % 1

      redraw()
    end
  end)
end

-- ---------------------------------------------------------------
-- input
-- ---------------------------------------------------------------

function key(n, z)
  if n == 1 then
    -- K1 momentary: enables encoder edit mode while held
    k1_held = (z == 1)
    screen_dirty = true
    return
  end
  if z == 0 then return end
  if n == 2 then
    -- slow / fast toggle (always lands on a non-brake mode)
    if mode == MODE_SLOW then
      set_mode(MODE_FAST)
    else
      set_mode(MODE_SLOW)
    end
  elseif n == 3 then
    -- brake toggle, returns to whatever non-brake mode was last active
    if mode == MODE_BRAKE then
      set_mode(prev_mode)
    else
      set_mode(MODE_BRAKE)
    end
  end
end

function enc(n, d)
  if k1_held then
    -- edit mode: fine-tune deeper params
    if n == 1 then
      -- doppler depth, both rotors (bass at ~2x scale, like the defaults)
      params:delta("horn_dopp", d)
      params:delta("bass_dopp", d * 2)
    elseif n == 2 then
      -- speed of whichever mode is currently selected
      if mode == MODE_FAST then
        params:delta("horn_fast", d)
        params:delta("bass_fast", d)
      else
        -- slow rates (also when in brake — pre-stages slow target)
        params:delta("horn_slow", d)
        params:delta("bass_slow", d)
      end
    elseif n == 3 then
      params:delta("xfreq", d)
    end
  else
    -- normal mode: input drive / throb / width
    if n == 1 then
      params:delta("drive", d)
    elseif n == 2 then
      -- throb: link both rotors but keep bass slightly lighter
      local v = util.clamp(params:get("horn_am") + d * 0.01, 0, 1)
      params:set("horn_am", v)
      params:set("bass_am", v * 0.8)
    elseif n == 3 then
      params:delta("width", d)
    end
  end
  screen_dirty = true
end

-- ---------------------------------------------------------------
-- screen
-- ---------------------------------------------------------------

-- one filled tapered cone: a horn flare from pivot (cx,cy) to mouth (mx,my).
-- visibility shrinks the bell when the assembly is rotated end-on, so the
-- bowtie smoothly thins to a line and back as it spins.
local function draw_horn_flare(cx, cy, mx, my, ah)
  local dx, dy = mx - cx, my - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.5 then return end
  dx, dy = dx / len, dy / len
  local px, py = -dy, dx

  local visibility = math.abs(math.cos(ah)) * 0.7 + 0.3
  local bell = 2.5 * visibility
  local throat = 0.5

  -- cone body
  screen.level(8)
  screen.move(cx + px * throat, cy + py * throat)
  screen.line(mx + px * bell,   my + py * bell)
  screen.line(mx - px * bell,   my - py * bell)
  screen.line(cx - px * throat, cy - py * throat)
  screen.fill()

  -- bright rim across the bell mouth (the round opening, edge-on)
  screen.level(15)
  screen.move(mx + px * bell, my + py * bell)
  screen.line(mx - px * bell, my - py * bell)
  screen.stroke()
end

function redraw()
  screen.clear()
  screen.aa(0)

  -- ====== cabinet ======
  local cx_l, cx_r = 4, 40
  local cy_t, cy_b = 4, 58

  screen.level(5)
  screen.rect(cx_l, cy_t, cx_r - cx_l, cy_b - cy_t)
  screen.stroke()

  -- top vent slats (where the horn radiates)
  screen.level(2)
  for i = 0, 3 do
    screen.move(cx_l + 3, 7 + i * 2)
    screen.line(cx_r - 3, 7 + i * 2)
    screen.stroke()
  end

  screen.level(3)
  screen.move(cx_l, 14)
  screen.line(cx_r, 14)
  screen.stroke()

  -- ====== horn rotor: bowtie of two flared bells ======
  -- a real Leslie horn assembly has TWO bells facing opposite directions
  -- on a single rotating arm. only one carries the driver; the other
  -- balances the rotation. visually they're identical, so we draw them
  -- the same.
  local hcx, hcy = 22, 22
  local hrx, hry = 8, 3
  local ah = horn_phase * 2 * math.pi
  local hx1 = hcx + math.cos(ah) * hrx
  local hy1 = hcy + math.sin(ah) * hry
  local hx2 = hcx - math.cos(ah) * hrx
  local hy2 = hcy - math.sin(ah) * hry

  draw_horn_flare(hcx, hcy, hx1, hy1, ah)
  draw_horn_flare(hcx, hcy, hx2, hy2, ah)

  -- pivot stub
  screen.level(4)
  screen.rect(hcx - 1, hcy, 2, 1)
  screen.fill()

  screen.level(3)
  screen.move(cx_l, 32)
  screen.line(cx_r, 32)
  screen.stroke()

  -- ====== bass drum ======
  local bcx, bcy = 22, 44
  local ab = bass_phase * 2 * math.pi
  screen.level(6)
  screen.circle(bcx, bcy, 8)
  screen.stroke()
  -- spinning marker (the slot in the drum face)
  local bmx = bcx + math.cos(ab) * 7
  local bmy = bcy + math.sin(ab) * 3.5
  screen.level(15)
  screen.circle(bmx, bmy, 1.5)
  screen.fill()
  screen.level(8)
  screen.rect(bcx - 1, bcy, 2, 1)
  screen.fill()

  -- legs
  screen.level(3)
  screen.rect(cx_l + 2, cy_b, 1, 2)
  screen.fill()
  screen.rect(cx_r - 3, cy_b, 1, 2)
  screen.fill()

  -- ====== right panel ======
  -- column layout, anchored so labels never collide with values.
  -- the widest labels ("width", "throb") render ~20 px wide; values like
  -- "1.00" / "800" run ~16 / 12 px; we leave at least 7 px of empty
  -- space between every label and value so nothing visually touches.
  --   xL  (label A)  xLV (value A)   xR  (label B)  xRV (value B)
  local xL, xLV, xR, xRV = 44, 72, 96, 114

  -- title; edit-mode badge sits at the top-right corner so it stays
  -- in a fixed, predictable spot regardless of what's in the title.
  screen.level(15)
  screen.move(xL, 8)
  screen.text("~leslie~")
  if k1_held then
    screen.move(122, 8)
    screen.text("*")
  end

  -- mode row: three options, current bright, others dim
  -- (xL=44: slow@44, fast@66, brake@88 — "brake" ends ~108, fits cleanly)
  local mode_xs = { xL, xL + 22, xL + 44 }
  for i = 1, 3 do
    screen.level(mode == i and 15 or 3)
    screen.move(mode_xs[i], 18)
    screen.text(mode_names[i])
  end

  -- compute target rate for the tach (so display reflects mode change
  -- the instant the user toggles, instead of waiting for the lerp)
  local target_h, target_b = 0, 0
  if mode == MODE_SLOW then
    target_h = params:get("horn_slow")
    target_b = params:get("bass_slow")
  elseif mode == MODE_FAST then
    target_h = params:get("horn_fast")
    target_b = params:get("bass_fast")
  end

  -- the value K1+E2 currently edits (slow rate or fast rate)
  local speed_edit_val
  if mode == MODE_FAST then
    speed_edit_val = params:get("horn_fast")
  else
    speed_edit_val = params:get("horn_slow")
  end

  -- two columns of params: left = normal-mode (E1/E2/E3), right = K1 edit
  -- mode (E1/E2/E3 alternative). active set is bright, the other dim.
  local lvl_n = k1_held and 3 or 15
  local lvl_e = k1_held and 15 or 3

  local rows = {
    { y = 30,
      la = "drive", va = string.format("%.2f", params:get("drive")),
      lb = "dop",   vb = string.format("%.1f", params:get("horn_dopp") * 1000) },
    { y = 38,
      la = "throb", va = string.format("%.2f", params:get("horn_am")),
      lb = "spd",   vb = string.format("%.1f", speed_edit_val) },
    { y = 46,
      la = "width", va = string.format("%.2f", params:get("width")),
      lb = "xov",   vb = string.format("%d",   params:get("xfreq")) },
  }

  for _, r in ipairs(rows) do
    screen.level(lvl_n)
    screen.move(xL, r.y);  screen.text(r.la)
    screen.move(xLV, r.y); screen.text(r.va)

    screen.level(lvl_e)
    screen.move(xR, r.y);  screen.text(r.lb)
    screen.move(xRV, r.y); screen.text(r.vb)
  end

  -- tach: target rate (immediate), with rotor visual showing the lerped value
  screen.level(2)
  screen.move(xL, 58)
  screen.text("h ")
  screen.level(8)
  screen.text(string.format("%.1f", target_h))
  screen.level(2)
  screen.move(xL + 32, 58)
  screen.text("b ")
  screen.level(8)
  screen.text(string.format("%.1f", target_b))

  screen.update()
end

function cleanup()
  if anim_id then clock.cancel(anim_id) end
end
