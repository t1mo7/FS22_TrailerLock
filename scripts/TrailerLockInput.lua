-- TrailerLockInput: vehicle specialization that registers the ALT + L hotkey.
-- The hotkey has to live on the vehicle, because FS22 switches to the vehicle input context
-- while you drive and global (mission) action events are not active there.

TrailerLockInput = {}
TrailerLockInput.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".trailerLockInput"

function TrailerLockInput.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Enterable, specializations)
end

function TrailerLockInput.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", TrailerLockInput)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", TrailerLockInput)
end

function TrailerLockInput:onLoad(savegame)
    local spec = self[TrailerLockInput.SPEC_TABLE_NAME]
    spec.actionEvents = {}
end

function TrailerLockInput:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self[TrailerLockInput.SPEC_TABLE_NAME]
    self:clearActionEventsTable(spec.actionEvents)

    if isActiveForInputIgnoreSelection and InputAction.TRAILER_LOCK_TOGGLE ~= nil then
        local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.TRAILER_LOCK_TOGGLE, self, TrailerLockInput.actionEventToggle, false, true, false, true, nil)
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
        g_inputBinding:setActionEventTextVisibility(actionEventId, false)
    end
end

function TrailerLockInput.actionEventToggle(self, actionName, inputValue, callbackState, isAnalog)
    TrailerLock:toggle()
end
