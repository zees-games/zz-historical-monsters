class_name ZhmCatalogue
extends RefCounted

## The monsters as [DotNpcDef]s, built from [ZhmConfig]: [method add_to] a host catalogue or [method build] one.
## Definitions name body scene and brain by path relative to this file, so a rebased mounted pack finds them.

const Config := preload("zhm_config.gd")

const IDS := {&"trex": &"zhm_trex", &"tiger": &"zhm_tiger", &"bear": &"zhm_bear", &"allosaurus": &"zhm_allosaurus", &"raptor": &"zhm_raptor", &"thylacine": &"zhm_thylacine"}


static func dir() -> String:
	return (new().get_script() as Script).resource_path.get_base_dir().get_base_dir()


## The id a species is spawned by, `zhm_trex`.
static func id_of(species: StringName) -> StringName:
	return IDS.get(species, &"")


## The species an id belongs to, or empty.
static func species_of(npc_id: StringName) -> StringName:
	for k in IDS:
		if IDS[k] == npc_id:
			return k
	return &""


static func def_for(species: StringName, config: Config) -> DotNpcDef:
	var c := config.species(species)
	var base := dir()
	var def := DotNpcDef.make(id_of(species), base.path_join("runtime/zhm_body.tscn"))
	def.display_name = str(c.get("name", String(species)))
	def.category = &"monster"
	def.faction = &"hostile"
	def.brain_script_path = base.path_join("runtime/zhm_brain.gd")
	def.weight = {&"trex": DotNpcDef.Weight.BOSS, &"allosaurus": DotNpcDef.Weight.HEAVY, &"bear": DotNpcDef.Weight.HEAVY}.get(species, DotNpcDef.Weight.NORMAL)
	def.cost = int(c.get("cost", 4))
	def.max_health = float(c.get("health", 500.0))
	def.move_speed = float(c.get("run_speed", 6.0))
	def.sight_range = float(c.get("sight_range", 35.0))
	def.sight_half_angle_deg = float(c.get("sight_half_angle", 70.0))
	def.hearing_range = float(c.get("hearing_range", 25.0))
	def.eye_height = float(c.get("eye_height", 1.5))
	def.require_line_of_sight = true
	# The brain and the body read their numbers from here, so one catalogue entry is the whole of
	# a monster and an operator editing a JSON catalogue can reach all of it.
	def.meta = {"species": String(species), "cfg": c}
	return def


## All of them, in a catalogue of their own.
static func build(config: Config = null) -> DotNpcCatalogue:
	var cat := DotNpcCatalogue.new()
	add_to(cat, config)
	return cat


## Adds them to [param catalogue]. Returns how many were added; a definition that fails
## validation is logged and skipped, so one bad number loses one monster, not all.
static func add_to(catalogue: DotNpcCatalogue, config: Config = null) -> int:
	var cfg := config if config != null else Config.load_config()
	var added := 0
	for sp in Config.SPECIES:
		var res := catalogue.add(def_for(sp, cfg))
		if res.ok:
			added += 1
		else:
			DotLog.warn("zhm.catalogue", "a monster definition was refused", {"species": String(sp), "why": res.error.message})
	return added
