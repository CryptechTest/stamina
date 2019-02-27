
stamina = {players = {}}

STAMINA_TICK = 800			-- time in seconds after that 1 stamina point is taken
STAMINA_TICK_MIN = 4		-- stamina ticks won't reduce stamina below this level
STAMINA_HEALTH_TICK = 4		-- time in seconds after player gets healed/damaged
STAMINA_MOVE_TICK = 0.5		-- time in seconds after the movement is checked
STAMINA_POISON_TICK = 1.25	-- time in seconds after player is poisoned

STAMINA_EXHAUST_DIG = 3		-- exhaustion increased this value after digged node
STAMINA_EXHAUST_PLACE = 1	-- .. after digging node
STAMINA_EXHAUST_MOVE = 1.5	-- .. if player movement detected
STAMINA_EXHAUST_JUMP = 5	-- .. if jumping
STAMINA_EXHAUST_CRAFT = 20	-- .. if player crafts
STAMINA_EXHAUST_PUNCH = 40	-- .. if player punches another player
STAMINA_EXHAUST_LVL = 160	-- at what exhaustion player saturation gets lowered

STAMINA_HEAL = 1			-- number of HP player gets healed after STAMINA_HEALTH_TICK
STAMINA_HEAL_LVL = 5		-- lower level of saturation needed to get healed
STAMINA_STARVE = 1			-- number of HP player gets damaged by stamina after STAMINA_HEALTH_TICK
STAMINA_STARVE_LVL = 3		-- level of staturation that causes starving

STAMINA_VISUAL_MAX = 20		-- hud bar extends only to 20

SPRINT_SPEED = 0.3			-- how much faster player can run if satiated
SPRINT_JUMP = 0.1			-- how much higher player can jump if satiated
SPRINT_DRAIN = 0.35			-- how fast to drain satation while sprinting (0-1)


local function get_int_attribute(player, key)

	if not player.get_attribute then return nil end -- pipeworks fake player check

	local level = player:get_attribute(key)

	if level then
		return tonumber(level)
	else
		return nil
	end
end


local function stamina_update_level(player, level)

	if not player.get_attribute then return nil end -- pipeworks fake player check

	local old = get_int_attribute(player, "stamina:level")

	if level == old then  -- To suppress HUD update
		return
	end

	player:set_attribute("stamina:level", level)

	player:hud_change(player:get_attribute("stamina:hud_id"), "number",
			math.min(STAMINA_VISUAL_MAX, level))
end


-- global function for mods to amend stamina level
stamina.change = function(player, change)

	local name = player:get_player_name()

	if not name or not change or change == 0 then
		return false
	end

	local level = get_int_attribute(player, "stamina:level") + change

	if level < 0 then level = 0 end

	if level > STAMINA_VISUAL_MAX then level = STAMINA_VISUAL_MAX end

	stamina_update_level(player, level)

	return true
end


local function exhaust_player(player, v)

	if not player
	or not player.is_player
	or not player:is_player()
	or not player.set_attribute then
		return
	end

	local name = player:get_player_name()

	if not name then
		return
	end

	local exhaustion = get_int_attribute(player, "stamina:exhaustion") or 0

	exhaustion = exhaustion + v

	if exhaustion > STAMINA_EXHAUST_LVL then

		exhaustion = 0

		local h = get_int_attribute(player, "stamina:level")

		if h > 0 then
			stamina_update_level(player, h - 1)
		end
	end

	player:set_attribute("stamina:exhaustion", exhaustion)
end


-- Sprint settings and function
local enable_sprint = minetest.setting_getbool("sprint") ~= false
local enable_sprint_particles = minetest.setting_getbool("sprint_particles") ~= false
--local armor_mod = minetest.get_modpath("3d_armor")
local monoids = minetest.get_modpath("player_monoids")
local pova_mod = minetest.get_modpath("pova")


local function set_sprinting(name, sprinting)

	local player = minetest.get_player_by_name(name)

	-- get player physics
	local def = player:get_physics_override()

--print ("---", def.speed, def.jump)

	if sprinting == true and not stamina.players[name].sprint then

		if monoids then

			stamina.players[name].sprint = player_monoids.speed:add_change(
					player, def.speed + SPRINT_SPEED)

			stamina.players[name].jump = player_monoids.jump:add_change(
					player, def.jump + SPRINT_JUMP)

		elseif pova_mod then

			pova.add_override(name, "sprint",
					{speed = SPRINT_SPEED, jump = SPRINT_JUMP})

			pova.do_override(player)

			stamina.players[name].sprint = true
		else
			player:set_physics_override({
				speed = def.speed + SPRINT_SPEED,
				jump = def.jump + SPRINT_JUMP,
			})

			stamina.players[name].sprint = true
		end

	elseif sprinting == false and stamina.players[name].sprint then

		if monoids then

			player_monoids.speed:del_change(player, stamina.players[name].speed)
			player_monoids.jump:del_change(player, stamina.players[name].jump)

			stamina.players[name].sprint = nil
			stamina.players[name].jump = nil

		elseif pova_mod then

			pova.del_override(name, "sprint")
			pova.do_override(player)

			stamina.players[name].sprint = nil
		else
			player:set_physics_override({
				speed = def.speed - SPRINT_SPEED,
				jump = def.jump - SPRINT_JUMP,
			})

			stamina.players[name].sprint = nil
		end
	end
end


-- Time based stamina functions
local stamina_timer = 0
local health_timer = 0
local action_timer = 0
local poison_timer = 0
local drunk_timer = 0

local function stamina_globaltimer(dtime)

	stamina_timer = stamina_timer + dtime
	health_timer = health_timer + dtime
	action_timer = action_timer + dtime
	poison_timer = poison_timer + dtime
	drunk_timer = drunk_timer + dtime

	for _,player in ipairs(minetest.get_connected_players()) do

		-- simulate drunk walking (thanks LumberJ)
		if drunk_timer > 1.0 then

			local name = player:get_player_name()

			if stamina.players[name] and stamina.players[name].drunk then

				local yaw = player:get_look_horizontal()

				yaw = yaw + math.random(-0.5, 0.5)

				player:set_look_horizontal(yaw)

				stamina.players[name].drunk = stamina.players[name].drunk - 1

				if stamina.players[name].drunk < 0 then
					stamina.players[name].drunk = nil
				end
			end

			drunk_timer = 0
		end

		-- hurt player when poisoned
		if poison_timer > STAMINA_POISON_TICK then

			local name = player:get_player_name()

			if stamina.players[name].poisoned
			and stamina.players[name].poisoned > 0 then

				stamina.players[name].poisoned =
						stamina.players[name].poisoned - STAMINA_POISON_TICK

				local hp = player:get_hp() - 1 or 0

				if hp > 0 then
					player:set_hp(hp)
				end

			elseif stamina.players[name].poisoned then

				player:hud_change(player:get_attribute("stamina:hud_id"),
						"text", "stamina_hud_fg.png")

				stamina.players[name].poisoned = nil
			end

			poison_timer = 0
		end

		-- sprint control and particle animation
		if action_timer > STAMINA_MOVE_TICK then

			local controls = player:get_player_control()

			-- Determine if the player is walking
			if controls.jump then
				exhaust_player(player, STAMINA_EXHAUST_JUMP)

			elseif controls.up
			or controls.down
			or controls.left
			or controls.right then
				exhaust_player(player, STAMINA_EXHAUST_MOVE)
			end

			--- START sprint
			if enable_sprint then

				local name = player:get_player_name()

				-- check if player can sprint (stamina must be over 6 points)
				if not stamina.players[name].poisoned
				and controls.aux1 and controls.up
				and not minetest.check_player_privs(player, {fast = true})
				and get_int_attribute(player, "stamina:level") > 6 then

					set_sprinting(name, true)

					-- create particles behind player when sprinting
					if enable_sprint_particles then

						local pos = player:get_pos()
						local node = minetest.get_node({
							x = pos.x, y = pos.y - 1, z = pos.z})

						if node.name ~= "air" then

						minetest.add_particlespawner({
							amount = 5,
							time = 0.01,
							minpos = {x = pos.x - 0.25, y = pos.y + 0.1, z = pos.z - 0.25},
							maxpos = {x = pos.x + 0.25, y = pos.y + 0.1, z = pos.z + 0.25},
							minvel = {x = -0.5, y = 1, z = -0.5},
							maxvel = {x = 0.5, y = 2, z = 0.5},
							minacc = {x = 0, y = -5, z = 0},
							maxacc = {x = 0, y = -12, z = 0},
							minexptime = 0.25,
							maxexptime = 0.5,
							minsize = 0.5,
							maxsize = 1.0,
							vertical = false,
							collisiondetection = false,
							texture = "default_dirt.png",
						})

						end
					end

					-- Lower the player's stamina when sprinting
					local level = get_int_attribute(player, "stamina:level")

					stamina_update_level(player,
							level - (SPRINT_DRAIN * STAMINA_MOVE_TICK))
				else
					set_sprinting(name, false)
				end
			end
			-- END sprint

			action_timer = 0
		end

		-- lower saturation by 1 point after STAMINA_TICK
		if stamina_timer > STAMINA_TICK then

			local h = get_int_attribute(player, "stamina:level")

			if h > STAMINA_TICK_MIN then
				stamina_update_level(player, h - 1)
			end

			stamina_timer = 0
		end

		-- heal or damage player, depending on saturation
		if health_timer > STAMINA_HEALTH_TICK then

			local air = player:get_breath() or 0
			local hp = player:get_hp()

			-- don't heal if drowning or dead or poisoned
			local h = get_int_attribute(player, "stamina:level")

			if h >= STAMINA_HEAL_LVL
			and h >= hp
			and hp > 0
			and air > 0
			and not stamina.players[player:get_player_name()].poisoned then

				player:set_hp(hp + STAMINA_HEAL)

				stamina_update_level(player, h - 1)
			end

			-- or damage player by 1 hp if saturation is < 2 (of 30)
			if get_int_attribute(player, "stamina:level") < STAMINA_STARVE_LVL then
				player:set_hp(hp - STAMINA_STARVE)
			end

			health_timer = 0
		end
	end -- player loop
end


-- override core.do_item_eat() so we can redirect hp_change to stamina
core.do_item_eat = function(hp_change, replace_with_item, itemstack, user, pointed_thing)

	if user.is_fake_player then
		return -- abort if called by fake player (eg. pipeworks-wielder)
	end

	local old_itemstack = itemstack

	itemstack = stamina.eat(hp_change, replace_with_item, itemstack, user, pointed_thing)

	for _, callback in pairs(core.registered_on_item_eats) do

		local result = callback(hp_change, replace_with_item, itemstack, user,
				pointed_thing, old_itemstack)

		if result then
			return result
		end
	end

	return itemstack
end


-- not local since it's called from within core context
function stamina.eat(hp_change, replace_with_item, itemstack, user, pointed_thing)

	if not itemstack or not user then
		return itemstack
	end

	local level = get_int_attribute(user, "stamina:level") or 0

	if level >= STAMINA_VISUAL_MAX then
		return itemstack
	end

	if hp_change > 0 then

		level = level + hp_change
		stamina_update_level(user, level)

	elseif hp_change < 0 then

		-- assume hp_change < 0
		user:hud_change(user:get_attribute("stamina:hud_id"), "text",
				"stamina_hud_poison.png")

		stamina.players[user:get_player_name()].poisoned = -hp_change
	end

	minetest.sound_play("stamina_eat",
			{to_player = user:get_player_name(), gain = 0.7})

	-- particle effect when eating
	local pos = user:get_pos() ; pos.y = pos.y + 1.5 -- mouth level
	local itemname = itemstack:get_name()
	local texture  = minetest.registered_items[itemname].inventory_image
	local dir = user:get_look_dir()

	minetest.add_particlespawner({
		amount = 5,
		time = 0.1,
		minpos = pos,
		maxpos = pos,
		minvel = {x = dir.x - 1, y = dir.y, z = dir.z - 1},
		maxvel = {x = dir.x + 1, y = dir.y, z = dir.z + 1},
		minacc = {x = 0, y = -5, z = 0},
		maxacc = {x = 0, y = -9, z = 0},
		minexptime = 1,
		maxexptime = 1,
		minsize = 1,
		maxsize = 2,
		texture = texture,
	})

	itemstack:take_item()

	if replace_with_item then

		if itemstack:is_empty() then
			itemstack:add_item(replace_with_item)
		else
			local inv = user:get_inventory()

			if inv:room_for_item("main", {name = replace_with_item}) then
				inv:add_item("main", replace_with_item)
			else
				pos.y = math.floor(pos.y - 1.0)
				core.add_item(pos, replace_with_item)
			end
		end
	end

	-- check for alcohol
	local units = minetest.registered_items[itemname].groups
			and minetest.registered_items[itemname].groups.alcohol or 0

	if units > 0 then

		local name = user:get_player_name()

		stamina.players[name].units = (stamina.players[name].units or 0) + 1

		if stamina.players[name].units > 2 then
			stamina.players[name].drunk = 60
			stamina.players[name].units = 0
		end
	end

	return itemstack
end


-- stamina is disabled if damage is disabled
if minetest.setting_getbool("enable_damage")
and minetest.setting_get("enable_stamina") ~= false then

	minetest.register_on_joinplayer(function(player)

		local level = STAMINA_VISUAL_MAX -- TODO

		if get_int_attribute(player, "stamina:level") then

			level = math.min(get_int_attribute(player, "stamina:level"),
					STAMINA_VISUAL_MAX)
		else
			player:set_attribute("stamina:level", level)
		end

		local id = player:hud_add({
			name = "stamina",
			hud_elem_type = "statbar",
			position = {x = 0.5, y = 1},
			size = {x = 24, y = 24},
			text = "stamina_hud_fg.png",
			number = level,
			alignment = {x = -1, y = -1},
			offset = {x = -266, y = -110},
			max = 0,
		})

		player:set_attribute("stamina:hud_id", id)
		player:set_attribute("stamina:exhaustion", 0) -- reset
	end)

	minetest.register_globalstep(stamina_globaltimer)

	minetest.register_on_placenode(function(pos, oldnode, player, ext)
		exhaust_player(player, STAMINA_EXHAUST_PLACE)
	end)

	minetest.register_on_dignode(function(pos, oldnode, player, ext)
		exhaust_player(player, STAMINA_EXHAUST_DIG)
	end)

	minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
		exhaust_player(player, STAMINA_EXHAUST_CRAFT)
	end)

	minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
		exhaust_player(hitter, STAMINA_EXHAUST_PUNCH)
	end)

	minetest.register_on_respawnplayer(function(player)
		stamina.players[player:get_player_name()] = {poisoned = nil, sprint = nil}
		stamina_update_level(player, STAMINA_VISUAL_MAX)
	end)
end


-- create player table on join
minetest.register_on_joinplayer(function(player)
	stamina.players[player:get_player_name()] = {poisoned = nil, sprint = nil}
end)


-- clear when player leaves
minetest.register_on_leaveplayer(function(player)
	stamina.players[player:get_player_name()] = nil
end)
