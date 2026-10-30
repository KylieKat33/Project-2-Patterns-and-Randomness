-- Getting a screenshot for the Part 2 of project 2
--the screenshot for the riso is from when I lived in Lisbon Portual over the summer in 2022
-- CONTROLS:
--   S           save the current frame as project2.png (this is the print version)
--   G           bring back the photo named in SCREENSHOT_PHOTO below
--
-- THE PRINT VERSION: the poster is one frame of the animation. Type the name of the
-- photo I want it on in SCREENSHOT_PHOTO below, and when that photo comes up the
-- program saves the frame by itself (or press S whenever I like what I see).

require("L5")

-- ---------------------------------------------------------------
-- SETTINGS
local W, H        = 780, 520      -- 3:2 landscape, inside the 400-800 px print limit
local FPS         = 30
local DAY_SECONDS = 40            -- one full day and night
local DAY_FRAMES  = DAY_SECONDS * FPS

local CELL     = 6                -- size of one dither pixel in the sky
local PLACE_Y  = 0                -- the place photo fills the whole canvas
local PLACE_H  = H - PLACE_Y
local PCELL    = 10               -- size of the pixel blocks when the photo breaks apart
local HOLD_SECONDS     = 5         -- how long each photo stays whole
local DISSOLVE_SECONDS = 3         -- how long it takes to break apart, or build back up
local HOLD_FRAMES     = HOLD_SECONDS * FPS
local DISSOLVE_FRAMES = DISSOLVE_SECONDS * FPS
local TRAIL_LENGTH    = 60         -- how many trail squares follow the owl
local ARC_Y    = H - 60           -- the sun/moon starts and ends low on the picture...
local ARC_H    = 340              -- ...and climbs this high in between
local ARC_X_LEFT  = 60            -- where it rises (left) and sets (right)
local ARC_X_RIGHT = W - 60

local ASSET_DIR = "assets"        -- put the dithered place images in this folder
local SNAP_TO_INKS = true          -- true: every photo pixel is snapped to the nearest ink mix ("i" toggles)

local STAR_COUNT  = 100

-- saving screenshot for the RISO PRINT
local SCREENSHOT_PHOTO = "assets/dithered-images/IMG_4010-dithered.jpg" 
local SHOT_DELAY       = 1
local SHOT_FRAMES      = SHOT_DELAY * FPS

-- ---------------------------------------------------------------
-- THE THREE INKS: the class RISO colors from the Riso Demo
local INK_C = { 0, 120, 191 }     -- blue
local INK_M = { 255, 72, 176 }    -- pink
local INK_Y = { 255, 232, 0 }     -- yellow
local PAPER = { 250, 246, 236 }   -- the paper color

-- Mixes the three inks on paper. Each amount runs from 0 (none) to 1 (full).
-- Inks are see-through, so mixing multiplies them together like a real print.
local function ink(c, m, y)
  local out = {}
  for i = 1, 3 do
    local v = PAPER[i]
    v = v * (1 - c + c * INK_C[i] / 255)
    v = v * (1 - m + m * INK_M[i] / 255)
    v = v * (1 - y + y * INK_Y[i] / 255)
    out[i] = math.floor(v + 0.5)
  end
  return out
end

local function setInk(col)
  fill(col[1], col[2], col[3])
end

-- Every color in the piece comes from this table of ink mixes.
local COL = {
  paper     = ink(0, 0, 0),
  moonLit   = ink(0, 0, 0.35),
  moonDim   = ink(0.6, 0.35, 0),
  sunCore   = ink(0, 0.25, 1),
  sunEdge   = ink(0, 0.5, 1),
  owlBody   = ink(0, 0.4, 0.75),
  owlEye    = ink(0, 0, 0),
  owlBeak   = ink(0, 0.8, 1),
  trailA    = ink(0, 0.45, 0.55),
  trailB    = ink(0.35, 0.25, 0.4),
}

-- ---------------------------------------------------------------
-- THE SKY CYCLE: ink amounts at different times of the day (0 to 1).
-- Each row is: time, then the top of the sky (c, m, y), then the horizon (c, m, y).
-- Only the clouds use these now, so they always match the time of day.
local skyKeys = {
  { 0.00,  0.50, 0.00, 0.00,   0.00, 0.50, 1.00 },   -- sunrise
  { 0.10,  0.50, 0.00, 0.00,   0.25, 0.00, 0.50 },   -- morning
  { 0.25,  0.25, 0.00, 0.00,   0.25, 0.00, 0.00 },   -- noon
  { 0.42,  0.50, 0.00, 0.00,   0.00, 0.00, 0.50 },   -- afternoon
  { 0.50,  0.25, 0.50, 0.00,   0.00, 0.50, 1.00 },   -- sunset
  { 0.58,  1.00, 0.75, 0.00,   0.25, 0.75, 0.50 },   -- dusk
  { 0.68,  1.00, 1.00, 0.00,   1.00, 0.50, 0.00 },   -- night
  { 0.90,  1.00, 1.00, 0.00,   1.00, 0.50, 0.00 },   -- late night
  { 1.00,  0.50, 0.00, 0.00,   0.00, 0.50, 1.00 },   -- back to sunrise
}

local function lerpNum(a, b, f)
  return a + (b - a) * f
end

-- returns the six ink amounts for time t
local function skyInks(t)
  for i = 1, #skyKeys - 1 do
    local a, b = skyKeys[i], skyKeys[i + 1]
    if t >= a[1] and t <= b[1] then
      local f = (t - a[1]) / (b[1] - a[1])
      local out = {}
      for k = 2, 7 do
        out[k - 1] = lerpNum(a[k], b[k], f)
      end
      return out
    end
  end
  return skyKeys[1]
end

-- 0 in the day, 1 in the middle of the night
local function nightAmount(t)
  if t < 0.52 then return 0 end
  if t < 0.62 then return (t - 0.52) / 0.10 end
  if t < 0.90 then return 1 end
  if t < 0.98 then return 1 - (t - 0.90) / 0.08 end
  return 0
end

-- A 4x4 pattern. A cell gets ink when the ink amount beats its number.
local BAYER = {
  {  0,  8,  2, 10 },
  { 12,  4, 14,  6 },
  {  3, 11,  1,  9 },
  { 15,  7, 13,  5 },
}

-- Each ink gets its own offset so the three inks do not all land on the same cells
local function bayer(col, row)
  return (BAYER[row % 4 + 1][col % 4 + 1] + 0.5) / 16
end

-- ---------------------------------------------------------------
-- STATE
local cycleFrame = 0
local dayCount   = 0

local stars   = {}
local clouds  = {}
local owl     = {}
local trail   = {}
local shoot   = {}

local shotTaken   = false     -- has the print frame been saved yet?
local wantPhoto   = false     -- true when the next photo should be the one in SCREENSHOT_PHOTO

-- The owl, drawn from a table of text rows. o = feather, e = eye, b = beak
local owlUp = {
  "o..o...o..o",
  "oo.ooooo.oo",
  ".ooooooooo.",
  "..ooeoeoo..",
  "..ooobooo..",
  "...ooooo...",
  "...ooooo...",
  "....ooo....",
  "....o.o....",
}
local owlDown = {
  "...o...o...",
  "...ooooo...",
  "..ooooooo..",
  "..ooeoeoo..",
  ".ooooboooo.",
  "ooooooooooo",
  "oo.ooooo.oo",
  "o...ooo...o",
  "....o.o....",
}

local starColors = { COL.paper, ink(0, 0, 0.45), ink(0.3, 0, 0) }

-- ---------------------------------------------------------------
-- PLACES: dithered photos of places I have been
local placeFiles  = {}     -- the paths of the photos found in the assets folder (loaded one at a time)
local placeNotes  = {}     -- messages about files that were skipped or failed to load
local assetsFound = false  -- did the assets folder exist?
local lastPlace   = ""     -- the last photo shown, so it never repeats
local placeImg    = nil    -- tonight's image
local placeScale  = 1
local placeQuads  = {}     -- the image cut into small squares, one per cell
local placeWhole  = nil    -- the whole visible part of the image
local cellsX      = math.ceil(W / PCELL)
local cellsY      = math.ceil(PLACE_H / PCELL)
local cellDelay   = {}     -- RANDOM: when each cell breaks away
local cellDrift   = {}     -- RANDOM: how far each cell slides sideways
local cellFall    = {}     -- RANDOM: how far each cell falls
local placeState  = "in"   -- "in" (pixelating in), "hold" (whole), or "out" (pixelating out)
local placeFrame  = 0      -- frames spent in the current state
local snapShader  = nil    -- makes every photo pixel one of the 8 ink mixes

-- The shader looks at each pixel of the photo and replaces it with the closest of the
-- 8 colors you can make from the three inks (each ink on or off). That way the photos
-- can never contain a color that the printer could not make.
local function makeSnapShader()
  local ok, result = pcall(love.graphics.newShader, [[
    uniform vec3 inkColors[8];
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
      vec4 px = Texel(tex, uv);
      vec3 best = inkColors[0];
      float bestDist = 1000.0;
      for (int i = 0; i < 8; i++) {
        vec3 d = px.rgb - inkColors[i];
        float dist = dot(d, d);
        if (dist < bestDist) {
          bestDist = dist;
          best = inkColors[i];
        }
      }
      return vec4(best, px.a) * color;
    }
  ]])
  if not ok then
    table.insert(placeNotes, "ink snapping is off: " .. tostring(result))
    return
  end
  snapShader = result

  -- FOR LOOPS: build the 8 ink mixes (each ink on or off) and send them to the shader
  local colors = {}
  for c = 0, 1 do
    for m = 0, 1 do
      for y = 0, 1 do
        local mix = ink(c, m, y)
        table.insert(colors, { mix[1] / 255, mix[2] / 255, mix[3] / 255 })
      end
    end
  end
  snapShader:send("inkColors", unpack(colors))
end

-- Looks through a folder (and every folder inside it) and adds each photo file to the list.
-- It does NOT load the pictures yet: loading a whole album at once makes the window freeze.
local function scanFolder(folder)
  local items = love.filesystem.getDirectoryItems(folder)
  table.sort(items)
  for i, name in ipairs(items) do
    local path = folder .. "/" .. name
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then
      scanFolder(path)                          -- look inside subfolders too
    elseif name:sub(1, 1) ~= "." then
      local ext = name:lower():match("%.(%w+)$")
      if ext == "png" or ext == "jpg" or ext == "jpeg" then
        table.insert(placeFiles, path)
      else
        table.insert(placeNotes, "skipped " .. name .. " (only png, jpg and jpeg work)")
      end
    end
  end
end

local function loadPlaces()
  placeFiles = {}
  placeNotes = {}
  assetsFound = love.filesystem.getInfo(ASSET_DIR) ~= nil
  if assetsFound then
    scanFolder(ASSET_DIR)
  end
end

-- Loads one photo. If it fails, the reason is saved so it can be shown on screen.
local function loadPlaceImage(name)
  local ok, result = pcall(love.graphics.newImage, name)
  if ok then
    return result
  end
  table.insert(placeNotes, "could not load " .. name .. ": " .. tostring(result))
  -- forget this file so it is not tried again
  for i, n in ipairs(placeFiles) do
    if n == name then
      table.remove(placeFiles, i)
      break
    end
  end
  return nil
end

-- Is this file the photo named in SCREENSHOT_PHOTO?
local function isShotPhoto(path)
  if SCREENSHOT_PHOTO == "" then return false end
  return path:lower():sub(-#SCREENSHOT_PHOTO) == SCREENSHOT_PHOTO:lower()
end

-- RANDOM: pick any photo, but never the same one twice in a row
-- (unless the poster photo was asked for, then it picks that one).
local function pickPlace()
  while #placeFiles > 0 do
    local idx = 1
    local found = false
    if wantPhoto then
      for i, name in ipairs(placeFiles) do
        if isShotPhoto(name) then
          idx = i
          found = true
        end
      end
      wantPhoto = false
    end
    if not found and #placeFiles > 1 then
      repeat
        idx = math.floor(random(1, #placeFiles + 1))
      until placeFiles[idx] ~= lastPlace
    end
    local name = placeFiles[idx]
    local img = loadPlaceImage(name)
    if img then
      lastPlace = name
      return img
    end
  end
  return nil
end

-- Cuts tonight's image into squares so it can break apart and rebuild.
-- The image is scaled to cover the whole canvas and cropped in the middle.
local function setupPlace()
  placeImg = nil
  placeQuads = {}
  collectgarbage()           -- let go of the last photo's memory before loading the next
  placeImg = pickPlace()
  placeQuads = {}
  cellDelay, cellDrift, cellFall = {}, {}, {}
  if not placeImg then return end

  local iw, ih = placeImg:getWidth(), placeImg:getHeight()
  placeScale = math.max(W / iw, PLACE_H / ih)
  local sw, sh = W / placeScale, PLACE_H / placeScale
  local sx, sy = (iw - sw) / 2, (ih - sh) / 2
  local cs = PCELL / placeScale

  placeWhole = love.graphics.newQuad(sx, sy, sw, sh, iw, ih)

  -- FOR LOOPS: one small square of the image for every cell
  for cy = 0, cellsY - 1 do
    for cx = 0, cellsX - 1 do
      local i = cy * cellsX + cx + 1
      placeQuads[i] = love.graphics.newQuad(sx + cx * cs, sy + cy * cs, cs, cs, iw, ih)
      cellDelay[i] = random()
      cellDrift[i] = random(-50, 50)
      cellFall[i] = random(30, 160)
    end
  end
end

-- Where the photo is in its life: pixelating in, whole for 5 seconds, or pixelating out.
-- The photo runs on its own timer, separate from the sun and moon cycle.
local function placeStage()
  if placeState == "in" then
    return "in", math.min(1, placeFrame / DISSOLVE_FRAMES)
  elseif placeState == "hold" then
    return "whole", 1
  end
  return "out", math.min(1, placeFrame / DISSOLVE_FRAMES)
end

-- Moves the photo through in -> hold -> out, then brings in a new random photo.
local function updatePlace()
  placeFrame = placeFrame + 1
  if placeState == "in" and placeFrame >= DISSOLVE_FRAMES then
    placeState = "hold"
    placeFrame = 0
  elseif placeState == "hold" and placeFrame >= HOLD_FRAMES then
    placeState = "out"
    placeFrame = 0
  elseif placeState == "out" and placeFrame >= DISSOLVE_FRAMES then
    setupPlace()              -- RANDOM: a new photo, with new random cell timings
    placeState = "in"
    placeFrame = 0
  end
end

function drawPlace()
  if not placeImg then
    return                -- drawNotice() explains what is wrong
  end

  local stage, p = placeStage()
  love.graphics.setColor(1, 1, 1, 1)
  if SNAP_TO_INKS and snapShader then
    love.graphics.setShader(snapShader)
  end

  if stage == "whole" then
    love.graphics.draw(placeImg, placeWhole, 0, PLACE_Y, 0, placeScale, placeScale)
    love.graphics.setShader()
    return
  end

  love.graphics.setScissor(0, PLACE_Y, W, PLACE_H)
  local win = 0.3
  for i = 1, #placeQuads do
    local cx = (i - 1) % cellsX
    local cy = math.floor((i - 1) / cellsX)
    -- 0 = in place, 1 = gone
    local s = math.max(0, math.min(1, (p * (1 + win) - cellDelay[i]) / win))
    if stage == "in" then
      s = 1 - s
    end
    if s < 1 then
      local x = cx * PCELL + cellDrift[i] * s
      local y = PLACE_Y + cy * PCELL + cellFall[i] * s * s
      love.graphics.draw(placeImg, placeQuads[i], x, y, 0, placeScale, placeScale)
    end
  end
  love.graphics.setScissor()
  love.graphics.setShader()
end

-- If no photo could be shown, this explains exactly why. It is drawn last, on top of
-- everything, on a paper-colored panel so it is easy to read.
function drawNotice()
  if placeImg then return end

  local lines = {}
  if not assetsFound then
    table.insert(lines, "There is no 'assets' folder next to main.lua.")
  elseif #placeFiles == 0 and #placeNotes == 0 then
    table.insert(lines, "The assets folder is empty.")
  else
    table.insert(lines, "No photo could be shown from the assets folder.")
  end
  table.insert(lines, "The game can only see files inside this folder:")
  table.insert(lines, love.filesystem.getSource())
  for i, note in ipairs(placeNotes) do
    if i <= 6 then
      table.insert(lines, note)
    end
  end

  setInk(COL.paper)
  rect(12, 66, W - 24, #lines * 20 + 20)
  setInk(ink(1, 0.8, 0.4))
  textAlign(LEFT, TOP)
  textSize(13)
  for i, line in ipairs(lines) do
    text(string.sub(line, 1, 100), 24, 76 + (i - 1) * 20)
  end
end

-- ---------------------------------------------------------------
-- RANDOM SETUP (the stars, clouds and shooting star are remade at the start of every new day)

-- RANDOM: about 100 stars with their own place, size, color and twinkle.
local function makeStars()
  stars = {}
  for i = 1, STAR_COUNT do
    local sizeRoll = random()
    local size = 1
    if sizeRoll > 0.93 then
      size = 3
    elseif sizeRoll > 0.70 then
      size = 2
    end
    stars[i] = {
      x = random(W),
      y = random(H * 0.7),                -- only the top 70% of the picture
      size = size,
      color = random(starColors),         -- only 3 colors, not every color
      speed = random(0.04, 0.16),         -- own twinkle speed
      phase = random(0, math.pi * 2),     -- own twinkle starting point
      appears = random(0.05, 0.9),        -- when in the evening it shows up
    }
  end
end

-- RANDOM: 2 to 5 clouds at random heights, drifting at different speeds.
local function makeClouds()
  clouds = {}
  local count = math.floor(random(2, 6))
  for i = 1, count do
    local cloud = {
      x = random(W),
      y = random(40, 300),
      speed = random(0.15, 0.6),
      rows = {},
    }
    local width = random(80, 160)
    for r = 1, 3 do
      local rowW = math.floor(width * random(0.55, 1.0) / CELL) * CELL
      local rowX = math.floor(random(0, width - rowW) / CELL) * CELL
      cloud.rows[r] = { x = rowX, w = rowW }
    end
    clouds[i] = cloud
  end
end

-- RANDOM: the owl starts at a random spot on the picture.
local function makeOwl()
  owl = {
    x = random(W * 0.25, W * 0.75),
    y = random(140, 380),
    heading = random(0, math.pi * 2),
    turn = 0,
    speed = 2,
    targetSpeed = 2,
  }
  trail = {}
end

-- RANDOM: 15% chance of a shooting star each night, at a random time.
local function makeShootingStar()
  shoot = {
    planned = random() < 0.15,
    fireAt = random(0.66, 0.88),
    fired = false,
    active = false,
    hist = {},
  }
end

-- The sun and moon cycle starts over. The photo and the owl keep going on their own.
local function newDay()
  cycleFrame = 0
  dayCount = dayCount + 1
  makeStars()
  makeClouds()
  makeShootingStar()
end

local function fireShootingStar()
  local angle = math.rad(random(20, 50))    -- 20 to 50 degrees downward
  local dir = 1
  if random() < 0.5 then dir = -1 end
  shoot.active = true
  shoot.fired = true
  shoot.life = 0
  shoot.x = random(120, W - 120)
  shoot.y = random(20, 110)
  shoot.vx = math.cos(angle) * 14 * dir
  shoot.vy = math.sin(angle) * 14
  shoot.hist = {}
end

-- ---------------------------------------------------------------
function setup()
  size(W, H)
  windowTitle("Project 2: Patterns and Randomness")
  describe("A pixel night sky built from blue, pink and yellow ink. The sun and moon repeat the same arc while an owl, stars, clouds and shooting stars change every night.")
  frameRate(FPS)
  noStroke()
  noSmooth()          -- keeps the dithered pixels crisp when an image is scaled
  loadPlaces()
  makeSnapShader()
  wantPhoto = SCREENSHOT_PHOTO ~= ""     -- start on the poster photo if one is named
  setupPlace()
  for i, note in ipairs(placeNotes) do
    print(note)
  end
  if SCREENSHOT_PHOTO ~= "" then
    local ok = false
    for i, name in ipairs(placeFiles) do
      if isShotPhoto(name) then ok = true end
    end
    if not ok then
      print("SCREENSHOT_PHOTO '" .. SCREENSHOT_PHOTO .. "' was not found in the assets folder")
    end
  end
  makeOwl()
  newDay()
end

function draw()
  cycleFrame = cycleFrame + 1
  if cycleFrame >= DAY_FRAMES then
    newDay()
  end
  local t = cycleFrame / DAY_FRAMES
  local night = nightAmount(t)

  updatePlace()
  updateOwl()
  updateShootingStar(t)

  setInk(COL.paper)
  rect(0, 0, W, H)           -- plain paper, seen where the photo has broken away
  drawPlace()                -- the dithered photo fills the screen, on its own timer
  drawTint(t, night)         -- night and sunset ink laid over the photo
  drawBody(t)                -- one shape that is the sun by day and the moon by night
  drawStars(night)
  drawClouds(t)
  drawShootingStar()
  drawOwl()                  -- the owl flies over everything
  drawPhaseRow()
  drawNotice()               -- only shows if no photo could be loaded

  -- the print version: save one frame once my chosen photo has been whole for a moment
  if not shotTaken and placeState == "hold" and placeFrame == SHOT_FRAMES and isShotPhoto(lastPlace) then
    saveFrame()
    shotTaken = true
  end
end

-- ---------------------------------------------------------------
-- THE SKY: a dither made only of on/off ink cells
local function quarter(v)
  return math.floor(v * 4 + 0.5) / 4
end

-- How close we are to sunrise or sunset
local function warmth(t)
  local d = math.min(math.abs(t), math.abs(t - 0.5), math.abs(t - 1))
  return math.max(0, 1 - d / 0.1)
end

-- A see-through layer of ink over the photo, like overprinting on paper.
-- Blue and magenta darken the photo at night, and yellow and magenta warm it
-- at sunrise and sunset. Multiply blending is how real ink layers combine.
function drawTint(t, night)
  local warm = warmth(t)
  if night < 0.02 and warm < 0.02 then return end

  local passes = {
    { ink = INK_C, amount = 0.5 * night,               dx = 0, dy = 0 },
    { ink = INK_M, amount = 0.5 * night + 0.25 * warm, dx = 2, dy = 1 },
    { ink = INK_Y, amount = 0.5 * warm,                dx = 1, dy = 2 },
  }
  local cols = math.ceil(W / CELL)
  local rows = math.ceil(H / CELL)

  love.graphics.setBlendMode("multiply", "premultiplied")
  -- FOR LOOPS: one pass for each ink, over every row and column of cells
  for i, pass in ipairs(passes) do
    if pass.amount > 0.02 then
      fill(pass.ink[1], pass.ink[2], pass.ink[3])
      for row = 0, rows - 1 do
        -- a little stronger toward the top, rounded to quarters for clean bands
        local amt = quarter(pass.amount * (1.2 - 0.4 * row / rows))
        local runStart = -1
        for col = 0, cols do
          local on = col < cols and amt > bayer(col + pass.dx, row + pass.dy)
          if on and runStart < 0 then
            runStart = col
          elseif not on and runStart >= 0 then
            rect(runStart * CELL, row * CELL, (col - runStart) * CELL, CELL)
            runStart = -1
          end
        end
      end
    end
  end
  love.graphics.setBlendMode("alpha")
end

-- ---------------------------------------------------------------
-- STARS
function drawStars(night)
  if night <= 0.05 then return end
  for i, s in ipairs(stars) do
    local twinkle = math.sin(cycleFrame * s.speed + s.phase)
    if night > s.appears and twinkle > -0.4 then
      local px = math.floor(s.x / 3) * 3
      local py = math.floor(s.y / 3) * 3
      local size = s.size * 3
      setInk(s.color)
      rect(px, py, size, size)
      if s.size == 3 and twinkle > 0.3 then
        -- the biggest stars grow a small cross when they sparkle
        rect(px - 3, py + 3, 3, 3)
        rect(px + size, py + 3, 3, 3)
        rect(px + 3, py - 3, 3, 3)
        rect(px + 3, py + size, 3, 3)
      end
    end
  end
end

-- ---------------------------------------------------------------
-- THE SUN AND MOON ARE ONE SHAPE.
-- It crosses the picture left to right as the sun, changes into the moon at sunset,
-- then travels back right to left along the same arc, and changes into the sun at sunrise.

-- Moves slowly near the edges (so the change happens while it is low) and quickly in the middle.
local function bodyPosition(t)
  local u, x
  if t < 0.5 then
    u = t / 0.5
  else
    u = (t - 0.5) / 0.5
  end
  local e = 0.5 - 0.5 * math.cos(math.pi * u)
  if t < 0.5 then
    x = lerpNum(ARC_X_LEFT, ARC_X_RIGHT, e)
  else
    x = lerpNum(ARC_X_RIGHT, ARC_X_LEFT, e)
  end
  local y = ARC_Y - math.sin(math.pi * e) * ARC_H
  return x, y
end

-- 0 = all sun, 1 = all moon. It changes around sunset (0.5) and sunrise (1.0).
local function morphAmount(t)
  local m
  if t < 0.06 then
    m = 1 - (t + 0.06) / 0.12
  elseif t < 0.44 then
    m = 0
  elseif t < 0.56 then
    m = (t - 0.44) / 0.12
  elseif t < 0.94 then
    m = 1
  else
    m = 1 - (t - 0.94) / 0.12
  end
  return m * m * (3 - 2 * m)          -- eases in and out
end

local function lerpColor(a, b, f)
  return {
    lerpNum(a[1], b[1], f),
    lerpNum(a[2], b[2], f),
    lerpNum(a[3], b[3], f),
  }
end

-- Lays the lit part of the moon over a disc as thin horizontal strips.
-- waxing: the lit part is on the right. c is where the shadow line sits:
-- -1 lights the whole disc, 0 is a half moon, 1 is no light at all.
local function litStrips(cx, cy, r, waxing, c)
  -- FOR LOOP: one strip for every row of pixels in the disc
  for dy = -r, r - 1 do
    local yy = dy + 0.5
    local halfW = math.sqrt(math.max(0, r * r - yy * yy))
    local x0, x1
    if waxing then
      x0 = c * halfW            -- the right side fills in
      x1 = halfW
    else
      x0 = -halfW               -- the left side shrinks away
      x1 = -c * halfW
    end
    if x1 > x0 then
      rect(cx + x0, cy + dy, x1 - x0, 1)
    end
  end
end

-- phase: 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter
local function drawMoonDisk(cx, cy, r, phase, ring)
  cx = math.floor(cx + 0.5)
  cy = math.floor(cy + 0.5)
  if ring > 0 then
    setInk(COL.paper)
    circle(cx, cy, (r + ring) * 2)
  end
  setInk(COL.moonDim)
  circle(cx, cy, r * 2)
  setInk(COL.moonLit)
  litStrips(cx, cy, r, phase < 0.5, math.cos(phase * math.pi * 2))
end

local function currentPhase()
  return (dayCount + 3) % 8       -- the first night is a full moon
end

-- The moon phase that goes with this moment: before midday it is still last night's moon.
local function phaseAt(t)
  if t < 0.25 then
    return ((dayCount + 2) % 8) / 8
  end
  return currentPhase() / 8
end

-- Everything is solid shapes with a cream ring, so it stands out from any photo.
function drawBody(t)
  local cx, cy = bodyPosition(t)
  cx = math.floor(cx + 0.5)
  cy = math.floor(cy + 0.5)
  local m = morphAmount(t)
  local r = math.floor(lerpNum(30, 28, m) + 0.5)
  local ring = math.floor(lerpNum(5, 4, m) + 0.5)

  local phase = phaseAt(t)
  local waxing = phase < 0.5
  -- the shadow line slides from "whole disc lit" to tonight's phase as it turns into the moon
  local c = lerpNum(-1, math.cos(phase * math.pi * 2), m)

  setInk(COL.paper)
  circle(cx, cy, (r + ring) * 2)                       -- ring

  setInk(lerpColor(COL.sunEdge, COL.moonDim, m))
  circle(cx, cy, r * 2)                                -- the disc

  setInk(lerpColor(COL.sunEdge, COL.moonLit, m))
  litStrips(cx, cy, r, waxing, c)                      -- the lit part

  if m < 0.98 then
    setInk(COL.sunCore)
    circle(cx, cy, r * 1.4 * (1 - m))                  -- the sun's bright center shrinks away
  end
end

-- A row of all 8 phases along the top. The tonight marker is a small bar.
function drawPhaseRow()
  local now = currentPhase()
  for i = 0, 7 do
    local x = W / 2 + (i - 3.5) * 36
    drawMoonDisk(x, 24, 13, i / 8, 2)
    if i == now then
      setInk(COL.sunCore)
      rect(math.floor(x) - 9, 46, 18, 3)
    end
  end
end

-- ---------------------------------------------------------------
-- CLOUDS (always a lighter version of the sky color behind them)
function drawClouds(t)
  local k = skyInks(t)
  local cloudColor = ink(k[1] * 0.3, k[2] * 0.3, k[3] * 0.3)
  setInk(cloudColor)
  for i, cloud in ipairs(clouds) do
    cloud.x = cloud.x + cloud.speed
    if cloud.x > W + 40 then cloud.x = -200 end
    for r, row in ipairs(cloud.rows) do
      rect(math.floor((cloud.x + row.x) / CELL) * CELL, cloud.y + (r - 1) * 12, row.w, 12)
    end
  end
end

-- ---------------------------------------------------------------
-- SHOOTING STAR
function updateShootingStar(t)
  if shoot.planned and not shoot.fired and t >= shoot.fireAt then
    fireShootingStar()
  end
  if shoot.active then
    shoot.life = shoot.life + 1
    shoot.x = shoot.x + shoot.vx
    shoot.y = shoot.y + shoot.vy
    table.insert(shoot.hist, 1, { x = shoot.x, y = shoot.y })
    if #shoot.hist > 8 then table.remove(shoot.hist) end
    if shoot.life > 36 then shoot.active = false end
  end
end

function drawShootingStar()
  if not shoot.active then return end
  for i, p in ipairs(shoot.hist) do
    if i == 1 then
      setInk(COL.paper)
    elseif i < 4 then
      setInk(COL.moonLit)
    else
      setInk(ink(0.2, 0, 0.3))
    end
    local size = math.max(3, 9 - i)
    rect(math.floor(p.x / 3) * 3, math.floor(p.y / 3) * 3, size, size)
  end
end

-- ---------------------------------------------------------------
-- THE OWL
local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function angleDiff(a, b)
  local d = (a - b + math.pi) % (math.pi * 2) - math.pi
  return d
end

function updateOwl()
  -- RANDOM: a small random nudge to the turning rate each frame. The nudges
  -- are tiny and the turn rate is capped, so the owl curves instead of jittering.
  owl.turn = clamp(owl.turn + random(-0.012, 0.012), -0.05, 0.05)
  owl.heading = owl.heading + owl.turn

  -- RANDOM: speed drifts toward a new random target between 1.5 and 3
  if cycleFrame % 45 == 0 then
    owl.targetSpeed = random(1.5, 3)
  end
  owl.speed = owl.speed + (owl.targetSpeed - owl.speed) * 0.05

  -- near an edge, curve gently back toward the middle
  local left, right, top, bottom = 70, W - 70, 80, H - 70
  if owl.x < left or owl.x > right or owl.y < top or owl.y > bottom then
    local toCenter = math.atan2(H / 2 - owl.y, W / 2 - owl.x)
    local d = angleDiff(toCenter, owl.heading)
    owl.heading = owl.heading + clamp(d, -0.06, 0.06)
  end

  owl.x = owl.x + math.cos(owl.heading) * owl.speed
  owl.y = owl.y + math.sin(owl.heading) * owl.speed

  -- remember where it has been
  if cycleFrame % 4 == 0 then
    table.insert(trail, { x = owl.x, y = owl.y })
    if #trail > TRAIL_LENGTH then table.remove(trail, 1) end
  end
end

function drawOwl()
  -- the trail of small squares behind the owl
  for i, p in ipairs(trail) do
    if i % 2 == 0 then
      if i % 4 == 0 then
        setInk(COL.trailA)
      else
        setInk(COL.trailB)
      end
      rect(math.floor(p.x / 3) * 3, math.floor(p.y / 3) * 3, 3, 3)
    end
  end

  -- two frames, swapped every few frames, so the wings flap
  local sprite = owlUp
  if math.floor(cycleFrame / 6) % 2 == 1 then
    sprite = owlDown
  end

  local px = 4
  local startX = math.floor(owl.x - 5.5 * px)
  local startY = math.floor(owl.y - 4.5 * px)
  for row = 1, #sprite do
    local line = sprite[row]
    for col = 1, #line do
      local ch = line:sub(col, col)
      if ch ~= "." then
        if ch == "o" then
          setInk(COL.owlBody)
        elseif ch == "e" then
          setInk(COL.owlEye)
        else
          setInk(COL.owlBeak)
        end
        rect(startX + (col - 1) * px, startY + (row - 1) * px, px, px)
      end
    end
  end
end

-- ---------------------------------------------------------------
-- Saves what is on screen right now as a png in the LOVE save folder.
function saveFrame()
  save("project2.png")
  print("Saved project2.png in: " .. love.filesystem.getSaveDirectory())
end

function mousePressed()
  skipAhead()
end

function skipAhead()
  local t = cycleFrame / DAY_FRAMES
  if t < 0.55 then
    cycleFrame = math.floor(0.55 * DAY_FRAMES)
  else
    newDay()
  end
end

function keyPressed()
  if key == "n" then
    skipAhead()
  elseif key == "s" then
    saveFrame()
  elseif key == "g" then
    wantPhoto = true         -- the next photo will be the one in SCREENSHOT_PHOTO
    shotTaken = false        -- and it will be saved again
    placeState = "out"
    placeFrame = 0
  elseif key == "i" then
    SNAP_TO_INKS = not SNAP_TO_INKS      -- compare the photos with and without ink snapping
  elseif key == "p" then
    placeState = "out"       -- jump to the next photo
    placeFrame = 0
  elseif key == "m" then
    fireShootingStar()
  end
end