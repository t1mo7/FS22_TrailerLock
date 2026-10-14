-- TrailerLockEvent: client asks the server to (un)lock, server tells all clients the new state

TrailerLockEvent = {}
local TrailerLockEvent_mt = Class(TrailerLockEvent, Event)
InitEventClass(TrailerLockEvent, "TrailerLockEvent")

function TrailerLockEvent.emptyNew()
    return Event.new(TrailerLockEvent_mt)
end

function TrailerLockEvent.new(vehicle, locked)
    local self = TrailerLockEvent.emptyNew()
    self.vehicle = vehicle
    self.locked = locked
    return self
end

function TrailerLockEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.locked = streamReadBool(streamId)
    self:run(connection)
end

function TrailerLockEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.locked)
end

function TrailerLockEvent:run(connection)
    if self.vehicle == nil then
        return
    end
    if not connection:getIsServer() then
        -- we are the server: apply and tell everybody
        TrailerLock:setLocked(self.vehicle, self.locked)
    else
        -- we are a client: only remember the state for the HUD
        self.vehicle.trailerLockActive = self.locked
    end
end
