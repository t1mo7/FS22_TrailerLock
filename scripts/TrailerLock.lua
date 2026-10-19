-- TrailerLock for Farming Simulator 22
-- Locks the yaw (side-to-side) rotation of double-trailer joints so the train stays straight.
-- ALT + L in a vehicle toggles the lock for the whole trailer chain.
-- The hitch on the tractor itself (root vehicle) always stays free.

TrailerLock = {}
TrailerLock.YAW_AXIS = 2 -- 1 = X, 2 = Y, 3 = Z
TrailerLock.CLEANUP_INTERVAL = 1000
TrailerLock.MIN_TURNTABLE_YAW = math.rad(5)
TrailerLock.MOD_NAME = g_currentModName

-- vehicles whose component joints are locked (server only), so we can unlock them after detaching
TrailerLock.lockedComponentVehicles = {}
TrailerLock.cleanupTimer = 0

local function log(fmt, ...)
    print(string.format("[TrailerLock] " .. fmt, ...))
end

local function notify(text, isError)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        local notificationType = isError and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_OK
        g_currentMission:addIngameNotification(notificationType, text)
    else
        log("%s", text)
    end
end

----------------------------------------------------------------------
-- Turntable joints (component joints inside one trailer)
----------------------------------------------------------------------

-- A turntable joint mainly rotates around Y. Many trailers also allow a little X / Z tilt for bumps,
-- so only require the Y limit to be clearly the largest one.
local function isTurntableJoint(joint)
    if joint.trailerLockBackup ~= nil then
        return true
    end
    local rotLimit = joint.rotLimit
    if rotLimit == nil or joint.rotMinLimit == nil then
        return false
    end
    local yaw = math.abs(rotLimit[2] or 0)
    return yaw >= TrailerLock.MIN_TURNTABLE_YAW
        and math.abs(rotLimit[1] or 0) <= yaw * 0.5
        and math.abs(rotLimit[3] or 0) <= yaw * 0.5
end

function TrailerLock:lockComponentJoints(vehicle)
    local count = 0
    if vehicle.componentJoints == nil or vehicle.setComponentJointRotLimit == nil then
        return count
    end
    for _, joint in ipairs(vehicle.componentJoints) do
        if isTurntableJoint(joint) then
            if joint.trailerLockBackup == nil then
                joint.trailerLockBackup = {
                    min = joint.rotMinLimit[TrailerLock.YAW_AXIS],
                    max = joint.rotLimit[TrailerLock.YAW_AXIS]
                }
            end
            vehicle:setComponentJointRotLimit(joint, TrailerLock.YAW_AXIS, 0, 0)
            count = count + 1
        end
    end
    if count > 0 then
        TrailerLock.lockedComponentVehicles[vehicle] = true
    end
    return count
end

function TrailerLock:unlockComponentJoints(vehicle)
    if vehicle.componentJoints ~= nil and vehicle.setComponentJointRotLimit ~= nil then
        for _, joint in ipairs(vehicle.componentJoints) do
            local backup = joint.trailerLockBackup
            if backup ~= nil then
                vehicle:setComponentJointRotLimit(joint, TrailerLock.YAW_AXIS, backup.min, backup.max)
                joint.trailerLockBackup = nil
            end
        end
    end
    TrailerLock.lockedComponentVehicles[vehicle] = nil
end

----------------------------------------------------------------------
-- Attacher joints (dolly -> trailer, trailer -> trailer)
----------------------------------------------------------------------

local function applyAttacherYawLimit(implement, jointDesc)
    local ok, err = pcall(function()
        AttacherJoints.updateAttacherJointRotationLimit(implement, jointDesc, TrailerLock.YAW_AXIS, true, jointDesc.moveLimitAlpha or 1)
    end)
    if not ok then
        log("updateAttacherJointRotationLimit failed (%s), setting joint directly", tostring(err))
        local limit = implement.upperRotLimit ~= nil and implement.upperRotLimit[TrailerLock.YAW_AXIS] or 0
        setJointRotationLimit(jointDesc.jointIndex, TrailerLock.YAW_AXIS - 1, true, -limit, limit)
    end
end

function TrailerLock:lockAttacherJoint(attacherVehicle, implement)
    local jointDesc = attacherVehicle:getAttacherJointByJointDescIndex(implement.jointDescIndex)
    if jointDesc == nil or jointDesc.jointIndex == nil or jointDesc.jointIndex == 0 then
        return 0
    end
    if implement.attachingIsInProgress then
        return 0
    end
    if implement.lowerRotLimit == nil or implement.upperRotLimit == nil then
        return 0
    end

    implement.trailerLockLocked = true
    implement.lowerRotLimit[TrailerLock.YAW_AXIS] = 0
    implement.upperRotLimit[TrailerLock.YAW_AXIS] = 0
    applyAttacherYawLimit(implement, jointDesc)
    return 1
end

function TrailerLock:unlockAttacherJoint(attacherVehicle, implement)
    if not implement.trailerLockLocked then
        return
    end
    implement.trailerLockLocked = nil

    local jointDesc = attacherVehicle:getAttacherJointByJointDescIndex(implement.jointDescIndex)
    if jointDesc == nil or jointDesc.jointIndex == nil or jointDesc.jointIndex == 0 then
        return
    end

    -- let the game recalculate its normal limits
    local inputJoint = implement.object ~= nil and implement.object.getActiveInputAttacherJoint ~= nil and implement.object:getActiveInputAttacherJoint() or nil
    if inputJoint ~= nil then
        AttacherJoints.updateAttacherJointLimits(implement, jointDesc, inputJoint, TrailerLock.YAW_AXIS)
    end
    applyAttacherYawLimit(implement, jointDesc)
end

-- Keep locked joints at 0 if the game recalculates the limits
local originalUpdateAttacherJointLimits = AttacherJoints.updateAttacherJointLimits
AttacherJoints.updateAttacherJointLimits = function(implement, attacherJointDesc, inputAttacherJointDesc, axis, ...)
    local rotLimit, transLimit = originalUpdateAttacherJointLimits(implement, attacherJointDesc, inputAttacherJointDesc, axis, ...)
    if implement.trailerLockLocked and axis == TrailerLock.YAW_AXIS then
        implement.lowerRotLimit[axis] = 0
        implement.upperRotLimit[axis] = 0
    end
    return rotLimit, transLimit
end

----------------------------------------------------------------------
-- Whole chain
----------------------------------------------------------------------

-- Calls func(attacherVehicle, implement) for every attached implement in the chain
local function forEachImplement(vehicle, func)
    if vehicle.getAttachedImplements == nil then
        return
    end
    for _, implement in pairs(vehicle:getAttachedImplements()) do
        if implement.object ~= nil then
            func(vehicle, implement)
            forEachImplement(implement.object, func)
        end
    end
end

-- Server only. Returns the number of joints that were locked.
function TrailerLock:setLocked(rootVehicle, locked)
    local count = 0

    forEachImplement(rootVehicle, function(attacherVehicle, implement)
        local trailer = implement.object
        if locked then
            -- turntable inside every trailer
            count = count + self:lockComponentJoints(trailer)
            -- connection between two trailers (not the tractor hitch)
            if attacherVehicle ~= rootVehicle then
                count = count + self:lockAttacherJoint(attacherVehicle, implement)
            end
        else
            self:unlockComponentJoints(trailer)
            self:unlockAttacherJoint(attacherVehicle, implement)
        end
    end)

    rootVehicle.trailerLockActive = locked and count > 0

    if g_server ~= nil then
        g_server:broadcastEvent(TrailerLockEvent.new(rootVehicle, rootVehicle.trailerLockActive))
    end
    return count
end

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------

function TrailerLock:getControlledRootVehicle()
    local vehicle = g_currentMission ~= nil and g_currentMission.controlledVehicle or nil
    if vehicle == nil then
        return nil
    end
    return vehicle:getRootVehicle()
end

function TrailerLock:toggle()
    local rootVehicle = self:getControlledRootVehicle()
    if rootVehicle == nil then
        notify("Get in a vehicle first.", true)
        return
    end

    local lock = not rootVehicle.trailerLockActive

    if g_server ~= nil then
        local count = self:setLocked(rootVehicle, lock)
        log("%s: %d joint(s) %s", tostring(rootVehicle:getName()), count, lock and "locked" or "unlocked")
        if lock then
            if count > 0 then
                notify(string.format("Trailer joints locked (%d)", count), false)
            else
                notify("No trailer joints to lock (needs a dolly, turntable trailer or second trailer)", true)
            end
        else
            notify("Trailer joints unlocked", false)
        end
    else
        g_client:getServerConnection():sendEvent(TrailerLockEvent.new(rootVehicle, lock))
        notify(lock and "Trailer joints locked" or "Trailer joints unlocked", false)
    end
end

-- The hotkey is registered by the trailerLockInput specialization on every enterable vehicle,
-- because mission-level action events are not active while you sit in a vehicle.
local function addInputSpecialization(typeManager)
    if typeManager.typeName ~= "vehicle" then
        return
    end
    local specName = TrailerLock.MOD_NAME .. ".trailerLockInput"
    local numAdded = 0
    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        if typeEntry.specializationsByName["enterable"] ~= nil and typeEntry.specializationsByName[specName] == nil then
            typeManager:addSpecialization(typeName, specName)
            numAdded = numAdded + 1
        end
    end
    log("hotkey added to %d vehicle types", numAdded)
end

TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, addInputSpecialization)

----------------------------------------------------------------------
-- Mod event listener
----------------------------------------------------------------------

function TrailerLock:loadMap(name)
    addConsoleCommand("tlToggle", "Lock / unlock the trailer joints of the current vehicle", "toggle", self)
    log("loaded (ALT + L in a vehicle)")
end

function TrailerLock:deleteMap()
    removeConsoleCommand("tlToggle")
end

function TrailerLock:update(dt)
    -- HUD text while locked
    local rootVehicle = self:getControlledRootVehicle()
    if rootVehicle ~= nil and rootVehicle.trailerLockActive and g_currentMission.addExtraPrintText ~= nil then
        g_currentMission:addExtraPrintText("Trailer lock: ON (ALT + L to unlock)")
    end

    -- server: unlock turntables of trailers that were detached or whose train got unlocked
    if g_server ~= nil then
        self.cleanupTimer = self.cleanupTimer + dt
        if self.cleanupTimer > TrailerLock.CLEANUP_INTERVAL then
            self.cleanupTimer = 0
            for vehicle in pairs(TrailerLock.lockedComponentVehicles) do
                if vehicle.isDeleted then
                    TrailerLock.lockedComponentVehicles[vehicle] = nil
                else
                    local root = vehicle:getRootVehicle()
                    if root == vehicle or not root.trailerLockActive then
                        self:unlockComponentJoints(vehicle)
                    end
                end
            end
        end
    end
end

addModEventListener(TrailerLock)
