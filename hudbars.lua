local S = minetest.get_translator("hudbars")

local function custom_hud(player)
	-- pipeworks fake player check
	if not player.get_attribute or not stamina_enabled then
		return nil
	end

	local old = get_int_attribute(player)

	if level == old then -- To suppress HUD update
		return
	end

	-- players without interact priv cannot eat
	if not minetest.check_player_privs(player, {interact = true}) then
		return
	end

	hb.init_hudbar(player, "stamina", level, nil, false)
end

function update_hud(player, s)
	hb.change_hudbar(player, "stamina", s)	
end

hb.register_hudbar("stamina", 0xFFFFFF, S("Stamina"), { bar = "hudbars_bar_stamina.png" }, 20, 20, false)


minetest.register_on_joinplayer(function(player)
	custom_hud(player)
end)

minetest.register_on_leaveplayer(function(player)
end)