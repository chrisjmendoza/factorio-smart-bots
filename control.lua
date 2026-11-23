-- SmartBots: roboports lend their buffered energy to robots queued for a pad.
--
-- A robot that decides to charge commits to one roboport and waits there, even
-- when the pads are all busy and a neighbour two tiles away is idle. Nothing in
-- the API can undo that choice -- robot_order_queue is read-only and there is no
-- dispatch hook -- but LuaLogisticCell.to_charge_robots names exactly who is
-- waiting, and both robot and roboport energy are writable. So the queue is
-- served where it stands: energy flows out of the roboport's buffer into the
-- robots behind it in line, which moves the bottleneck off the pad count and
-- onto the power grid, where a factory can actually build its way out of it.

local CYCLE_TICKS = 30

-- How much of its buffer a roboport will part with. Roboports run their own
-- pads and doors off the same buffer, and one that empties itself stops working
-- until it has recovered recharge_minimum, so the floor is not optional.
local function spare_energy(port, reserve)
	return math.max(0, port.energy - port.electric_buffer_size * reserve)
end

-- The engine clamps the write at the robot's battery size, so what the robot
-- actually took is read back rather than assumed. That is what keeps the
-- transfer conserving: the roboport is only billed for energy that landed.
local function transfer(port, robot, joules)
	local before = robot.energy
	robot.energy = before + joules
	local moved = robot.energy - before
	if moved > 0 then
		port.energy = port.energy - moved
	end
	return moved
end

local function serve_cell(cell, opts)
	local port = cell.owner
	if not (port and port.valid) then return 0 end

	local waiting = cell.to_charge_robots
	if #waiting == 0 then return 0 end

	-- Drawn before the lending check so the overlay still reports queue depth
	-- when lending is switched off, which is how you see what it is worth.
	if opts.show then
		rendering.draw_text{
			text = tostring(#waiting),
			surface = port.surface,
			target = {entity = port, offset = {0, -1.2}},
			color = {r = 1, g = 0.55, b = 0.2},
			scale = 1.5,
			alignment = "center",
			time_to_live = CYCLE_TICKS + 1,
		}
	end

	if not opts.lend then return 0 end

	-- Neighbouring roboports are on the same logistic network and usually the
	-- same power grid, so a congested one can draw on the buffers around it
	-- instead of stalling once its own hits the reserve.
	local donors = {port}
	if opts.borrow then
		for _, other in pairs(cell.neighbours) do
			local owner = other.owner
			if not other.mobile and owner and owner.valid then
				donors[#donors + 1] = owner
			end
		end
	end

	local served, donor = 0, 1
	for _, robot in pairs(waiting) do
		if donor > #donors then break end
		if robot.valid then
			local moved = 0
			while donor <= #donors do
				local source = donors[donor]
				local available = math.min(opts.joules, spare_energy(source, opts.reserve))
				if available <= 0 then
					donor = donor + 1 -- this buffer is down to its reserve
				else
					-- A zero here means the robot was already full, not that
					-- the donor is spent, so the donor keeps its turn.
					moved = transfer(source, robot, available)
					break
				end
			end
			if moved > 0 then served = served + 1 end
		end
	end

	return served
end

local function congested_cells()
	local found = {}
	for _, force in pairs(game.forces) do
		for _, networks in pairs(force.logistic_networks) do
			for _, network in pairs(networks) do
				for _, cell in pairs(network.cells) do
					-- Mobile cells are personal roboports, where `owner` is the
					-- character or vehicle and its energy is not the equipment
					-- grid's. Draining a player's armour would be a surprise.
					if not cell.mobile and cell.to_charge_robot_count > 0 then
						found[#found + 1] = cell
					end
				end
			end
		end
	end
	return found
end

script.on_nth_tick(CYCLE_TICKS, function()
	local lend = settings.global["smartbots-enable-overflow"].value
	local show = settings.global["smartbots-show-queues"].value
	if not (lend or show) then return end

	local cells = congested_cells()
	local count = #cells
	if count == 0 then
		storage.cursor = 0
		return
	end

	local opts = {
		joules = settings.global["smartbots-overflow-power"].value * 1e6 * CYCLE_TICKS / 60,
		reserve = settings.global["smartbots-roboport-reserve"].value,
		borrow = settings.global["smartbots-borrow-from-neighbours"].value,
		lend = lend,
		show = show,
	}
	local budget = settings.global["smartbots-robots-per-cycle"].value

	-- Serving resumes where the last pass ran out of budget, so one busy corner
	-- of a megabase cannot starve every other queue on the map.
	local start = (storage.cursor or 0) % count
	local served = 0
	for i = 0, count - 1 do
		served = served + serve_cell(cells[(start + i) % count + 1], opts)
		storage.cursor = start + i + 1
		-- Robots served caps the work when lending; with only the overlay on
		-- nothing is served, so the cells looked at cap it instead.
		if served >= budget or i >= budget then break end
	end
end)
