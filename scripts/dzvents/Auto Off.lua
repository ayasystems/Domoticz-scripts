-- This script will run every minute and can automatically send an 'Off' command to turn off any device after
-- it has been on for some specified time. Each device can be individually configured by putting json coded 
-- settings into the device's description field. The settings currently supported are:
-- - "auto_off_minutes" : <time in minutes>
-- - "auto_off_motion_device" : "<name of a motion detection device>"
-- If "auto_off_minutes" is not set, the device will never be turned off by this script. If 
-- "auto_off_minutes" is set and <time in minutes> is a valid number, the device will be turned off when it 
-- is found to be on plus the device's lastUpdate is at least <time in minutes> minutes old. This behavior 
-- can be further modified by specifying a valid device name after "auto_off_motion_device". When a motion 
-- device is specified and the device's lastUpdate is at least <time in minutes> old, the device will not 
-- be turned off until the motion device is off and it's lastUpdate is also <time in minutes> old. 
-- Specifying "auto_off_motion_device" without specifying "auto_off_minutes" does nothing.
--
-- Example 1: turn off the device after 2 minutes:
-- {
-- "auto_off_minutes": 2
-- }
--
-- Example 2: turn off the device when it has been on for 5 minutes and no motion has been detected for 
-- at least 5 minutes:
-- {
-- "auto_off_minutes": 5,
-- "auto_off_motion_device": "Overloop: Motion"
-- }

return {
	on = {

		-- timer triggers
		timer = {
			'every minute'
		}
	},

	execute = function(domoticz, triggeredItem, info)
	    local cnt = 0

		domoticz.devices().forEach(
	        function(device)
	            cnt = cnt + 1
	            if device.state ~= 'Off' then
    	            local description = device.description
    	            if description ~= nil and description ~= '' then
    	                local ok, settings = pcall( domoticz.utils.fromJSON, description)
    	                if ok and settings ~= nil then
    	                    if settings.auto_off_minutes ~= nil and device.lastUpdate.minutesAgo >= tonumber(settings.auto_off_minutes) then
	                            if settings.auto_off_motion_device == nil then
            		                domoticz.log(device.name .. ' is switched off because it has been on for ' .. settings.auto_off_minutes .. ' minutes.', domoticz.LOG_INFO)
	                                device.switchOff()
	                            elseif type(settings.auto_off_motion_device) == "string" then
	                                local motion_device = domoticz.devices(settings.auto_off_motion_device)
                                    if motion_device.state == 'Off' and motion_device.lastUpdate.minutesAgo >= tonumber(settings.auto_off_minutes) then
                		                domoticz.log(device.name .. ' is switched off because no one was in the room for ' .. settings.auto_off_minutes .. ' minutes.', domoticz.LOG_INFO)
    	                                device.switchOff()
                                    end
                                elseif type(settings.auto_off_motion_device) == "table" then
                                    local off = true
                                    for i,v in ipairs(settings.auto_off_motion_device) do
                                        local d = domoticz.devices(v)
                                        if d.state ~= 'Off' or d.lastUpdate.minutesAgo < tonumber(settings.auto_off_minutes) then
                                            off = false
                                        end
                                    end
                                    if off then
                		                domoticz.log(device.name .. ' is switched off because no one was in the room for ' .. settings.auto_off_minutes .. ' minutes.', domoticz.LOG_INFO)
                                        device.switchOff()
                                    end
	                            end
                            end 
                        else
                            domoticz.log( 'Device description for '.. device.name ..' is not in json format. Ignoring this device.', domoticz.LOG_ERROR)
                        end
                    end
                end
            end
        )
    
        domoticz.log('Scanned ' .. tostring(cnt) .. ' devices.', domoticz.LOG_INFO)
    

        -- Set ventilation back to automatic after 2 hours of manual control.
--        local hs = domoticz.devices('Humidity setting')
--        if hs.state ~= 'On' and hs.lastUpdate.hoursAgo >= 2 then
--            hs.switchOn()
--        end
    
	end
}