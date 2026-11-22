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
