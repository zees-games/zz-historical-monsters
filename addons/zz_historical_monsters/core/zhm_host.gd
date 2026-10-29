class_name ZhmHost
extends RefCounted

## What a monster needs from its game, and the stand-in used when there is none. The seam is three server-only
## methods on a host set as `spawner.set_meta(&"zhm_host", host)`: `zhm_targets() -> Array`,
## `zhm_hit(npc, victim, amount, kind, info)`, `zhm_status(victim, status, seconds, info)`; the default records calls.

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
	# dot-npc's public accessor; a real host passes its own list, this is only the default.
	var list: Variant = director.call(&"candidates") if director.has_method(&"candidates") else null
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
