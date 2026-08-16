extends Registry
## EnemyKinds (Registry pattern, autoload) -- mirrors BlobKinds exactly, but
## for hostile creatures. A single Enemy script/scene handles every kind;
## kind_id just selects which stat multipliers and look get applied in
## Enemy._ready(), the same "one scene, data-driven variants" approach
## BlobKinds already uses.
##
## The `_kinds`/`_ordered_ids` storage, `_register()`, and `get_ordered_ids()`
## are inherited from Registry (see scripts/core/registry.gd).

class Kind:
	var id: String
	var display_name: String
	var health_mult: float
	var attack_mult: float
	var speed_mult: float
	var hue: float
	var body_scale: float
	## Which of Enemy.tscn's three pre-built rigs this kind shows -- "blob"
	## (amorphous, no limbs, the original spiky-sphere look), "quadruped"
	## (four-legged animal), or "humanoid" (bipedal, same rig family as
	## Blob). Enemy hides the other two and only animates the active one.
	var body_type: String

	func _init(p_id: String, p_name: String, p_health_mult: float, p_attack_mult: float,
			p_speed_mult: float, p_hue: float, p_body_scale: float, p_body_type: String = "blob") -> void:
		id = p_id
		display_name = p_name
		health_mult = p_health_mult
		attack_mult = p_attack_mult
		speed_mult = p_speed_mult
		hue = p_hue
		body_scale = p_body_scale
		body_type = p_body_type


func _ready() -> void:
	_default_id = "slime"
	_register(Kind.new("slime", "Slime", 1.0, 1.0, 1.0, 0.0, 1.0, "blob"))
	_register(Kind.new("wolf", "Wolf", 0.8, 1.15, 1.35, 0.08, 0.95, "quadruped"))
	_register(Kind.new("spider", "Spider", 0.65, 0.9, 1.5, 0.75, 0.8, "quadruped"))
	_register(Kind.new("scorpion", "Scorpion", 1.3, 1.3, 0.85, 0.1, 1.1, "quadruped"))
	_register(Kind.new("bandit", "Bandit", 1.1, 1.2, 1.05, 0.6, 1.05, "humanoid"))
	_register(Kind.new("yeti", "Yeti", 1.6, 1.4, 0.75, 0.55, 1.35, "humanoid"))
	_register(Kind.new("leech", "Leech", 0.55, 0.85, 1.2, 0.35, 0.75, "blob"))
	_register(Kind.new("panther", "Panther", 0.9, 1.25, 1.6, 0.85, 0.9, "quadruped"))
	_register(Kind.new("imp", "Imp", 0.7, 1.35, 1.3, 0.03, 0.8, "humanoid"))

## Thin covariant override: keeps callers' `var kind := EnemyKinds.get_kind(id)`
## statically typed as `Kind` (with EnemyKinds' own fields).
func get_kind(id: String) -> Kind:
	return super.get_kind(id)
