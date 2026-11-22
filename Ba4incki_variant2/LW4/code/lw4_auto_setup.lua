-- LW4, variant 2: automatic scene setup for CoppeliaSim (written without access to CoppeliaSim, so every step is guarded:
-- a failed step prints "FAILED: ..." and the rest still runs; do the failed step by hand).
--
-- Usage (CoppeliaSim command line, simulation stopped), robot PioneerP3DX already dragged into the scene:
--   dofile([[C:\temp\lw4_auto_setup.lua]])
--   lw4_partA()   -- camera on the robot + wall + floating view   (screenshot L4-01)
--   lw4_partB()   -- floor, oval track, line sensors, robot on the track, line-following script (L4-02, L4-03)
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
    robot      = sim.getObject('..')
    -- line sensors: left, middle, right
    lineSensors = {
        sim.getObject('../sensorLeft'),
        sim.getObject('../sensorMiddle'),
        sim.getObject('../sensorRight')
    }
    baseSpeed = 1.8      -- rad/s
    threshold = 0.35     -- darker than this means "line"
    steerGain = 1.1
    lastSide  = 0        -- -1: line was last seen on the left, 1: on the right
    -- blue trail of the robot
    trail = sim.addDrawingObject(sim.drawing_linestrip, 4, 0, -1, 4000, {0.1, 0.35, 1.0})
end

function sysCall_actuation()
    local seen = {0, 0, 0}
    for i = 1, 3 do
        local res, packet = sim.readVisionSensor(lineSensors[i])
        if res >= 0 and packet and packet[11] < threshold then
            seen[i] = 1
        end
    end

    local vL, vR
    if seen[1] + seen[2] + seen[3] == 0 then
        -- line lost: turn to the side where it was seen last
        if lastSide > 0 then
            vL, vR = 0.5 * baseSpeed, -0.2 * baseSpeed
        elseif lastSide < 0 then
            vL, vR = -0.2 * baseSpeed, 0.5 * baseSpeed
        else
            vL, vR = baseSpeed, baseSpeed
        end
    else
        -- steer > 0: line is on the right, so speed up the left wheel
        local steer = seen[3] - seen[1]
        if steer ~= 0 then lastSide = steer end
        vL = baseSpeed * (1 + 0.5 * steerGain * steer)
        vR = baseSpeed * (1 - 0.5 * steerGain * steer)
    end
    sim.setJointTargetVelocity(motorLeft, vL)
    sim.setJointTargetVelocity(motorRight, vR)

    -- add the current position to the trail
    local p = sim.getObjectPosition(robot, sim.handle_world)
    sim.addDrawingObjectItem(trail, {p[1], p[2], 0.012})
end

function sysCall_cleanup()
    if trail then
        sim.removeDrawingObject(trail)
    end
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
    try('1) white floor', function()
        fl = sim.createPrimitiveShape(sim.primitiveshape_cuboid, {6, 4, 0.1})
        setPos(fl, {0, 0, -0.05})
        sim.setShapeColor(fl, nil, sim.colorcomponent_ambient_diffuse, {1, 1, 1})
        sim.setObjectInt32Param(fl, sim.shapeintparam_respondable, 1)
        sim.setObjectInt32Param(fl, sim.shapeintparam_static, 1)
        sim.setObjectAlias(fl, 'whiteFloor')
    end)
    try('2) oval track', function()
        R = 0.9 L = 2.0 W_LINE = 0.07 N = 20
        local function mk(x, y, a, len, n)
            local s = sim.createPrimitiveShape(sim.primitiveshape_cuboid, {len, W_LINE, 0.002})
            setPos(s, {x, y, 0.005})
            setOri(s, {0, 0, a})
            sim.setShapeColor(s, nil, sim.colorcomponent_ambient_diffuse, {0, 0, 0})
            sim.setObjectInt32Param(s, sim.shapeintparam_respondable, 0)
            sim.setObjectAlias(s, n)
        end
        mk(0, -R, 0, L + 0.1, 'trackBottom')
        mk(0, R, 0, L + 0.1, 'trackTop')
        for i = 0, N - 1 do
            local t = -math.pi / 2 + math.pi * (i + 0.5) / N
            mk(L / 2 + R * math.cos(t), R * math.sin(t), t + math.pi / 2, math.pi * R / N * 1.15, 'trackRight' .. i)
            t = math.pi / 2 + math.pi * (i + 0.5) / N
            mk(-L / 2 + R * math.cos(t), R * math.sin(t), t + math.pi / 2, math.pi * R / N * 1.15, 'trackLeft' .. i)
        end
    end)
    try('3) three line sensors', function()
        rb = sim.getObject('/PioneerP3DX')
        local cam = sim.getObject('/PioneerP3DX/visionSensor')
        local m = sim.getObjectMatrix(cam, W)
        fx, fy = m[3], m[7]
        local ln = math.sqrt(fx * fx + fy * fy)
        fx, fy = fx / ln, fy / ln
        local lx, ly = -fy, fx
        local cp = sim.getObjectPosition(cam, W)
        local nm = {'sensorLeft', 'sensorMiddle', 'sensorRight'}
        local of = {0.06, 0, -0.06}
        for i = 1, 3 do
            local s = sim.createVisionSensor(2, {1, 1, 0, 0}, {0.005, 1, math.rad(20), 0.01, 0.01, 0.01, 0, 0, 0, 0, 0})
            setPos(s, {cp[1] + 0.12 * fx + of[i] * lx, cp[2] + 0.12 * fy + of[i] * ly, 0.05})
            setOri(s, {math.pi, 0, 0})
            sim.setObjectParent(s, rb, true)
            sim.setObjectAlias(s, nm[i])
        end
    end)
    try('4) robot on the track', function()
        local o = sim.getObjectOrientation(rb, W)
        o[3] = o[3] - math.atan(fy, fx)
        setOri(rb, o)
        local sm = sim.getObject('/PioneerP3DX/sensorMiddle')
        local sp = sim.getObjectPosition(sm, W)
        local rp = sim.getObjectPosition(rb, W)
        setPos(rb, {rp[1] - 0.8 - sp[1], rp[2] - R - sp[2], rp[3]})
    end)
    try('move the test wall away from the track', function()
        local w = sim.getObject('/testWall')
        setPos(w, {2.7, 0, 0.2})
    end)
    try('install the line-following script into the robot', function()
        local rbh = sim.getObject('/PioneerP3DX')
        local ok, scr = pcall(sim.getScript, sim.scripttype_simulation, rbh)
        if not ok or scr == nil or scr == -1 then
            ok, scr = pcall(sim.getScript, sim.scripttype_childscript, rbh)
        end
        if not ok or scr == nil or scr == -1 then error('the robot script was not found') end
        sim.setScriptStringParam(scr, sim.scriptstringparam_text, LW4_SCRIPT)
    end)
end

print('lw4_auto_setup loaded: run lw4_partA() and then lw4_partB()')
