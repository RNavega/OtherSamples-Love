-- ==========================================================
-- Example of a Super Mario World style jump mechanic, where
-- the player can control how far they should jump by holding
-- the jump key, with a maximum possible jump height.
-- By Rafael Navega (2024)
--
-- License: Public Domain
-- ==========================================================

io.stdout:setvbuf('no')


local TILE_HEIGHT = 64
local PLAYER_HEIGHT = TILE_HEIGHT * 2.0
local FLOOR_Y = 500

-- How many tiles high that a SHORT jump should reach.
local SHORT_JUMP_TILES = 3
-- How many tiles high that a LONG jump should reach.
local LONG_JUMP_TILES = 5
local TOLERANCE_MIN_HEIGHT = TILE_HEIGHT * 1.8
local TOLERANCE_MAX_HEIGHT = SHORT_JUMP_TILES * TILE_HEIGHT

-- Initial jump speed, in pixels per second.
-- Completely subjective, choosing a value that "feels right".
local INITIAL_SPEED = TILE_HEIGHT * 24.0
-- Gravity when falling, in pixels per second.
-- Also subjective.
local GRAVITY = TILE_HEIGHT * 220.0

local playerPosition = {100.0, FLOOR_Y - PLAYER_HEIGHT}
local drawDebug = true


local relevantKeys = {
    ['left'] = false,
    ['right'] = false
}

-- Forward declarations of the player physics effects, so they can reference
-- each other inside their handling functions.
local jumpImpulseEffect, fallEffect, steerEffect

jumpImpulseEffect = {
    active = false,
    s=0.0, u=nil, a=nil, t=0.0,
    useGravity=false, aT=0.0,
    -- Debug fields..
    maxS=0.0,
    startKey=nil,
    holdDistance=0.0,
}

function jumpImpulseEffect:start(startKey)
    local ji = jumpImpulseEffect
    ji.active = true
    ji.s = 0.0
    ji.u = INITIAL_SPEED
    ji.a = nil
    ji.useGravity = false
    ji.t = 0.0
    ji.aT = 0.0
    -- Debug fields.
    ji.startKey = startKey
    ji.maxS = 0.0
    ji.holdDistance = 0.0
end

function jumpImpulseEffect:startGravity()
    if self.useGravity then
        return
    end
    -- Record the current 'time' of the jump, so the
    -- acceleration time can start from zero from now on.
    self.aT = 0.0--self.t
    self.useGravity = true
    -- Desired distance in pixels that the player should always reach when jumping up.
    local desiredDistance
    -- Change this 'extraPixels' value to +3 or something like that so it's added
    -- to the desired jump height. This can be used as a safety precaution so the
    -- player will reach slightly above the tile height that they aimed for
    -- and ensuring that they land there.
    local extraPixels = 0.0
    if self.s >= TOLERANCE_MIN_HEIGHT then
        -- Player released the jump key after reaching at least the minimum
        -- tolerance height, so do a linear blend between the short jump
        -- and long jump depending on how far they've already traveled.
        local minHeight = SHORT_JUMP_TILES * TILE_HEIGHT
        local maxHeight = LONG_JUMP_TILES * TILE_HEIGHT
        local heightDiff = TOLERANCE_MAX_HEIGHT - TOLERANCE_MIN_HEIGHT
        local factor = (self.s - TOLERANCE_MIN_HEIGHT) / heightDiff
        if factor > 1.0 then factor = 1.0 end
        local blendedHeight = minHeight + (maxHeight - minHeight) * factor
        desiredDistance = blendedHeight - self.s + extraPixels
    else
        -- Player released the key before reaching the tolerance height, so
        -- force the player to reach a "short jump" height.
        desiredDistance = SHORT_JUMP_TILES * TILE_HEIGHT - self.s + extraPixels
    end

    -- Solving for (a) to find the acceleration that'll make the player hit that
    -- desired jump height as the maximum, with (v²) being 0.0 as that's the speed
    -- at the highest point of the jump, after which the player starts falling.
    -- v² = u² + 2 * a * s
    -- 2 * s * a = v² - u²
    -- a = (v² - u²) / (2 * s)
    self.a = (0.0 - (self.u * self.u)) / (2.0 * desiredDistance)
end

function jumpImpulseEffect:update(dt)
    -- Classic kinematic equations (AKA "suvat" equations):
    -- A) u = s / t - 1/2 * a * t
    -- B) v = u + a * t
    -- C) s = u * t + 1/2 * a * t²
    -- D) v² = u² + 2 * a * s
    -- E) s = 1/2 * (u + v) * t
    --
    -- Using equation (C) to find (s), used as the jump offset to be
    -- added to the player position:
    -- s = (u * t) + (1/2 * a * t²)
    -- s = uniform_distance + accelerated_distance
    --
    -- However, we only use the initial distance first (constant speed along time).
    -- The gravity only kicks in when the player has made it clear that they want
    -- to do a long jump by holding the jump key long enough.
    --
    -- Once the jump reaches its highest point (the derivative of fixed_speed_distance
    -- becomes less than the derivative of accelerated_distance, meaning, the velocity
    -- at the player is zero and from this point on the player will start falling),
    -- we change to a different gravity.
    self.t = self.t + dt
    local uniformDistance = self.u * self.t

    if self.useGravity then
        self.aT = self.aT + dt
        local accelDistance = 0.5 * self.a * (self.aT * self.aT)
        self.s = uniformDistance + accelDistance

        local v = self.u + self.a * self.aT
        if v < 0.0 then
            fallEffect:start(self.s, self.t)
            self.active = false
        end
    else
        self.s = uniformDistance
        self.holdDistance = uniformDistance
        if self.s >= TOLERANCE_MAX_HEIGHT then
            self:startGravity()
        end
    end
    self.maxS = self.s > self.maxS and self.s or self.maxS
end


fallEffect = {
    active=false,
    s=0.0, u=nil, a=nil, t=0.0, aT=0.0,
}

function fallEffect:start(s, t)
    self.active = true
    self.s = s
    self.t = t
    self.a = GRAVITY
    self.v = 0.0
    self.aT = 0.0
end

function fallEffect:update(dt)
    self.t = self.t + dt
    self.aT = self.aT + dt
    -- Using "Euler integration", which is less precise than using a
    -- kinematic equation, but it works perfectly for a falling effect.
    self.v = self.v + self.a * dt
    -- A top-cap on the falling speed, in pixels per second.
    -- Subjective value, use what feels right.
    -- Try setting a small value like (TILE_HEIGHT * 5) to see it more clearly.
    local SPEED_LIMIT = TILE_HEIGHT * 300.0
    if self.v > SPEED_LIMIT then
        self.v = SPEED_LIMIT
    end
    self.s = self.s - self.v * dt
    -- For the purposes of this example, consider the character on ground
    -- when the jump offset goes below zero (goes back to the ground).
    -- In an actual game, in love.update() you'd check for collisions and
    -- disable this falling effect when the character lands on solid ground.
    if self.s < 0.0 then
        self.s = 0.0
        self.active = false
    end
end


-- Left and right steering.
steerEffect = {MOVE_SPEED = TILE_HEIGHT * 6.0}

function steerEffect:start(positionTable)
    self.pt = positionTable
end

function steerEffect:update(dt)
    if relevantKeys.right then
        self.pt[1] = self.pt[1] + self.MOVE_SPEED * dt
        if self.pt[1] > 800 - TILE_HEIGHT then
            self.pt[1] = 800 - TILE_HEIGHT
        end
    elseif relevantKeys.left then
        self.pt[1] = self.pt[1] - self.MOVE_SPEED * dt
        if self.pt[1] < 0 then
            self.pt[1] = 0
        end
    end
end


function love.load()
    steerEffect:start(playerPosition)
    love.window.setTitle('Super Mario World jump example')
end


function love.update(dt)
    if jumpImpulseEffect.active then
        jumpImpulseEffect:update(dt)
    end
    if fallEffect.active then
        fallEffect:update(dt)
    end
    steerEffect:update(dt)
end


function love.draw()
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle('fill', 0, FLOOR_Y, 800, 600 - FLOOR_Y)

    love.graphics.setColor(1.0, 1.0, 1.0)
    for y = 1, SHORT_JUMP_TILES do
        love.graphics.rectangle('line', 300, FLOOR_Y - y * TILE_HEIGHT, TILE_HEIGHT, TILE_HEIGHT)
    end
    for y = 1, LONG_JUMP_TILES do
        love.graphics.rectangle('line', 500, FLOOR_Y - y * TILE_HEIGHT, TILE_HEIGHT, TILE_HEIGHT)
    end
    for y = 1, 10 do
        love.graphics.rectangle('line', 700, FLOOR_Y - y * TILE_HEIGHT, TILE_HEIGHT, TILE_HEIGHT)
    end

    local ji = jumpImpulseEffect
    if drawDebug then
        love.graphics.setColor(0.0, 0.8, 0.8)
        local limitY = playerPosition[2] - ji.maxS
        love.graphics.line(0, limitY, 800, limitY)
        love.graphics.line(0, limitY + PLAYER_HEIGHT, 800, limitY + PLAYER_HEIGHT)
        love.graphics.setColor(0.0, 0.3, 0.8)
        local holdY = FLOOR_Y - ji.holdDistance
        love.graphics.rectangle('fill', 10, holdY, TILE_HEIGHT, ji.holdDistance)
        if holdY < FLOOR_Y - TOLERANCE_MIN_HEIGHT then
            if holdY < FLOOR_Y - TOLERANCE_MAX_HEIGHT then
                holdY = FLOOR_Y - TOLERANCE_MAX_HEIGHT
            end
            local innerHeight = ji.holdDistance - TOLERANCE_MIN_HEIGHT
            if innerHeight > TOLERANCE_MAX_HEIGHT - TOLERANCE_MIN_HEIGHT then innerHeight = TOLERANCE_MAX_HEIGHT - TOLERANCE_MIN_HEIGHT end
            love.graphics.setColor(0.8, 0.7, 0.0)
            love.graphics.rectangle('fill', 10, holdY, TILE_HEIGHT, innerHeight)
        end
        love.graphics.line(10, holdY, playerPosition[1], holdY)
        love.graphics.setColor(0.6, 0.6, 0.0)
        love.graphics.line(10, FLOOR_Y - TOLERANCE_MIN_HEIGHT, TILE_HEIGHT + 10, FLOOR_Y - TOLERANCE_MIN_HEIGHT)
        love.graphics.line(10, FLOOR_Y - TOLERANCE_MAX_HEIGHT, TILE_HEIGHT + 10, FLOOR_Y - TOLERANCE_MAX_HEIGHT)
    end

    -- Draw the player.
    love.graphics.setColor(0.0, 0.8, 0.0)
    local effect = ji.active and ji or fallEffect
    love.graphics.rectangle('fill', playerPosition[1], playerPosition[2] - effect.s,
                            TILE_HEIGHT, PLAYER_HEIGHT)

    love.graphics.setColor(1.0, 1.0, 1.0)
    love.graphics.print(('Offset: %.03f'):format(effect.s), 10, 10)
    love.graphics.print('On Ground: ' .. tostring(not (ji.active or fallEffect.active)), 10, 30)
    love.graphics.print(('Stopwatch: %.03fs'):format(effect.t), 10, 50)
    love.graphics.print('Press Tab to toggle the debug drawings ('
                        .. (drawDebug and 'ON' or 'OFF') .. ')',
                        10, 70)
    love.graphics.print([[- Use the Left and Right keys to steer.
- Tap any key to short jump
- Hold any key to long jump
- Press Esc to quit]], 10, 90)
end


function love.keypressed(key)
    if key == 'escape' then
        love.event.quit()
    elseif key == 'tab' then
        drawDebug = not drawDebug
    elseif key == 'right' then
        relevantKeys['right'] = true
    elseif key == 'left' then
        relevantKeys['left'] = true
    elseif not (jumpImpulseEffect.active or fallEffect.active) then
        jumpImpulseEffect:start(key)
    end
end


function love.keyreleased(key)
    if key == 'right' then
        relevantKeys['right'] = false
    elseif key == 'left' then
        relevantKeys['left'] = false
    elseif jumpImpulseEffect.active and jumpImpulseEffect.startKey == key then
        jumpImpulseEffect:startGravity()
    end
end
