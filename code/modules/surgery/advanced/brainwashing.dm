/obj/item/disk/surgery/brainwashing
	name = "Brainwashing Surgery Disk"
	desc = "The disk provides instructions on how to impress an order on a brain, making it the primary objective of the patient."
	surgeries = list(/datum/surgery/advanced/brainwashing)

/obj/item/healthanalyzer/advanced/brainwashing
	advanced_surgeries = list(/datum/surgery/advanced/brainwashing)

/datum/surgery/advanced/brainwashing
	name = "Brainwashing"
	desc = "A surgical procedure which directly implants a directive into the patient's brain, making it their absolute priority. It can be cleared using a mindshield implant."
	icon_state = "brainwashing"
	steps = list(
	/datum/surgery_step/incise,
	/datum/surgery_step/retract_skin,
	/datum/surgery_step/saw,
	/datum/surgery_step/clamp_bleeders,
	/datum/surgery_step/brainwash,
	/datum/surgery_step/close)

	target_mobtypes = list(/mob/living/carbon/human)
	possible_locs = list(BODY_ZONE_HEAD)
	requires_bodypart_type = FALSE

/datum/surgery/advanced/brainwashing/can_start(mob/user, mob/living/carbon/target)
	if(!..())
		return FALSE
	var/obj/item/organ/brain/B = target.getorganslot(ORGAN_SLOT_BRAIN)
	if(!B)
		return FALSE
	return TRUE

/datum/surgery_step/brainwash
	name = "brainwash"
	implements = list(TOOL_HEMOSTAT = 85, TOOL_WIRECUTTER = 50, /obj/item/stack/packageWrap = 35, /obj/item/stack/cable_coil = 15)
	difficulty = EXP_GENIUS
	time = 20 SECONDS
	preop_sound = 'sound/surgery/hemostat1.ogg'
	success_sound = 'sound/surgery/hemostat1.ogg'
	failure_sound = 'sound/surgery/organ2.ogg'

/datum/surgery_step/brainwash/preop(mob/user, mob/living/carbon/target, target_zone, obj/item/tool, datum/surgery/surgery)
	display_results(user, target, span_notice("You begin to brainwash [target]..."),
		"[user] begins to fix [target]'s brain.",
		"[user] begins to perform surgery on [target]'s brain.")

/datum/surgery_step/brainwash/success(mob/user, mob/living/carbon/target, target_zone, obj/item/tool, datum/surgery/surgery)
	if(!target.mind)
		to_chat(user, span_warning("[target] doesn't respond to the brainwashing, as if [target.p_they()] lacked a mind..."))
		return FALSE
	if(HAS_TRAIT(target, TRAIT_MINDSHIELD))
		to_chat(user, span_warning("You hear a faint buzzing from a device inside [target]'s brain, and the brainwashing is erased."))
		return FALSE
	display_results(user, target, span_notice("You succeed in brainwashing [target]."),
		"[user] successfully fixes [target]'s brain!",
		"[user] completes the surgery on [target]'s brain.")
	to_chat(target, span_userdanger("A new compulsion fills your mind... you feel forced to obey it!"))
	var/objective = stripped_input(user, "Choose the objective to imprint on your victim's brain.", "Brainwashing", null, MAX_MESSAGE_LEN)
	if(!objective)
		return FALSE
	brainwash(target, objective)
	message_admins("[ADMIN_LOOKUPFLW(user)] surgically brainwashed [ADMIN_LOOKUPFLW(target)] with the objective '[objective]'.")
	log_game("[key_name(user)] surgically brainwashed [key_name(target)] with the objective '[objective]'.")
	return TRUE

/datum/surgery_step/brainwash/failure(mob/user, mob/living/carbon/target, target_zone, obj/item/tool, datum/surgery/surgery)
	var/obj/item/organ/brain/B = target.getorganslot(ORGAN_SLOT_BRAIN)
	if(B)
		display_results(user, target, span_warning("You screw up, bruising the brain tissue!"),
			span_warning("[user] screws up, causing brain damage!"),
			"[user] completes the surgery on [target]'s brain.")
		B.applyOrganDamage(80)
	else
		user.visible_message("<span class='warning'>[user] suddenly notices that the brain [user.p_they()] [user.p_were()] working on is not there anymore.", span_warning("You suddenly notice that the brain you were working on is not there anymore."))
	return FALSE

/datum/surgery/advanced/brainwashing/mechanic
	steps = list(/datum/surgery_step/mechanic_open,
				/datum/surgery_step/open_hatch,
				/datum/surgery_step/mechanic_unwrench,
				/datum/surgery_step/prepare_electronics,
				/datum/surgery_step/brainwash,
				/datum/surgery_step/mechanic_wrench,
				/datum/surgery_step/mechanic_close)
	requires_bodypart_type = BODYPART_ROBOTIC
