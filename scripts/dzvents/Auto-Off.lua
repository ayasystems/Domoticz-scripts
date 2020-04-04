-- Auto-Off (v2) by Richard Rozema
--
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
--
-- Example 3: turn off the device when it has been on for 1 minute and not motion was detected for at least 1 
-- minute on either one of a set of motion sensors.
-- {
-- "auto_off_minutes": 1,
-- "auto_off_motion_device": ["Overloop 1: Motion 1", "Overloop 1: Motion 2"]
-- }

local AUTOOFFVERSION = '2.03'

return {
	on = {

		timer = {
			'every minute'
		}
	},
	data = { 
	    triggers = {initial = {}},      -- Holds a list of (unique) motion devices and a list of devices it triggers.
	    triggered_by = {initial = {}}   -- Holds a list of (unique) triggered devices and a list of motion devices that trigger it.
	},
	logging = {
        level = domoticz.LOG_WARNING,
        marker = 'Generic Auto Off v' .. AUTOOFFVERSION
    },
	execute = function(domoticz, triggeredItem, info)
        local cnt = 0
        
        --domoticz.log( 'Generic Auto Off v' .. AUTOOFFVERSION .. ', Domoticz v' .. domoticz.settings.domoticzVersion .. '.', domoticz.LOG_INFO)
        domoticz.log( 'Generic Auto Off v' .. AUTOOFFVERSION .. ', Domoticz v' .. domoticz.settings.domoticzVersion .. ', Dzvents v' .. domoticz.settings.dzVentsVersion .. '.', domoticz.LOG_INFO)
        
        --domoticz.dump(domoticz.utils)
        --domoticz.utils.dumpTable(domoticz)
        --domoticz.utils.dumpTable(domoticz.utils)
        --domoticz.utils.dumpTable(domoticz.utils._)
        
        --local Time = require('Time')
        local now = domoticz.time
        
--        if domoticz.data.triggers == nil then
	        domoticz.data.triggers = {}
--	    end
	   
--	    if domoticz.data.triggered_by == nil then
            domoticz.data.triggered_by = {}
--	    end

        domoticz.devices().forEach(
	        function(device)
	            cnt = cnt + 1
	            local description
                local motion_device_names  -- If no settings are found we may still have to
                                           -- remove some device's motion devices from the 
                                           -- trigger lists. So we start with an empty list.

                motion_device_names = {}
                description = device.description

                if description ~= nil and description ~= '' then
                    local ok, settings = pcall( domoticz.utils.fromJSON, description)
                    if ok and settings ~= nil then
                        -- Determine highest level available in the settings that is 
                        -- lower than the current level where 'Off' equals level 0.
                        local dimlevel = nil;

                        -- Determine the list of motion devices configured for this
                        -- device in the settings.
                        if type(settings.auto_off_motion_device) == "string" then
                            table.insert( motion_device_names, settings.auto_off_motion_device)
                        elseif type(settings.auto_off_motion_device) == "table" then
                            for i,v in ipairs(settings.auto_off_motion_device) do
                                table.insert( motion_device_names, v)
                            end
                        end
                    
                        -- Lowest dim level is 'Off', this I will represent as level == 0.
                        -- If auto_off_minutes was specified and the device is not off, I 
                        -- will use this to initialise the dimlevel variable with a level 
                        -- of 0. If the device is off already, we don't need to change it.
                        if settings.auto_off_minutes ~= nil and device.bState then
                            dimlevel = { level = 0, minutes = settings.auto_off_minutes}
                        end
                        
                        -- If one or more dimlevels were specified, the user must think our
                        -- device is a dimmer switch, so it should be safe to reference
                        -- its level attribute. We search for the dimlevel that has the
                        -- highest level below that of our device's level.
                        if settings.auto_off_dimlevel ~= nil and type(settings.auto_off_dimlevel) == "table" then
                            -- if a single dimlevel was specified...
                            if settings.auto_off_dimlevel.level ~= nil then
                                if settings.auto_off_dimlevel.level < 0 then
                                    settings.auto_off_dimlevel.level = 0
                                elseif settings.auto_off_dimlevel.level > 100 then
                                    settings.auto_off_dimlevel.level = 100
                                end
                                    
                                if settings.auto_off_dimlevel.level < device.level then
                                    if dimlevel == nil or settings.auto_off_dimlevel.level > dimlevel.level then
                                        dimlevel = settings.auto_off_dimlevel
                                    end
                                end
                            else
                                -- or when multiple dimlevels were specified as a table of tables.
                                for i,v in ipairs(settings.auto_off_dimlevel) do
                                    if v.level < 0 then
                                        v.level = 0
                                    elseif v.level > 100 then
                                        v.level = 100
                                    end
                                    
                                    if v.level < device.level then
                                        if dimlevel == nil or v.level > dimlevel.level then
                                            dimlevel = v
                                        end
                                    end
                                end
                            end
                        end

                        -- If we have found a new dim level then see if it is time yet to
                        -- set this new level.
                        if dimlevel ~= nil then
                            local minutes = dimlevel.minutes
                            
                            -- Find the latest last modified date from our device plus
                            -- any motion devices that may have been specified. Initially
                            -- assume our device has the latest last modified date.
                            local lastUpdate = device.lastUpdate
                            
                            --domoticz.utils.dumpTable(lastUpdate)
                            
                            -- We will skip setting a new level if either of the following is true: 
                            -- at least one of the motion devices has state 'On' or the lastUpdate 
                            -- on our device or any of the specified motion devices is less than 
                            -- <minutes> ago. To accomplish this, lets find out if any of the 
                            -- motion devices has a more recent lastUpdate than that of our device.
                            -- If a motion device has state 'On', we will set lastUpdate to nil,
                            -- indicating we can skip the check for lastUpdate completely.
                            local motion_devices = domoticz.devices().filter(motion_device_names)
                            lastUpdate = motion_devices.reduce(
                                    function(acc, md)
                                        if md.timedOut ~= true then -- Ignore motion devices that have timed out, to 
                                                                    -- avoid leaving the light on because a sensor that 
                                                                    -- has an empty battery isn't updated to 'Off'.
                                            if acc ~= nil then      -- If a previous sensor was 'On', we will have set 
                                                                    -- lastUpdate to nil and we don't want to overwrite
                                                                    -- this.
                                                if md.bState then
                                                    --domoticz.utils._.print( 'Sensor ' .. md.name .. ' is on')
                                                    domoticz.log( 'Motion device ' .. md.name .. ' is On.', domoticz.LOG_DEBUG)

                                                    acc = nil               -- Set lastUpdate to nil to indicate at least 
                                                                            -- one sensor is 'On'.
                                                elseif md.lastUpdate.compare(acc).compare < 0 then  -- If acc < lastUpdate
                                                    domoticz.log( 'Motion device ' .. md.name .. ' was last modified ' .. md.lastUpdate.raw .. '.', domoticz.LOG_DEBUG)
                                                    acc = md.lastUpdate     -- We've found a more recent lastUpdate.
                                                end
                                            end
                                        else
                                            domoticz.log( 'Motion device ' .. md.name .. ' ignored because it timed out. Do you need to replace the battery?', domoticz.LOG_WARNING)
                                        end
                                        return acc -- Always return the accumulator.
                                    end, lastUpdate)

                            if lastUpdate ~= nil and lastUpdate.secondsAgo > tonumber(minutes * 60) then
                                if dimlevel.level > 0 then
            		                domoticz.log(device.name .. ' is dimmed to level ' .. dimlevel.level .. ' after ' .. dimlevel.minutes .. ' minutes.', domoticz.LOG_DEBUG)
                                    device.setLevel(tonumber(dimlevel.level))
                                else
            		                domoticz.log(device.name .. ' is switched off after ' .. dimlevel.minutes .. ' minutes.', domoticz.LOG_DEBUG)
                                    device.switchOff()
                                end
                            end
                        end
                    
                        -- Now see if we need to update our triggers lists. I keep a list of trigger devices that I 
                        -- use to see 1) which devices are our motion devices and 2) which devices need to be 
                        -- switched on for each motion device. Plus I keep an additional list of triggered devices 
                        -- so I can determine that a motion device was removed from the settings. Because in this 
                        -- case I need to remove it from the list of trigger devices too.
                        --

                        -- Do we need to add entries to the triggers lists?
                        --      For each of the motion devices in settings
                        --          If not exists data.triggers[ <settings.motion device> ]
                        --          Then
                        --              add a new entry in data.triggers with our current device in the list of devices to trigger.
                        --          Else
                        --              If our current device is not in the list of devices to trigger
                        --              Then
                        --                  Add our device to the list of devices to trigger.
                        --
                        --          If data.triggered_by does not have our device
                        --          Then
                        --              add a new entry in data.triggered_by for our current device with our motion device in the triggered_by list.
                        --          Else
                        --              If our motion device is not in the list of trigger devices
                        --              Then
                        --                  add the motion device to the list of trigger devices
                        -- 
                        
                        for i,v in ipairs(motion_device_names) do
                            if domoticz.data.triggers[v] == nil then
                                --domoticz.log('adding trigger ' .. v .. '.', domoticz.LOG_DEBUG)
                                domoticz.data.triggers[v] = {}
                            end
                            -- TODO: This code keeps adding entries, even though following if exists. Why?
                            if domoticz.data.triggers[v][device.name] == nil then
                                --domoticz.log('adding triggered device ' .. device.name .. '.', domoticz.LOG_DEBUG)
                                table.insert(domoticz.data.triggers[v], device.name)
                            end

                            if domoticz.data.triggered_by[device.name] == nil then
                                domoticz.data.triggered_by[device.name] = {}
                            end
                            if domoticz.data.triggered_by[device.name][v] == nil then
                                table.insert(domoticz.data.triggered_by[device.name], v)
                            end
                        end
                    else
                        domoticz.log( 'Device description for '.. device.name ..' is not in json format. Ignoring this device.', domoticz.LOG_WARNING)
                    end
                    
                    -- Do we need to remove entries from the triggers lists?
                    --      For each of the entries in the list of trigger devices from data.triggered_by[ <current device> ]
                    --          If settings does not have a motion device[ <listed motion device> ]
                    --          Then
                    --              remove data.triggered_by[<current device>][ <listed motion device> ]
                    --              If data.triggered_by[<current device>] has no more entries
                    --              Then 
                    --                  remove data.triggered_by[<current device>]
                    --              If exists data.triggers[ <listed motion device> ][ <current device> ]
                    --              Then
                    --                  remove data.triggers[ <listed motion device> ][ <current device> ]
                    --              If data.triggers[ <listed motion device> ] has no more entries
                    --                  remove data.triggers[ <listed motion device> ]
                    if domoticz.data.triggered_by[device.name] ~= nil then
                        for i,v in ipairs(domoticz.data.triggered_by[device.name]) do
                            if motion_device_names[v] == nil then
                                domoticz.data.triggered_by[device.name][v] = nil
                                if #(domoticz.data.triggered_by[device.name]) <= 0 then
                                    domoticz.data.triggered_by[device.name] = nil
                                end
                                if domoticz.data.triggers[v][device.name] ~= nil then
                                    domoticz.data.triggers[v][device.name] = nil
                                end
                                if #(domoticz.data.triggers[v]) <= 0 then
                                    domoticz.data.triggers[v] = nil
                                end
                            end
                        end
                    end
                end
            end
        )
    
        domoticz.log('Scanned ' .. tostring(cnt) .. ' devices.', domoticz.LOG_INFO)
    
        --domoticz.utils.dumpTable(domoticz.data.triggers)
        --domoticz.utils.dumpTable(domoticz.data.triggered_by)

	end
}