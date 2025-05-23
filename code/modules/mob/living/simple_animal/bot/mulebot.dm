

// Mulebot - carries crates around for Quartermaster
// Navigates via floor navbeacons
// Remote Controlled from QM's PDA

#define SIGH 0
#define ANNOYED 1
#define DELIGHT 2

/mob/living/simple_animal/bot/mulebot
	name = "\improper MULEbot"
	desc = "A Multiple Utility Load Effector bot."
	icon_state = "mulebot0"
	density = TRUE
	move_resist = MOVE_FORCE_STRONG
	animate_movement = 1
	health = 50
	maxHealth = 50
	damage_coeff = list(BRUTE = 0.5, BURN = 0.7, TOX = 0, CLONE = 0, STAMINA = 0, OXY = 0)
	combat_mode = TRUE //No swapping
	can_toggle_combat = FALSE // I SAID NO SWAPPING
	buckle_lying = 0
	mob_size = MOB_SIZE_LARGE

	radio_key = /obj/item/encryptionkey/headset_cargo
	radio_channel = RADIO_CHANNEL_SUPPLY

	bot_type = MULE_BOT
	model = "MULE"
	bot_core_type = /obj/machinery/bot_core/mulebot

	/// unique identifier in case there are multiple mulebots.
	var/id

	path_image_color = "#7F5200"

	var/atom/movable/load = null
	var/mob/living/passenger = null
	var/turf/target				// this is turf to navigate to (location of beacon)
	var/loaddir = 0				// this the direction to unload onto/load from
	var/home_destination = "" 	// tag of home beacon

	var/reached_target = 1 	//true if already reached the target

	var/auto_return = 1		// true if auto return to home beacon after unload
	var/auto_pickup = 1 	// true if auto-pickup at beacon
	var/report_delivery = 1 // true if bot will announce an arrival to a location.

	var/obj/item/stock_parts/cell/cell
	var/bloodiness = 0

	///The amount of steps we should take until we rest for a time.
	var/num_steps = 0
	
/mob/living/simple_animal/bot/mulebot/Initialize(mapload)
	. = ..()
	wires = new /datum/wires/mulebot(src)
	var/datum/job/cargo_tech/J = new/datum/job/cargo_tech
	access_card.access = J.get_access()
	prev_access = access_card.access
	cell = new /obj/item/stock_parts/cell/upgraded(src, 2000)

	var/static/mulebot_count = 0
	mulebot_count += 1
	set_id(suffix || id || "#[mulebot_count]")
	suffix = null

/mob/living/simple_animal/bot/mulebot/Destroy()
	if(!isnull(wires))
		QDEL_NULL(wires)
	unload(0)
	return ..()

/mob/living/simple_animal/bot/mulebot/death(gibbed)
	QDEL_NULL(wires)
	return ..()

/mob/living/simple_animal/bot/mulebot/proc/set_id(new_id)
	id = new_id
	if(paicard)
		bot_name = "\improper MULEbot ([new_id])"
	else
		name = "\improper MULEbot ([new_id])"

/mob/living/simple_animal/bot/mulebot/bot_reset()
	..()
	reached_target = 0

/mob/living/simple_animal/bot/mulebot/attackby(obj/item/I, mob/living/user, params)
	if(I.tool_behaviour == TOOL_SCREWDRIVER)
		..()
		if(open)
			on = FALSE
	else if(istype(I, /obj/item/stock_parts/cell) && open && !cell)
		if(!user.transferItemToLoc(I, src))
			return
		cell = I
		visible_message("[user] inserts a cell into [src].",
						span_notice("You insert the new cell into [src]."))
	else if(I.tool_behaviour == TOOL_CROWBAR && open && cell)
		cell.add_fingerprint(usr)
		cell.forceMove(loc)
		cell = null
		visible_message("[user] crowbars out the power cell from [src].",
						span_notice("You pry the powercell out of [src]."))
	else if(is_wire_tool(I) && open)
		return attack_hand(user)
	else if(load && ismob(load))  // chance to knock off rider
		if(prob(1 + I.force * 2))
			unload(0)
			user.visible_message(span_danger("[user] knocks [load] off [src] with \the [I]!"),
									span_danger("You knock [load] off [src] with \the [I]!"))
		else
			to_chat(user, span_warning("You hit [src] with \the [I] but to no effect!"))
			..()
	else
		..()
	update_appearance(UPDATE_ICON)
	return

/mob/living/simple_animal/bot/mulebot/emag_act(mob/user, obj/item/card/emag/emag_card)
	if(emagged < 1)
		emagged = TRUE
	if(!open)
		locked = !locked
		to_chat(user, span_notice("You [locked ? "lock" : "unlock"] [src]'s controls!"))
	flick("mulebot-emagged", src)
	playsound(src, "sparks", 100, 0)

/mob/living/simple_animal/bot/mulebot/update_icon_state()
	. = ..()
	if(open)
		icon_state="mulebot-hatch"
	else
		icon_state = "mulebot[wires.is_cut(WIRE_AVOIDANCE)]"

/mob/living/simple_animal/bot/mulebot/update_overlays()
	. = ..()
	if(load && !ismob(load))//buckling handles the mob offsets
		load.pixel_y = initial(load.pixel_y) + 9
		if(load.layer < layer)
			load.layer = layer + 0.01
		. += load

/mob/living/simple_animal/bot/mulebot/ex_act(severity)
	unload(0)
	switch(severity)
		if(1)
			qdel(src)
		if(2)
			for(var/i = 1; i < 3; i++)
				wires.cut_random()
		if(3)
			wires.cut_random()
	return

/mob/living/simple_animal/bot/mulebot/bullet_act(obj/projectile/Proj)
	. = ..()
	if(.)
		if(prob(50) && !isnull(load))
			unload(0)
		if(prob(25))
			visible_message(span_danger("Something shorts out inside [src]!"))
			wires.cut_random()

/mob/living/simple_animal/bot/mulebot/interact(mob/user)
	if(open && !isAI(user))
		wires.interact(user)
	else
		if(wires.is_cut(WIRE_RX) && isAI(user))
			return
		ui_interact(user)

/mob/living/simple_animal/bot/mulebot/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Mule", name)
		ui.open()

/mob/living/simple_animal/bot/mulebot/ui_data(mob/user)
	var/list/data = list()
	data["on"] = on
	data["locked"] = locked
	data["siliconUser"] = user.has_unlimited_silicon_privilege
	data["mode"] = mode ? mode_name[mode] : "Ready"
	data["modeStatus"] = ""
	switch(mode)
		if(BOT_IDLE, BOT_DELIVER, BOT_GO_HOME)
			data["modeStatus"] = "good"
		if(BOT_BLOCKED, BOT_NAV, BOT_WAIT_FOR_NAV)
			data["modeStatus"] = "average"
		if(BOT_NO_ROUTE)
			data["modeStatus"] = "bad"
		else
			data["modeStatus"] = "unknown"
	data["load"] = load ? load.name : null
	data["destination"] = destination ? destination : null
	data["home"] = home_destination
	data["destinations"] = GLOB.deliverybeacontags
	data["cell"] = cell ? TRUE : FALSE
	data["cellPercent"] = cell ? cell.percent() : null
	data["autoReturn"] = auto_return
	data["autoPickup"] = auto_pickup
	data["reportDelivery"] = report_delivery
	data["haspai"] = paicard ? TRUE : FALSE
	data["id"] = id
	return data

/mob/living/simple_animal/bot/mulebot/ui_act(action, params)
	if(..() || (locked && !usr.has_unlimited_silicon_privilege))
		return
	switch(action)
		if("lock")
			if(usr.has_unlimited_silicon_privilege)
				locked = !locked
				. = TRUE
		if("power")
			if(on)
				turn_off()
			else if(cell && !open)
				if(!turn_on())
					to_chat(usr, span_warning("You can't switch on [src]!"))
					return
			. = TRUE
		else
			bot_control(action, usr, params) // Kill this later.
			. = TRUE

/mob/living/simple_animal/bot/mulebot/bot_control(command, mob/user, list/params = list(), pda = FALSE)
	if(pda && wires.is_cut(WIRE_RX)) // MULE wireless is controlled by wires.
		return

	switch(command)
		if("stop")
			if(mode >= BOT_DELIVER)
				bot_reset()
		if("go")
			if(mode == BOT_IDLE)
				start()
		if("home")
			if(mode == BOT_IDLE || mode == BOT_DELIVER)
				start_home()
		if("destination")
			var/new_dest
			if(pda)
				new_dest = input(user, "Enter Destination:", name, destination) as null|anything in GLOB.deliverybeacontags
			else
				new_dest = params["value"]
			if(new_dest)
				set_destination(new_dest)
		if("setid")
			var/new_id
			if(pda)
				new_id = stripped_input(user, "Enter ID:", name, id, MAX_NAME_LEN)
			else
				new_id = params["value"]
			if(new_id)
				set_id(new_id)
		if("sethome")
			var/new_home
			if(pda)
				new_home = input(user, "Enter Home:", name, home_destination) as null|anything in GLOB.deliverybeacontags
			else
				new_home = params["value"]
			if(new_home)
				home_destination = new_home
		if("unload")
			if(load && mode != BOT_HUNT)
				if(loc == target)
					unload(loaddir)
				else
					unload(0)
		if("autoret")
			auto_return = !auto_return
		if("autopick")
			auto_pickup = !auto_pickup
		if("report")
			report_delivery = !report_delivery
		if("ejectpai")
			ejectpairemote(user)

// TODO: remove this; PDAs currently depend on it
/mob/living/simple_animal/bot/mulebot/get_controls(mob/user)
	var/ai = issilicon(user)
	var/dat
	dat += "<h3>Multiple Utility Load Effector Mk. V</h3>"
	dat += "<b>ID:</b> [id]<BR>"
	dat += "<b>Power:</b> [on ? "On" : "Off"]<BR>"
	dat += "<h3>Status</h3>"
	dat += "<div class='statusDisplay'>"
	switch(mode)
		if(BOT_IDLE)
			dat += span_good("Ready")
		if(BOT_DELIVER)
			dat += span_good("[mode_name[BOT_DELIVER]]")
		if(BOT_GO_HOME)
			dat += span_good("[mode_name[BOT_GO_HOME]]")
		if(BOT_BLOCKED)
			dat += span_average("[mode_name[BOT_BLOCKED]]")
		if(BOT_NAV,BOT_WAIT_FOR_NAV)
			dat += span_average("[mode_name[BOT_NAV]]")
		if(BOT_NO_ROUTE)
			dat += span_bad("[mode_name[BOT_NO_ROUTE]]")
	dat += "</div>"

	dat += "<b>Current Load:</b> [load ? load.name : "<i>none</i>"]<BR>"
	dat += "<b>Destination:</b> [!destination ? "<i>none</i>" : destination]<BR>"
	dat += "<b>Power level:</b> [cell ? cell.percent() : 0]%"

	if(locked && !ai && !IsAdminGhost(user))
		dat += "&nbsp;<br /><div class='notice'>Controls are locked</div><A href='byond://?src=[REF(src)];op=unlock'>Unlock Controls</A>"
	else
		dat += "&nbsp;<br /><div class='notice'>Controls are unlocked</div><A href='byond://?src=[REF(src)];op=lock'>Lock Controls</A><BR><BR>"

		dat += "<A href='byond://?src=[REF(src)];op=power'>Toggle Power</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=stop'>Stop</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=go'>Proceed</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=home'>Return to Home</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=destination'>Set Destination</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=setid'>Set Bot ID</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=sethome'>Set Home</A><BR>"
		dat += "<A href='byond://?src=[REF(src)];op=autoret'>Toggle Auto Return Home</A> ([auto_return ? "On":"Off"])<BR>"
		dat += "<A href='byond://?src=[REF(src)];op=autopick'>Toggle Auto Pickup Crate</A> ([auto_pickup ? "On":"Off"])<BR>"
		dat += "<A href='byond://?src=[REF(src)];op=report'>Toggle Delivery Reporting</A> ([report_delivery ? "On" : "Off"])<BR>"
		if(load)
			dat += "<A href='byond://?src=[REF(src)];op=unload'>Unload Now</A><BR>"
		dat += "<div class='notice'>The maintenance hatch is closed.</div>"

	return dat


// returns true if the bot has power
/mob/living/simple_animal/bot/mulebot/proc/has_power()
	return !open && cell && cell.charge > 0 && (!wires.is_cut(WIRE_POWER1) && !wires.is_cut(WIRE_POWER2))

/mob/living/simple_animal/bot/mulebot/proc/buzz(type)
	switch(type)
		if(SIGH)
			audible_message("[src] makes a sighing buzz.", span_italics("You hear an electronic buzzing sound."))
			playsound(loc, 'sound/machines/buzz-sigh.ogg', 50, 0)
		if(ANNOYED)
			audible_message("[src] makes an annoyed buzzing sound.", span_italics("You hear an electronic buzzing sound."))
			playsound(loc, 'sound/machines/buzz-two.ogg', 50, 0)
		if(DELIGHT)
			audible_message("[src] makes a delighted ping!", span_italics("You hear a ping."))
			playsound(loc, 'sound/machines/ping.ogg', 50, 0)


// mousedrop a crate to load the bot
// can load anything if hacked
/mob/living/simple_animal/bot/mulebot/MouseDrop_T(atom/movable/AM, mob/user)
	var/mob/living/L = user

	if(user.incapacitated() || (istype(L) && !(L.mobility_flags & MOBILITY_STAND)))
		return

	if(!istype(AM))
		return

	load(AM)

// called to load a crate
/mob/living/simple_animal/bot/mulebot/proc/load(atom/movable/AM)
	if(load ||  AM.anchored)
		return

	if(!isturf(AM.loc)) //To prevent the loading from stuff from someone's inventory or screen icons.
		return

	var/obj/structure/closet/crate/CRATE
	if(istype(AM, /obj/structure/closet/crate))
		CRATE = AM
	else
		if(!wires.is_cut(WIRE_LOADCHECK))
			buzz(SIGH)
			return	// if not hacked, only allow crates to be loaded

	if(CRATE) // if it's a crate, close before loading
		CRATE.close()

	if(isobj(AM))
		var/obj/O = AM
		if(O.has_buckled_mobs() || (locate(/mob) in AM)) //can't load non crates objects with mobs buckled to it or inside it.
			buzz(SIGH)
			return

	if(isliving(AM))
		if(!load_mob(AM))
			return
	else
		AM.forceMove(src)

	load = AM
	mode = BOT_IDLE
	update_appearance(UPDATE_ICON)

/mob/living/simple_animal/bot/mulebot/proc/load_mob(mob/living/M)
	can_buckle = TRUE
	if(buckle_mob(M))
		passenger = M
		load = M
		can_buckle = FALSE
		return TRUE
	return FALSE

/mob/living/simple_animal/bot/mulebot/post_buckle_mob(mob/living/M)
	M.pixel_y = initial(M.pixel_y) + 9
	if(M.layer < layer)
		M.layer = layer + 0.01

/mob/living/simple_animal/bot/mulebot/post_unbuckle_mob(mob/living/M)
		load = null
		M.layer = initial(M.layer)
		M.pixel_y = initial(M.pixel_y)

// called to unload the bot
// argument is optional direction to unload
// if zero, unload at bot's location
/mob/living/simple_animal/bot/mulebot/proc/unload(dirn)
	if(!load)
		return

	mode = BOT_IDLE

	cut_overlays()

	unbuckle_all_mobs()

	if(load)
		load.forceMove(loc)
		load.pixel_y = initial(load.pixel_y)
		load.layer = initial(load.layer)
		SET_PLANE_IMPLICIT(load, initial(load.plane))
		if(dirn)
			var/turf/T = loc
			var/turf/newT = get_step(T,dirn)
			if(load.CanPass(load,newT)) //Can't get off onto anything that wouldn't let you pass normally
				step(load, dirn)
		load = null



/mob/living/simple_animal/bot/mulebot/call_bot()
	..()
	if(path && path.len)
		target = ai_waypoint //Target is the end point of the path, the waypoint set by the AI.
		destination = get_area_name(target, TRUE)
		pathset = 1 //Indicates the AI's custom path is initialized.
		start()

/mob/living/simple_animal/bot/mulebot/handle_automated_action()
	if(!has_power())
		on = FALSE
		return
	if(on)
		var/speed = (wires.is_cut(WIRE_MOTOR1) ? 0 : 1) + (wires.is_cut(WIRE_MOTOR2) ? 0 : 2)
		if(!speed)//Devide by zero man bad
			return
		num_steps = round(10/speed) //10, 5, or 3 steps, depending on how many wires we have cut
		if(mode != BOT_IDLE)
			START_PROCESSING(SSfastprocess, src)

/mob/living/simple_animal/bot/mulebot/process()
	if(num_steps <= 0)
		return PROCESS_KILL
	num_steps--
	if(!on || client)
		return
	update_appearance(UPDATE_ICON)

	switch(mode)
		if(BOT_IDLE) // idle
			return

		if(BOT_DELIVER, BOT_GO_HOME, BOT_BLOCKED) // navigating to deliver,home, or blocked
			if(loc == target) // reached target
				at_target()
				return

			else if(path.len > 0 && target) // valid path
				var/turf/next = path[1]
				reached_target = 0
				if(next == loc)
					path -= next
					return
				if(isturf(next))
					if(bloodiness)
						var/obj/effect/decal/cleanable/blood/tracks/B = new(loc)
						B.add_blood_DNA(return_blood_DNA())
						var/newdir = get_dir(next, loc)
						if(newdir == dir)
							B.setDir(newdir)
						else
							newdir = newdir | dir
							if(newdir == 3)
								newdir = 1
							else if(newdir == 12)
								newdir = 4
							B.setDir(newdir)
						bloodiness--


					var/oldloc = loc
					var/moved = step_towards(src, next)	// attempt to move
					if(cell)
						cell.use(1)
					if(moved && oldloc!=loc)	// successful move
						blockcount = 0
						path -= loc

						if(destination == home_destination)
							mode = BOT_GO_HOME
						else
							mode = BOT_DELIVER

					else		// failed to move

						blockcount++
						mode = BOT_BLOCKED
						if(blockcount == 3)
							buzz(ANNOYED)

						if(blockcount > 10)	// attempt 10 times before recomputing
							// find new path excluding blocked turf
							buzz(SIGH)
							mode = BOT_WAIT_FOR_NAV
							blockcount = 0
							spawn(20)
								calc_path(avoid=next)
								if(path.len > 0)
									buzz(DELIGHT)
								mode = BOT_BLOCKED
							return
						return
				else
					buzz(ANNOYED)
					mode = BOT_NAV
					return
			else
				mode = BOT_NAV
				return

		if(BOT_NAV)	// calculate new path
			mode = BOT_WAIT_FOR_NAV
			spawn(0)
				calc_path()

				if(path.len > 0)
					blockcount = 0
					mode = BOT_BLOCKED
					buzz(DELIGHT)

				else
					buzz(SIGH)

					mode = BOT_NO_ROUTE

// calculates a path to the current destination
// given an optional turf to avoid
/mob/living/simple_animal/bot/mulebot/calc_path(turf/avoid = null)
	path = get_path_to(src, target, /turf/proc/Distance_cardinal, 0, 250, id=access_card, exclude=avoid)

// sets the current destination
// signals all beacons matching the delivery code
// beacons will return a signal giving their locations
/mob/living/simple_animal/bot/mulebot/proc/set_destination(new_dest)
	new_destination = new_dest
	get_nav()

// starts bot moving to current destination
/mob/living/simple_animal/bot/mulebot/proc/start()
	if(!on)
		return
	if(destination == home_destination)
		mode = BOT_GO_HOME
	else
		mode = BOT_DELIVER
	update_appearance(UPDATE_ICON)
	get_nav()

// starts bot moving to home
// sends a beacon query to find
/mob/living/simple_animal/bot/mulebot/proc/start_home()
	if(!on)
		return
	spawn(0)
		set_destination(home_destination)
		mode = BOT_BLOCKED
	update_appearance(UPDATE_ICON)

// called when bot reaches current target
/mob/living/simple_animal/bot/mulebot/proc/at_target()
	if(!reached_target)
		radio_channel = RADIO_CHANNEL_SUPPLY //Supply channel
		audible_message("[src] makes a chiming sound!", span_italics("You hear a chime."))
		playsound(loc, 'sound/machines/chime.ogg', 50, 0)
		reached_target = 1

		if(pathset) //The AI called us here, so notify it of our arrival.
			loaddir = dir //The MULE will attempt to load a crate in whatever direction the MULE is "facing".
			if(calling_ai)
				to_chat(calling_ai, span_notice("[icon2html(src, calling_ai)] [src] wirelessly plays a chiming sound!"))
				playsound(calling_ai, 'sound/machines/chime.ogg',40, 0)
				calling_ai = null
				radio_channel = RADIO_CHANNEL_AI_PRIVATE //Report on AI Private instead if the AI is controlling us.

		if(load)		// if loaded, unload at target
			if(report_delivery)
				speak("Destination <b>[destination]</b> reached. Unloading [load].",radio_channel)
			unload(loaddir)
		else
			// not loaded
			if(auto_pickup) // find a crate
				var/atom/movable/AM
				if(wires.is_cut(WIRE_LOADCHECK)) // if hacked, load first unanchored thing we find
					for(var/atom/movable/A in get_step(loc, loaddir))
						if(!A.anchored)
							AM = A
							break
				else			// otherwise, look for crates only
					AM = locate(/obj/structure/closet/crate) in get_step(loc,loaddir)
				if(AM && AM.Adjacent(src))
					load(AM)
					if(report_delivery)
						speak("Now loading [load] at <b>[get_area_name(src)]</b>.", radio_channel)
		// whatever happened, check to see if we return home

		if(auto_return && home_destination && destination != home_destination)
			// auto return set and not at home already
			start_home()
			mode = BOT_BLOCKED
		else
			bot_reset()	// otherwise go idle

	return

// called when bot bumps into anything
/mob/living/simple_animal/bot/mulebot/Bump(atom/obs)
	if(wires.is_cut(WIRE_AVOIDANCE))	// usually just bumps, but if avoidance disabled knock over mobs
		if(isliving(obs))
			var/mob/living/L = obs
			if(iscyborg(L))
				visible_message(span_danger("[src] bumps into [L]!"))
			else
				if(!paicard)
					log_combat(src, L, "knocked down")
					visible_message(span_danger("[src] knocks over [L]!"))
					L.Knockdown(8 SECONDS)
	return ..()

// called from mob/living/carbon/human/proc/on_entered()
// when mulebot is in the same loc
/mob/living/simple_animal/bot/mulebot/proc/RunOver(mob/living/carbon/human/H)
	log_combat(src, H, "run over", null, "(DAMTYPE: [uppertext(BRUTE)])")
	H.visible_message(span_danger("[src] drives over [H]!"), \
					span_userdanger("[src] drives over you!"))
	playsound(loc, 'sound/effects/splat.ogg', 50, 1)

	var/damage = rand(5,15)
	H.apply_damage(2*damage, BRUTE, BODY_ZONE_HEAD, run_armor_check(BODY_ZONE_HEAD, MELEE))
	H.apply_damage(2*damage, BRUTE, BODY_ZONE_CHEST, run_armor_check(BODY_ZONE_CHEST, MELEE))
	H.apply_damage(0.5*damage, BRUTE, BODY_ZONE_L_LEG, run_armor_check(BODY_ZONE_L_LEG, MELEE))
	H.apply_damage(0.5*damage, BRUTE, BODY_ZONE_R_LEG, run_armor_check(BODY_ZONE_R_LEG, MELEE))
	H.apply_damage(0.5*damage, BRUTE, BODY_ZONE_L_ARM, run_armor_check(BODY_ZONE_L_ARM, MELEE))
	H.apply_damage(0.5*damage, BRUTE, BODY_ZONE_R_ARM, run_armor_check(BODY_ZONE_R_ARM, MELEE))

	var/turf/T = get_turf(src)
	T.add_mob_blood(H)

	var/list/blood_dna = H.get_blood_dna_list()
	add_blood_DNA(blood_dna)
	bloodiness += 4

// player on mulebot attempted to move
/mob/living/simple_animal/bot/mulebot/relaymove(mob/user)
	if(user.incapacitated())
		return
	if(load == user)
		unload(0)


//Update navigation data. Called when commanded to deliver, return home, or a route update is needed...
/mob/living/simple_animal/bot/mulebot/proc/get_nav()
	if(!on || wires.is_cut(WIRE_BEACON))
		return

	for(var/obj/machinery/navbeacon/NB in GLOB.deliverybeacons)
		if(NB.location == new_destination)	// if the beacon location matches the set destination
									// the we will navigate there
			destination = new_destination
			target = NB.loc
			var/direction = NB.dir	// this will be the load/unload dir
			if(direction)
				loaddir = text2num(direction)
			else
				loaddir = 0
			update_appearance(UPDATE_ICON)
			if(destination) // No need to calculate a path if you do not have a destination set!
				calc_path()

/mob/living/simple_animal/bot/mulebot/emp_act(severity)
	. = ..()
	if(cell && !(. & EMP_PROTECT_CONTENTS))
		cell.emp_act(severity)
	if(load)
		load.emp_act(severity)


/mob/living/simple_animal/bot/mulebot/explode()
	visible_message(span_boldannounce("[src] blows apart!"))
	var/atom/Tsec = drop_location()

	new /obj/item/assembly/prox_sensor(Tsec)
	new /obj/item/stack/rods(Tsec)
	new /obj/item/stack/rods(Tsec)
	new /obj/item/stack/cable_coil/cut(Tsec)
	if(cell)
		cell.forceMove(Tsec)
		cell.update_appearance(UPDATE_ICON)
		cell = null

	do_sparks(3, TRUE, src)

	new /obj/effect/decal/cleanable/oil(loc)
	..()

/mob/living/simple_animal/bot/mulebot/remove_air(amount) //To prevent riders suffocating
	if(loc)
		return loc.remove_air(amount)
	else
		return null

/mob/living/simple_animal/bot/mulebot/remove_air_ratio(ratio)
	if(loc)
		return loc.remove_air_ratio(ratio)
	return null

/mob/living/simple_animal/bot/mulebot/resist()
	..()
	if(load)
		unload()

/mob/living/simple_animal/bot/mulebot/UnarmedAttack(atom/A)
	if(isturf(A) && isturf(loc) && loc.Adjacent(A) && load)
		unload(get_dir(loc, A))
	else
		..()

/mob/living/simple_animal/bot/mulebot/insertpai(mob/user, obj/item/computer_hardware/paicard/card)
	if(..())
		visible_message("[src] safeties are locked on.")

#undef SIGH
#undef ANNOYED
#undef DELIGHT

/obj/machinery/bot_core/mulebot
	req_access = list(ACCESS_CARGO)
