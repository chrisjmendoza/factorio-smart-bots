-- More charging pads per roboport, and robots that fly further per charge.
--
-- Pad contention is the half of the problem that needs no script: a vanilla
-- roboport has four charging points, so the fifth robot to arrive waits no
-- matter how much energy the roboport is sitting on.

local STATIONS = settings.startup["smartbots-charging-stations"].value
local POWER = settings.startup["smartbots-charging-power"].value
local BATTERY = settings.startup["smartbots-robot-battery"].value
local EFFICIENCY = settings.startup["smartbots-robot-efficiency"].value

local PREFIXES = {
	{1e18, "E"}, {1e15, "P"}, {1e12, "T"},
	{1e9, "G"}, {1e6, "M"}, {1e3, "k"},
}

-- Energy properties are strings such as "5MJ" or "1000kW". Rescaling one means
-- reading the magnitude out, multiplying, and writing a fresh string -- and it
-- has to be written in plain decimal, because "1.2e+06J" is not something the
-- prototype parser accepts.
local function format_energy(base, unit)
	for _, step in ipairs(PREFIXES) do
		if base >= step[1] then
			local text = string.format("%.4f", base / step[1])
			text = text:gsub("0+$", ""):gsub("%.$", "")
			return text .. step[2] .. unit
		end
	end
	local text = string.format("%.4f", base):gsub("0+$", ""):gsub("%.$", "")
	return text .. unit
end

local function scale_energy(value, factor)
	if type(value) ~= "string" or factor == 1 then return value end
	local number, prefix, unit = value:match("^%s*([%d%.]+)%s*(%a?)([JWjw])%s*$")
	if not number then return value end

	local multiplier = 1
	for _, step in ipairs(PREFIXES) do
		if prefix == step[2] then
			multiplier = step[1]
			break
		end
	end
	if prefix == "K" then multiplier = 1e3 end

	return format_energy(tonumber(number) * multiplier * factor, unit:upper())
end

local function xy(vector)
	if vector.x then return vector.x, vector.y end
	return vector[1], vector[2]
end

-- Charging points are laid out as an even ring rather than appended to the
-- author's four, so eight pads look deliberate instead of crowding one corner.
-- The radius is taken from the offsets already there, which keeps the ring on
-- the pad of a modded roboport of any size.
local function ring_offsets(existing, count)
	local radius, samples = 0, 0
	for _, offset in pairs(existing or {}) do
		local x, y = xy(offset)
		radius = radius + math.sqrt(x * x + y * y)
		samples = samples + 1
	end
	radius = samples > 0 and radius / samples or 1.6

	local out = {}
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		out[i] = {radius * math.cos(angle), radius * math.sin(angle)}
	end
	return out
end

local function upgrade_charging(prototype)
	prototype.charging_energy = scale_energy(prototype.charging_energy, POWER)

	-- charging_offsets is only consulted when charging_station_count is 0, so
	-- whichever one the author used is the one to raise.
	if prototype.charging_station_count and prototype.charging_station_count > 0 then
		prototype.charging_station_count = math.max(prototype.charging_station_count, STATIONS)
	else
		local existing = prototype.charging_offsets
		if existing and #existing >= STATIONS then return end
		prototype.charging_offsets = ring_offsets(existing, STATIONS)
	end
end

for _, prototype in pairs(data.raw["roboport"] or {}) do
	upgrade_charging(prototype)
end

-- Personal roboports queue robots the same way, and the script deliberately
-- leaves equipment alone, so the pad count is the only relief they get.
for _, prototype in pairs(data.raw["roboport-equipment"] or {}) do
	upgrade_charging(prototype)
end

for _, kind in ipairs({"logistic-robot", "construction-robot"}) do
	for _, prototype in pairs(data.raw[kind] or {}) do
		prototype.max_energy = scale_energy(prototype.max_energy, BATTERY)
		prototype.energy_per_move = scale_energy(prototype.energy_per_move, EFFICIENCY)
		prototype.energy_per_tick = scale_energy(prototype.energy_per_tick, EFFICIENCY)
	end
end
