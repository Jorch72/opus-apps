local Config = require('config')
local GPS    = require('gps')
local Util   = require('util')

local args       = { ... }
local colors     = _G.colors
local fs         = _G.fs
local gps 			 = _G.gps
local os         = _G.os
local peripheral = _G.peripheral
local read       = _G.read
local term       = _G.term
local turtle     = _G.turtle
local vector     = _G.vector

local WIRED_MODEM = 'computercraft:wired_modem_full'
local CABLE       = 'computercraft:cable'
local ENDER_MODEM = 'computercraft:advanced_modem'

local STARTUP_FILE = 'usr/autorun/gpsServer.lua'

local positions = { }

local function build()
	if not turtle.has(WIRED_MODEM, 5) or
		 not turtle.has(CABLE, 8) or
		 not turtle.has(ENDER_MODEM, 4) then
		error([[Place into inventory:
 * 5 Wired modem (blocks)
 * 8 Network cables
 * 4 Ender modems]])
	end

	term.clear()
	term.setCursorPos(1, 2)
	term.setTextColor(colors.yellow)
	print('    Turtle must be facing east\n')
	term.setTextColor(colors.white)
	print(' Enter to continue or ctrl-t to abort')
	read()

	term.clear()
	term.setCursorPos(1, 2)
	print('building...')

	local blocks = {
		{ x =  0, y = 0, z =  0, b = WIRED_MODEM },

		{ x =  1, y = 0, z =  0, b = CABLE },
		{ x =  2, y = 0, z =  0, b = CABLE },
		{ x =  2, y = 1, z =  0, b = CABLE },
		{ x =  2, y = 2, z =  0, b = WIRED_MODEM },
		{ x =  2, y = 3, z =  0, b = ENDER_MODEM },

		{ x = -1, y = 0, z =  0, b = CABLE },
		{ x = -2, y = 0, z =  0, b = CABLE },
		{ x = -2, y = 1, z =  0, b = CABLE },
		{ x = -2, y = 2, z =  0, b = WIRED_MODEM },
		{ x = -2, y = 3, z =  0, b = ENDER_MODEM },

		{ x =  0, y = 0, z =  1, b = CABLE },
		{ x =  0, y = 0, z =  2, b = WIRED_MODEM },
		{ x =  0, y = 1, z =  2, b = ENDER_MODEM },

		{ x =  0, y = 0, z = -1, b = CABLE },
		{ x =  0, y = 0, z = -2, b = WIRED_MODEM },
		{ x =  0, y = 1, z = -2, b = ENDER_MODEM },
	}

	for _,v in ipairs(blocks) do
		turtle.placeDownAt(v, v.b)
	end
end

local function configure()
	local function getOption(prompt)
		while true do
			term.write(prompt)
			local value = read()
			if tonumber(value) then
				return tonumber(value)
			end
			print('Invalid value, try again.\n')
		end
	end

	print('Server configuration\n\n')

	Config.update('gpsServer', {
		x = getOption('Turtle x: '),
		y = getOption('Turtle y: '),
		z = getOption('Turtle z: '),
		east = getOption('East modem: modem_'),
		south = getOption('South modem: modem_'),
		west = getOption('West modem: modem_'),
		north = getOption('North modem: modem_'),
	})

	print('Make sure all wired modems are activated')
	print('Enter to continue')
	read()

	if not fs.exists(STARTUP_FILE) then
		Util.writeFile(STARTUP_FILE,
			[[shell.openForegroundTab('gpsServer.lua server')]])
		print('Autorun program created: ' .. STARTUP_FILE)
	end
end

local function memoize(t, k, fn)
	local e = t[k]
	if not e then
		e = fn()
		t[k] = e
	end
	return e
end

local function server()
	local computers = { }

	if not fs.exists('usr/config/gpsServer') then
		configure()
	end

	local config = Config.load('gpsServer')

	local modems = { }
	modems['modem_' .. config.east]  = { x = config.x + 2, y = config.y + 1, z = config.z     }
	modems['modem_' .. config.west]  = { x = config.x - 2, y = config.y + 1, z = config.z     }
	modems['modem_' .. config.south] = { x = config.x,     y = config.y - 1, z = config.z + 2 }
	modems['modem_' .. config.north] = { x = config.x,     y = config.y - 1, z = config.z - 2 }

	for k, modem in pairs(modems) do
		Util.merge(modem, peripheral.wrap(k) or { })
		Util.print('%s: %d %d %d', k, modem.x, modem.y, modem.z)
		if not modem.open then
			error('Modem is not activated or connected: ' .. k)
		end
		modem.open(gps.CHANNEL_GPS)
		--modem.open(999)
	end

	print('\nStarting GPS Server')

	local function getPosition(computerId, modem, distance)
		local computer = memoize(computers, computerId, function() return { } end)
		table.insert(computer, {
			position = vector.new(modem.x, modem.y, modem.z),
			distance = distance,
		})
		if #computer == 4 then
			local pt = GPS.trilaterate(computer)
			if pt then
				positions[computerId] = pt
				term.clear()
				for k,v in pairs(positions) do
					Util.print('ID: %d: %s %s %s', k, v.x, v.y, v.z)
				end
			end
			computers[computerId] = nil
		end
	end

	while true do
		local e, side, channel, computerId, message, distance = os.pullEvent( "modem_message" )
		if e == "modem_message" then
			if distance and modems[side] then
				if channel == gps.CHANNEL_GPS and message == "PING" then
					for _, modem in pairs(modems) do
						modem.transmit(computerId, gps.CHANNEL_GPS, { modem.x, modem.y, modem.z })
					end
					getPosition(computerId, modems[side], distance)
				end

				--if channel == gps.CHANNEL_GPS or channel == 999 then
				--	getPosition(computerId, modems[side], distance)
				--end
			end
		end
	end
end

if args[1] == 'build' then
	local y = tonumber(args[2] or 0)

	turtle.setPoint({ x = 0, y = -y, z = 0, heading = 0 })
	build()
	turtle.go({ x = 0, y = 1, z = 0, heading = 0 })

	configure()

	server()

elseif args[1] == 'server' then
	server()

else

	error('Syntax: gpsServer [build | server]')
end
