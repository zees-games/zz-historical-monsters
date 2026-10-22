class_name ZhmHost
extends RefCounted

## What a monster needs from the game it is in, and the stand-in used when there is none.
##
## [b]The seam.[/b] A monster knows where players are and what it does to them, and nothing about
## what a player IS: health, armour, knock-back and being stunned are the game's. A host (Zombie
## Zone's horde, Playground's world) hands the spawner a node or object carrying these three
## methods, as meta on the spawner (`spawner.set_meta(&"zhm_host", host)`), and the brain calls
## them. All three run on the server only.
##
## [codeblock]
## func zhm_targets() -> Array                      # [{id: StringName, position: Vector3}, ...]
## func zhm_hit(npc: DotNpcInstance, victim: StringName, amount: float, kind: StringName, info: Dictionary) -> void
## func zhm_status(victim: StringName, status: StringName, seconds: float, info: Dictionary) -> void
## [/codeblock]
##
## [param kind] is one of `bite`, `claw`, `tail`, `charge`, `pounce`, `maul`, `slam`, `bleed`;
## `info` carries `impulse` (a Vector3 to knock the victim along, when the attack throws) and
## `source` (the monster's position). `status` is `stun`, `slow` or `bleed`; a host that has no
## such state may ignore it, and the monster's damage still lands.
##
## This default reads the spawner's own candidate list, records every call (so a suite and a
## demo can see what a monster did) and emits [signal hit] and [signal status] so a host can
## wire it up in one line each when it has no node of its own to write.

signal hit(npc_id: int, victim: StringName, amount: float, kind: StringName, info: Dictionary)
signal status(victim: StringName, status: StringName, seconds: float, info: Dictionary)

var director: Object = null
## Everything that happened, newest last, capped. For a suite and for the demo's log.
var history: Array[Dictionary] = []
var max_history: int = 256


func _init(p_director: Object = null) -> void:
	director = p_director


func zhm_targets() -> Array:
	var out: Array = []
	if director == null:
		return out
	# The spawner keeps what it was last handed in `_candidates`; there is no public accessor, and
	# asking for one is on the board (dot-npc). Reading it by name is the whole reason this default
	# is only a default: a real host passes its own list.
	var list: Variant = director.get(&"_candidates")
	if list is Array:
		for entry in list:
			if entry != null and "id" in entry and "position" in entry:
				out.append({"id": entry.id, "position": entry.position})
	return out


func zhm_hit(npc: Object, victim: StringName, amount: float, kind: StringName, info: Dictionary) -> void:
	var id: int = int(npc.get("instance_id")) if npc != null else 0
	_record({"op": "hit", "npc": id, "victim": victim, "amount": amount, "kind": kind})
	hit.emit(id, victim, amount, kind, info)


func zhm_status(victim: StringName, st: StringName, seconds: float, info: Dictionary) -> void:
	_record({"op": "status", "victim": victim, "status": st, "seconds": seconds})
	status.emit(victim, st, seconds, info)


func total_damage(victim: StringName = &"") -> float:
	var sum := 0.0
	for h in history:
		if h["op"] == "hit" and (victim == &"" or h["victim"] == victim):
			sum += float(h["amount"])
	return sum


func _record(entry: Dictionary) -> void:
	history.append(entry)
	if history.size() > max_history:
		history.pop_front()


func describe() -> Dictionary:
	return {"events": history.size(), "damage": total_damage()}
