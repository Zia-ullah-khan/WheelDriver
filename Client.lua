local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local vehicleSeat = script.Parent

local serverUrl = "http://192.168.1.157:5000"
local controlsEndpoint = serverUrl .. "/controls"
local updateControlsEndpoint = serverUrl .. "/update_controls"
local heartbeatEndpoint = serverUrl .. "/roblox_heartbeat"

local inputStates = {
	Throttle = 0,
	Steering = 0,
	Handbrake = false
}

local function logMessage(message, data)
    if data then
        print("🔄 " .. message .. ":", HttpService:JSONEncode(data))
    else
        print("🔄 " .. message)
    end
end

local requestQueue = {
    maxSize = 3,
    pending = 0,
    lastSentTime = 0,
    minInterval = 0.05
}

local function updateServer()
	local vehicleState = {
		CurrentSpeed = vehicleSeat.Velocity.Magnitude,
		Occupied = vehicleSeat.Occupant ~= nil,
		SeatOrientation = {
			X = vehicleSeat.CFrame.Position.X,
			Y = vehicleSeat.CFrame.Position.Y,
			Z = vehicleSeat.CFrame.Position.Z
		}
	}

    local now = os.clock()
    if requestQueue.pending >= requestQueue.maxSize or
       (now - requestQueue.lastSentTime) < requestQueue.minInterval then
        return
    end
    
    requestQueue.pending = requestQueue.pending + 1
    requestQueue.lastSentTime = now

	local jsonData = HttpService:JSONEncode(vehicleState)
    
    if totalRequests.updates % 10 == 0 then
        logMessage("Sending vehicle state to server", vehicleState)
    end

	task.spawn(function()
		pcall(function()
            local success, result = pcall(function()
                return HttpService:PostAsync(updateControlsEndpoint, jsonData, Enum.HttpContentType.ApplicationJson, false, {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json"
                })
            end)
            
            requestQueue.pending = math.max(0, requestQueue.pending - 1)
            
            if not success then
                logMessage("Failed to update server: " .. tostring(result))
            end
		end)
	end)
end

local targetInputs = {
    Throttle = 0,
    Steering = 0,
    Brake = 0,
    Handbrake = false
}

local function smoothlyApplyInputs()
    local alpha = 0.3
    
    -- Apply handbrake immediately (no smoothing)
    inputStates.Handbrake = targetInputs.Handbrake
    
    -- Smoothly interpolate steering, throttle and brake
    inputStates.Throttle = inputStates.Throttle + (targetInputs.Throttle - inputStates.Throttle) * alpha
    inputStates.Steering = inputStates.Steering + (targetInputs.Steering - inputStates.Steering) * alpha
    
    -- Apply to vehicle
    -- Use throttle directly as it's already 0 to 1
    vehicleSeat.ThrottleFloat = inputStates.Throttle
    
    -- Use steering directly
    vehicleSeat.SteerFloat = inputStates.Steering
    
    -- If we have brake value, apply it (should be implemented in the vehicle)
    if vehicleSeat:FindFirstChild("BrakeFloat") then
        vehicleSeat.BrakeFloat.Value = targetInputs.Brake
    end
    
    -- Apply handbrake if present
    if vehicleSeat:FindFirstChild("Handbrake") then
        vehicleSeat.Handbrake.Value = inputStates.Handbrake
    end
    
    -- Log current input state periodically
    if not _G.lastInputLog or (os.clock() - _G.lastInputLog) > 5 then
        _G.lastInputLog = os.clock()
        logMessage("Current vehicle inputs", {
            Throttle = inputStates.Throttle,
            Brake = targetInputs.Brake,
            Steering = inputStates.Steering,
            Handbrake = inputStates.Handbrake
        })
    end
end

local function getExternalControls()
    if requestQueue.pending >= requestQueue.maxSize then
        return
    end
    
    requestQueue.pending = requestQueue.pending + 1
    
	task.spawn(function()
		pcall(function()
			local success, response = pcall(function()
                return HttpService:GetAsync(controlsEndpoint, false, {
                    ["Accept"] = "application/json"
                })
            end)
            
            requestQueue.pending = math.max(0, requestQueue.pending - 1)
            
            if success then
                local controls = HttpService:JSONDecode(response)
                
                if totalRequests.controls % 20 == 0 then
                    logMessage("Received controls from server", controls)
                end
    
                -- Update target values from server
                if controls.Throttle ~= nil then
                    targetInputs.Throttle = controls.Throttle
                end
                
                if controls.Steering ~= nil then
                    targetInputs.Steering = controls.Steering
                end
                
                if controls.Brake ~= nil then
                    targetInputs.Brake = controls.Brake
                end
                
                if controls.Handbrake ~= nil then
                    targetInputs.Handbrake = controls.Handbrake
                end
    
            else
                logMessage("Failed to get controls: " .. tostring(response))
            end
		end)
	end)
end

local function sendHeartbeat()
    if requestQueue.pending >= requestQueue.maxSize then
        return
    end
    
    requestQueue.pending = requestQueue.pending + 1
    
    task.spawn(function()
        pcall(function()
            local success, result = pcall(function()
                return HttpService:PostAsync(heartbeatEndpoint, HttpService:JSONEncode({
                    timestamp = os.time(),
                    game = game.PlaceId,
                    player = game.Players.LocalPlayer and game.Players.LocalPlayer.Name or "None"
                }), Enum.HttpContentType.ApplicationJson, false, {
                    ["Content-Type"] = "application/json"
                })
            end)
            
            requestQueue.pending = math.max(0, requestQueue.pending - 1)
            
            if success then
                if totalRequests.heartbeats % 5 == 0 then
                    logMessage("Heartbeat sent successfully")
                end
            else
                -- Log all heartbeat failures to help diagnose issues
                logMessage("Failed to send heartbeat: " .. tostring(result))
            end
        end)
    end)
end

local pollRate = 0.1
local heartbeatRate = 1.0  -- Changed from 2.0 to 1.0 seconds
local lastHeartbeat = 0

local totalRequests = {
    heartbeats = 0,
    controls = 0,
    updates = 0
}

RunService.RenderStepped:Connect(function()
    smoothlyApplyInputs()
end)

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    
    if not _G.lastPoll or (now - _G.lastPoll) >= pollRate then
        _G.lastPoll = now
        getExternalControls()
        totalRequests.controls = totalRequests.controls + 1
        
        if totalRequests.controls % 2 == 0 then
            updateServer()
            totalRequests.updates = totalRequests.updates + 1
        end
        
        if totalRequests.controls % 100 == 0 then
            logMessage("Total requests made", totalRequests)
        end
    end
    
    if not lastHeartbeat or (now - lastHeartbeat) >= heartbeatRate then
        lastHeartbeat = now
        sendHeartbeat()
        totalRequests.heartbeats = totalRequests.heartbeats + 1
    end
end)

vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
    logMessage("Occupant changed, updating server")
	updateServer()
end)

logMessage("🚀 Wheel driver client starting with server URL: " .. serverUrl)
logMessage("Current vehicle seat properties", {
    Name = vehicleSeat.Name,
    HasHandbrake = vehicleSeat:FindFirstChild("Handbrake") ~= nil,
    HasBrake = vehicleSeat:FindFirstChild("BrakeFloat") ~= nil,
    ClassName = vehicleSeat.ClassName
})

-- Create BrakeFloat value if it doesn't exist
if not vehicleSeat:FindFirstChild("BrakeFloat") then
    local brakeValue = Instance.new("NumberValue")
    brakeValue.Name = "BrakeFloat"
    brakeValue.Value = 0
    brakeValue.Parent = vehicleSeat
    logMessage("Created BrakeFloat value for braking")
end

-- Send immediate heartbeat on script start
task.spawn(function()
    wait(1)  -- Brief delay to ensure everything is initialized
    sendHeartbeat()
    logMessage("Initial heartbeat sent")
end)

print("✅ Wheel driver client loaded - Using optimized networking with input smoothing and brake support")
