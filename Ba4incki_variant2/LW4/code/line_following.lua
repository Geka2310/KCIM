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
