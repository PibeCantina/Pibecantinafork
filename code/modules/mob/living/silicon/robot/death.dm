
/mob/living/silicon/robot/gib_animation()
	new /obj/effect/temp_visual/gib_animation(loc, "gibbed-r")

/mob/living/silicon/robot/dust(just_ash, drop_items, force)
	if(mmi)
		qdel(mmi)
	..()

/mob/living/silicon/robot/spawn_dust()
	new /obj/effect/decal/remains/robot(loc)

/mob/living/silicon/robot/dust_animation()
	new /obj/effect/temp_visual/dust_animation(loc, "dust-r")

/mob/living/silicon/robot/death(gibbed)
	if(stat == DEAD)
		return

	if(deployed && shell)
		deployed = FALSE

	if(!gibbed)
		logevent("FATAL -- SYSTEM HALT")
		modularInterface.shutdown_computer()

	. = ..()

	locked = FALSE //unlock cover

	if(!QDELETED(builtInCamera) && builtInCamera.status)
		builtInCamera.toggle_cam(src,0)
	toggle_headlamp(TRUE) //So borg lights are disabled when killed.

	uneq_all() // particularly to ensure sight modes are cleared

	update_icons()

	unbuckle_all_mobs(TRUE)

	if(connected_ai)
		connected_ai.send_borg_death_warning(src)

	SSblackbox.ReportDeath(src)
