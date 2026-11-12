
class_name PulseGateRules
extends RefCounted

# ============================================================
# EXCITABLE MEDIUMS - BLOCKER AND GATE RULES
# Godot 4.3
#
# A reusable state manager for:
# - Single Blocker
# - Amount Blocker
# - Target Blocker
# - Amount Gate
# - Trigger Target
#
# All arrivals in a tick are evaluated together.
# State changes take effect on the following tick.
# ============================================================

enum Mechanic {
	SINGLE_BLOCKER,
	AMOUNT_BLOCKER,
	TARGET_BLOCKER,
	AMOUNT_GATE,
	TRIGGER_TARGET
}

enum Channel {
	PURPLE,
	BLUE,
	GREEN,
	RED
}

# Configurations and active states, indexed by node UID.
var configurations: Dictionary = {}
var states: Dictionary = {}

# Trigger channels unlocked by completed Trigger Targets.
var unlocked_channels: Dictionary = {}


# ============================================================
# REGISTER NODE
# ============================================================

func register_node(
	uid: String,
	mechanic: int,
	amount: int = 1,
	channel: int = Channel.PURPLE
) -> void:

	configurations[uid] = {
		"mechanic": mechanic,
		"amount": maxi(1, amount),
		"channel": channel
	}

	states[uid] = {
		"count": 0,
		"open": mechanic == Mechanic.AMOUNT_GATE,
		"complete": false
	}


# ============================================================
# RESET
# ============================================================

func reset() -> void:

	unlocked_channels.clear()

	for uid in configurations.keys():

		var config: Dictionary = configurations[uid]

		states[uid] = {
			"count": 0,
			"open": (
				int(config["mechanic"])
				== Mechanic.AMOUNT_GATE
			),
			"complete": false
		}


# ============================================================
# BEGIN TICK
#
# Apply any changes caused by previous ticks.
# Call before processing the new tick's arrivals.
# ============================================================

func begin_tick() -> void:

	for uid in configurations.keys():

		var config: Dictionary = configurations[uid]
		var state: Dictionary = states[uid]

		var mechanic: int = config["mechanic"]
		var amount: int = config["amount"]

		match mechanic:

			Mechanic.SINGLE_BLOCKER:
				state["open"] = false

			Mechanic.AMOUNT_BLOCKER:
				state["open"] = (
					int(state["count"]) >= amount
				)

			Mechanic.AMOUNT_GATE:
				state["open"] = (
					int(state["count"]) < amount
				)

			Mechanic.TARGET_BLOCKER:
				state["open"] = (
					unlocked_channels.has(
						int(config["channel"])
					)
				)

		states[uid] = state


# ============================================================
# PROCESS SIMULTANEOUS ARRIVALS
#
# Returns how many pulses may continue.
# The rest are absorbed.
#
# Call only once per node per tick, with the
# total number of pulses arriving that tick.
# ============================================================

func process_arrivals(
	uid: String,
	arrival_count: int
) -> Dictionary:

	if not configurations.has(uid):
		return {
			"passed": 0,
			"blocked": arrival_count,
			"completed": false
		}

	if arrival_count <= 0:
		return {
			"passed": 0,
			"blocked": 0,
			"completed": false
		}

	var config: Dictionary = configurations[uid]
	var state: Dictionary = states[uid]

	var mechanic: int = config["mechanic"]
	var amount: int = config["amount"]

	var passed: int = 0
	var blocked: int = 0
	var just_completed: bool = false

	match mechanic:

		# --------------------------------------------
		# PERMANENT BLOCKER
		# --------------------------------------------

		Mechanic.SINGLE_BLOCKER:

			blocked = arrival_count
			state["count"] = (
				int(state["count"]) + arrival_count
			)

		# --------------------------------------------
		# AMOUNT BLOCKER
		# First N signals blocked, then open.
		# --------------------------------------------

		Mechanic.AMOUNT_BLOCKER:

			if bool(state["open"]):
				passed = arrival_count
			else:
				blocked = arrival_count
				state["count"] = (
					int(state["count"]) + arrival_count
				)

		# --------------------------------------------
		# AMOUNT GATE
		# First N signals passed, then closed.
		# --------------------------------------------

		Mechanic.AMOUNT_GATE:

			if bool(state["open"]):
				passed = arrival_count
				state["count"] = (
					int(state["count"]) + arrival_count
				)
			else:
				blocked = arrival_count

		# --------------------------------------------
		# TARGET BLOCKER
		# Open only after matching trigger.
		# --------------------------------------------

		Mechanic.TARGET_BLOCKER:

			if bool(state["open"]):
				passed = arrival_count
			else:
				blocked = arrival_count

		# --------------------------------------------
		# TRIGGER TARGET
		# Absorbs pulses and unlocks its channel.
		# --------------------------------------------

		Mechanic.TRIGGER_TARGET:

			blocked = arrival_count

			if not bool(state["complete"]):

				state["count"] = (
					int(state["count"]) + arrival_count
				)

				if int(state["count"]) >= amount:

					state["complete"] = true
					just_completed = true

					unlocked_channels[
						int(config["channel"])
					] = true

	states[uid] = state

	return {
		"passed": passed,
		"blocked": blocked,
		"completed": just_completed
	}


# ============================================================
# STATE QUERIES
# ============================================================

func is_open(uid: String) -> bool:

	if not states.has(uid):
		return false

	return bool(states[uid]["open"])


func is_complete(uid: String) -> bool:

	if not states.has(uid):
		return false

	return bool(states[uid]["complete"])


func get_count(uid: String) -> int:

	if not states.has(uid):
		return 0

	return int(states[uid]["count"])


func get_remaining(uid: String) -> int:

	if not configurations.has(uid):
		return 0

	var amount: int = int(
		configurations[uid]["amount"]
	)

	return maxi(
		0,
		amount - get_count(uid)
	)


func is_channel_unlocked(channel: int) -> bool:
	return unlocked_channels.has(channel)


# ============================================================
# REMOVE NODE
# ============================================================

func unregister_node(uid: String) -> void:

	configurations.erase(uid)
	states.erase(uid)
