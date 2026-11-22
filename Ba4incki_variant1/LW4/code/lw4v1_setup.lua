-- LW4, variant 1: automatic scene setup for CoppeliaSim (written without access to CoppeliaSim, so every step is guarded:
-- a failed step prints "FAILED: ..." and the rest still runs; do the failed step by hand).
--
-- Usage (CoppeliaSim command line, simulation stopped), robot PioneerP3DX already dragged into the scene:
--   dofile([[C:\temp\lw4v1_setup.lua]])
--   lw4_partA()   -- camera on the robot + standard test wall + floating view   (screenshot L4-01)
--   lw4_partB()   -- remove the test wall, five random obstacles, left-turn script into the robot (L4-02, L4-03)
-- then press Start.

pcall(function() sim = require 'sim' end)

local function try(name, f)
    local ok, err = pcall(f)
    if ok then print('OK: ' .. name) else print('FAILED: ' .. name .. ' -> ' .. tostring(err)) end
end

-- API-order independent helpers (the argument order differs between CoppeliaSim versions)
local W = sim.handle_world
local function setPos(h, p)
    if not pcall(sim.setObjectPosition, h, p, W) then sim.setObjectPosition(h, W, p) end
end
local function setOri(h, o)
    if not pcall(sim.setObjectOrientation, h, o, W) then sim.setObjectOrientation(h, W, o) end
end
local function setMat(h, M)
    if not pcall(sim.setObjectMatrix, h, M, W) then sim.setObjectMatrix(h, W, M) end
end

LW4_SCRIPT = [==[
sim = require 'sim'

function sysCall_init()
    motorLeft  = sim.getObject('../leftMotor')
    motorRight = sim.getObject('../rightMotor')
    robot = sim.getObject('..')
    -- all ultrasonic (proximity) sensors of the robot
    sonars = sim.getObjectsInTree(robot, sim.object_proximitysensor_type)
    cruise    = 2.0      -- base wheel speed, rad/s
    farRange  = 0.6      -- the sensor starts to react, m
    nearRange = 0.15     -- full reaction, m
    -- front sensors only; the left wheel is slowed down, the right one is helped a bit,
    -- so the robot always avoids an obstacle by turning left
    slowLeft   = {0.2, 0.4, 0.6, 0.8, 0.8, 0.6, 0.4, 0.2, 0, 0, 0, 0, 0, 0, 0, 0}
    boostRight = {0.1, 0.1, 0.2, 0.2, 0.2, 0.2, 0.1, 0.1, 0, 0, 0, 0, 0, 0, 0, 0}
end

function sysCall_actuation()
    local vL, vR = cruise, cruise
    for i = 1, math.min(#sonars, #slowLeft) do
        local res, dist = sim.readProximitySensor(sonars[i])
        if res > 0 and dist < farRange then
            -- k: 0 when far, 1 when near
            local k = (farRange - math.max(dist, nearRange)) / (farRange - nearRange)
            vL = vL - 2 * cruise * slowLeft[i] * k
            vR = vR + cruise * boostRight[i] * k
        end
    end
    -- do not let the left wheel spin backwards too fast
    vL = math.max(vL, -cruise)
    sim.setJointTargetVelocity(motorLeft, vL)
    sim.setJointTargetVelocity(motorRight, vR)
end
]==]

-- forward direction of the robot in the world (xy): the mean axis of the 8 front ultrasonic sensors
local function robotForward(rb)
    local sx, sy, n = 0, 0, 0
    for i = 0, 7 do
        local h
        local ok = pcall(function() h = sim.getObject('/PioneerP3DX/ultrasonicSensor', {index = i}) end)
        if not ok or not h then
            ok = pcall(function() h = sim.getObject('/PioneerP3DX/ultrasonicSensor[' .. i .. ']') end)
        end
        if ok and h then
            local m = sim.getObjectMatrix(h, W)
            sx, sy, n = sx + m[3], sy + m[7], n + 1
        end
    end
    if n == 0 then error('front ultrasonic sensors not found') end
    local ln = math.sqrt(sx * sx + sy * sy)
    return sx / ln, sy / ln
end

function lw4_partA()
    try('find the robot', function()
        rb = sim.getObject('/PioneerP3DX')
    end)
    try('camera on the robot', function()
        if pcall(sim.getObject, '/PioneerP3DX/visionSensor') then return end
        local fx, fy = robotForward(rb)
        print('robot forward direction: ' .. fx .. ', ' .. fy)
        local rp = sim.getObjectPosition(rb, W)
        local cam = sim.createVisionSensor(2, {256, 256, 0, 0}, {0.01, 5, math.rad(60), 0.05, 0.05, 0.05, 0, 0, 0, 0, 0})
        -- camera z axis = robot forward, camera y axis = down
        setMat(cam, {fy, 0, fx, rp[1] + 0.15 * fx,
                     -fx, 0, fy, rp[2] + 0.15 * fy,
                     0, -1, 0, rp[3] + 0.35})
        sim.setObjectParent(cam, rb, true)
        sim.setObjectAlias(cam, 'visionSensor')
    end)
    try('wall in front of the robot', function()
        local fx, fy = robotForward(rb)
        local rp = sim.getObjectPosition(rb, W)
        local w = sim.createPrimitiveShape(sim.primitiveshape_cuboid, {0.1, 1.2, 0.4})
        setPos(w, {rp[1] + 1.2 * fx, rp[2] + 1.2 * fy, 0.2})
        setOri(w, {0, 0, math.atan(fy, fx)})
        sim.setShapeColor(w, nil, sim.colorcomponent_ambient_diffuse, {0.8, 0.5, 0.3})
        sim.setObjectInt32Param(w, sim.shapeintparam_static, 1)
        sim.setObjectAlias(w, 'testWall')
    end)
    try('floating view for the robot camera', function()
        local cam = sim.getObject('/PioneerP3DX/visionSensor')
        local v = sim.floatingViewAdd(0.7, 0.7, 0.28, 0.28, 0)
        sim.adjustView(v, cam, 0)
    end)
end

function lw4_partB()
    try('remove the test wall', function()
        local ok, w = pcall(sim.getObject, '/testWall')
        if ok and w then sim.removeObjects({w}) end
    end)
    try('remove all old obstacles (if the step is run again)', function()
        local all = sim.getObjectsInTree(sim.handle_scene, sim.object_shape_type, 0)
        local n = 0
        for _, h in ipairs(all) do
            local alias = sim.getObjectAlias(h)
            if string.sub(alias, 1, 8) == 'obstacle' then
                sim.removeObjects({h})
                n = n + 1
            end
        end
        print('removed obstacles: ' .. n)
    end)
    try('five random obstacles along the way of the robot', function()
        local rb = sim.getObject('/PioneerP3DX')
        local fx, fy = robotForward(rb)
        local h = math.atan(fy, fx)
        local p = sim.getObjectPosition(rb, W)
        local px, py = p[1], p[2]
        -- fixed, irregular distances between the walls (m); every next leg is longer than the previous one,
        -- so the path is a spiral that opens outwards and the walls never close the robot in
        local legs = {1.1, 1.0, 1.9, 2.5, 2.9}
        for i = 1, 5 do
            local d = legs[i]
            local ox, oy = px + d * math.cos(h), py + d * math.sin(h)
            local w = sim.createPrimitiveShape(sim.primitiveshape_cuboid, {0.08, 0.9, 0.35})
            setPos(w, {ox, oy, 0.175})
            setOri(w, {0, 0, h})
            sim.setShapeColor(w, nil, sim.colorcomponent_ambient_diffuse, {0.85, 0.35, 0.2})
            sim.setObjectInt32Param(w, sim.shapeintparam_static, 1)
            sim.setObjectAlias(w, 'obstacle' .. i)
            -- the next leg starts a bit before this wall, turned to the left by 90 degrees
            px, py = ox - 0.6 * math.cos(h), oy - 0.6 * math.sin(h)
            h = h + math.rad(90)
        end
    end)
    try('install the left-turn script into the robot', function()
        local rbh = sim.getObject('/PioneerP3DX')
        local ok, scr = pcall(sim.getScript, sim.scripttype_simulation, rbh)
        if not ok or scr == nil or scr == -1 then
            ok, scr = pcall(sim.getScript, sim.scripttype_childscript, rbh)
        end
        if not ok or scr == nil or scr == -1 then error('the robot script was not found') end
        sim.setScriptStringParam(scr, sim.scriptstringparam_text, LW4_SCRIPT)
    end)
end

print('lw4v1_setup loaded: run lw4_partA() and then lw4_partB()')
