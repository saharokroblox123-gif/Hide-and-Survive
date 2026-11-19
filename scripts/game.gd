extends Node3D

const ROUND_SECONDS := 300.0
const CLASS_DATA := {
	"person": {"title": "Человек", "hp": 100, "price": 0, "description": "Восстановление: +20 HP"},
	"medic": {"title": "Медик", "hp": 90, "price": 500, "description": "Лечит союзника на 25 HP"},
	"military": {"title": "Военный", "hp": 120, "price": 1250, "description": "Таран отталкивает монстра"},
	"hacker": {"title": "Взломщик", "hp": 100, "price": 4000, "description": "Останавливает монстра на 5 секунд"},
	"builder": {"title": "Строитель", "hp": 120, "price": 7500, "description": "Маяк стазиса создаёт поле замедления"},
	"mage": {"title": "Маг", "hp": 80, "price": 20000, "description": "Проклятие и полное лечение"}
}
const ITEM_DATA := {
	"glove": {"title": "Импульсная перчатка", "price": 250, "description": "Вызывает энергетическую волну, опрокидывающую монстра"},
	"block": {"title": "Блок", "price": 750, "description": "Защита от удара"},
	"trap": {"title": "Руна стазиса", "price": 1750, "description": "Магическое поле останавливает монстра на 10 секунд"},
	"pulse": {"title": "Импульсный разряд", "price": 4000, "description": "Останавливает монстра на 5 секунд"},
	"gravity_orb": {"title": "Гравитационная сфера", "price": 8500, "description": "Отталкивает монстра на большое расстояние"},
	"cloak": {"title": "Плащ-невидимка", "price": 14750, "description": "Невидимость на 10 секунд"},
	"elixir": {"title": "Эликсир бессмертия", "price": 20000, "description": "Защита на 10 секунд"},
	"revive": {"title": "Возрождение", "price": 30000, "description": "Возвращает союзника в раунд"}
}
const MONSTER_DATA := [
	{"id": "locust", "title": "Саранча", "difficulty": "3 ⭐", "color": Color(0.42, 0.72, 0.25), "speed": 4.2},
	{"id": "hat_cat", "title": "Кот в шляпе", "difficulty": "6,5 ⭐", "color": Color(0.68, 0.23, 0.28), "speed": 4.0},
	{"id": "cartoon_cat", "title": "Картун Кэт", "difficulty": "11 ⭐", "color": Color(0.08, 0.08, 0.11), "speed": 4.6},
	{"id": "twixxel", "title": "Twixxel сталкер", "difficulty": "16 ⭐", "color": Color(0.30, 0.08, 0.42), "speed": 4.8}
]

var rng := RandomNumberGenerator.new()
var camera: Camera3D
var world_root: Node3D
var ui_root: Control
var lobby_panel: PanelContainer
var shop_panel: PanelContainer
var hud_root: Control
var hud_label: Label
var timer_label: Label
var team_label: Label
var coins_label: Label
var class_button: Button
var shop_list: VBoxContainer
var ability_list: HBoxContainer
var joystick_hint: Label
var result_label: Label
var round_state := "lobby"
var round_time := ROUND_SECONDS
var coins := 0
var current_class := "person"
var owned_classes: Array[String] = ["person"]
var owned_items: Array[String] = []
var used_class := false
var used_magic_heal := false
var used_items: Dictionary = {}
var survivors: Array[Dictionary] = []
var monster: Dictionary = {}
var monster_node: CharacterBody3D
var selected_monster: Dictionary = {}
var monster_stun := 0.0
var monster_slow := 0.0
var monster_attack_cd := 0.0
var monster_special_cd := 8.0
var monster_dash_time := 0.0
var twixxel_stalk_cd := 38.0
var stalk_time := 0.0
var hunt_time := 0.0
var hunt_target: Dictionary = {}
var beacon: Dictionary = {}
var beacon_tick := 0.0
var trap_nodes: Array[Node3D] = []
var touch_index := -1
var joystick_value := Vector2.ZERO
var joystick_center := Vector2(112, 602)
var joystick_radius := 74.0
var lobby_actors: Array[Node3D] = []
var config := ConfigFile.new()

func _ready() -> void:
	rng.randomize()
	_load_save()
	_build_world()
	_build_ui()
	_show_lobby()
	set_process(true)
	set_physics_process(true)

func _process(delta: float) -> void:
	if camera != null and round_state == "playing" and not survivors.is_empty():
		var p: CharacterBody3D = survivors[0]["node"]
		if is_instance_valid(p):
			var target_pos := p.global_position + Vector3(0, 10.5, 13.0)
			camera.global_position = camera.global_position.lerp(target_pos, min(delta * 4.0, 1.0))
			camera.look_at(p.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	if round_state == "playing":
		round_time = maxf(0.0, round_time - delta)
		timer_label.text = "ВРЕМЯ  %02d:%02d" % [int(round_time) / 60, int(round_time) % 60]
		_update_hud()

func _physics_process(delta: float) -> void:
	if round_state != "playing":
		return
	_update_survivors(delta)
	_update_stasis_beacon(delta)
	_update_traps()
	_update_monster(delta)
	var alive_count := _alive_count()
	if alive_count == 0:
		_end_round(false)
	elif round_time <= 0.0:
		_end_round(true)

func _input(event: InputEvent) -> void:
	if round_state != "playing":
		return
	var view_size := get_viewport().get_visible_rect().size
	joystick_center = Vector2(112, view_size.y - 112)
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < view_size.x * 0.42 and event.position.y > view_size.y * 0.48:
			touch_index = event.index
			joystick_value = ((event.position - joystick_center) / joystick_radius).limit_length(1.0)
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			joystick_value = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == touch_index:
		joystick_value = ((event.position - joystick_center) / joystick_radius).limit_length(1.0)

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.018, 0.035, 0.09)
	sky_mat.sky_horizon_color = Color(0.13, 0.18, 0.25)
	sky_mat.ground_bottom_color = Color(0.025, 0.035, 0.045)
	sky_mat.ground_horizon_color = Color(0.10, 0.13, 0.15)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.55, 0.68)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world_root.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	world_root.add_child(sun)
	_add_box(world_root, Vector3(100, 1, 100), Vector3(0, -0.6, 0), Color(0.11, 0.17, 0.19), true)
	_add_box(world_root, Vector3(82, 4, 1), Vector3(0, 1.4, -42), Color(0.07, 0.11, 0.15), true)
	_add_box(world_root, Vector3(82, 4, 1), Vector3(0, 1.4, 42), Color(0.07, 0.11, 0.15), true)
	_add_box(world_root, Vector3(1, 4, 82), Vector3(-42, 1.4, 0), Color(0.07, 0.11, 0.15), true)
	_add_box(world_root, Vector3(1, 4, 82), Vector3(42, 1.4, 0), Color(0.07, 0.11, 0.15), true)
	for i in range(8):
		var x := -28.0 + float(i) * 8.0
		_add_box(world_root, Vector3(4, 2.8, 4), Vector3(x, 1.0, -20), Color(0.17, 0.23, 0.25), true)
		_add_box(world_root, Vector3(4, 2.8, 4), Vector3(x, 1.0, 20), Color(0.15, 0.21, 0.24), true)
	for p in [Vector3(-25, 0, -8), Vector3(24, 0, -10), Vector3(-23, 0, 12), Vector3(25, 0, 14), Vector3(0, 0, -29), Vector3(0, 0, 29)]:
		_add_shelter(p)
	for p in [Vector3(-34, 0, -30), Vector3(34, 0, -28), Vector3(-34, 0, 30), Vector3(34, 0, 29)]:
		_add_tree(p)
	_add_lobby_decor()
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.fov = 64
	camera.position = Vector3(0, 12, 21)
	world_root.add_child(camera)
	camera.current = true

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.material_override = _material(color, 0.88)
	parent.add_child(mesh_instance)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		parent.add_child(body)
	return mesh_instance

func _add_shelter(pos: Vector3) -> void:
	_add_box(world_root, Vector3(6, 0.35, 5), pos + Vector3(0, 0.05, 0), Color(0.22, 0.28, 0.31), true)
	_add_box(world_root, Vector3(6.4, 0.45, 0.5), pos + Vector3(0, 2.2, -2.4), Color(0.11, 0.18, 0.24), true)
	_add_box(world_root, Vector3(0.5, 2.3, 5), pos + Vector3(-2.8, 1.1, 0), Color(0.13, 0.2, 0.25), true)
	_add_box(world_root, Vector3(0.5, 2.3, 5), pos + Vector3(2.8, 1.1, 0), Color(0.13, 0.2, 0.25), true)
	var lamp := OmniLight3D.new()
	lamp.position = pos + Vector3(0, 2.5, 0)
	lamp.light_color = Color(0.35, 0.72, 1.0)
	lamp.light_energy = 1.2
	lamp.omni_range = 8
	world_root.add_child(lamp)

func _add_tree(pos: Vector3) -> void:
	_add_box(world_root, Vector3(0.8, 4.5, 0.8), pos + Vector3(0, 2.25, 0), Color(0.20, 0.12, 0.08), false)
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.4
	sphere.height = 4.4
	crown.mesh = sphere
	crown.position = pos + Vector3(0, 5.1, 0)
	crown.material_override = _material(Color(0.08, 0.25, 0.20))
	world_root.add_child(crown)

func _add_lobby_decor() -> void:
	_add_box(world_root, Vector3(13, 0.5, 8), Vector3(0, 0.1, 0), Color(0.12, 0.19, 0.27), false)
	_add_box(world_root, Vector3(11, 0.3, 0.25), Vector3(0, 2.6, -4), Color(0.12, 0.62, 0.92), false)
	var sign_label := Label3D.new()
	sign_label.text = "HIDE  AND  SURVIVE"
	sign_label.font_size = 72
	sign_label.modulate = Color(0.45, 0.85, 1.0)
	sign_label.position = Vector3(0, 4.0, -4.6)
	sign_label.pixel_size = 0.012
	world_root.add_child(sign_label)

func _material(color: Color, roughness: float = 0.72) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _actor_visual(actor: CharacterBody3D, color: Color, monster_id: String = "") -> void:
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42 if monster_id == "" else 0.58
	capsule.height = 1.35 if monster_id == "" else 2.1
	torso.mesh = capsule
	torso.position.y = 0.95 if monster_id == "" else 1.25
	torso.material_override = _material(color, 0.48)
	actor.add_child(torso)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.36 if monster_id == "" else 0.55
	sphere.height = 0.72 if monster_id == "" else 1.1
	head.mesh = sphere
	head.position.y = 1.95 if monster_id == "" else 2.55
	head.material_override = _material(color.lightened(0.14), 0.36)
	actor.add_child(head)
	for eye_x in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.055 if monster_id == "" else 0.095
		eye.mesh = eye_mesh
		eye.position = Vector3(eye_x, 2.0 if monster_id == "" else 2.60, -0.32 if monster_id == "" else -0.49)
		eye.material_override = _material(Color(0.015, 0.02, 0.025), 0.18)
		actor.add_child(eye)
	if monster_id == "hat_cat":
		var brim := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.75
		cylinder.bottom_radius = 0.82
		cylinder.height = 0.12
		brim.mesh = cylinder
		brim.position.y = 3.12
		brim.material_override = _material(Color(0.78, 0.12, 0.16), 0.4)
		actor.add_child(brim)
		var hat := MeshInstance3D.new()
		var hat_mesh := CylinderMesh.new()
		hat_mesh.top_radius = 0.48
		hat_mesh.bottom_radius = 0.58
		hat_mesh.height = 1.05
		hat.mesh = hat_mesh
		hat.position.y = 3.65
		hat.material_override = _material(Color(0.83, 0.12, 0.18), 0.35)
		actor.add_child(hat)
	elif monster_id == "locust":
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			var wing_mesh := BoxMesh.new()
			wing_mesh.size = Vector3(0.10, 0.95, 0.85)
			wing.mesh = wing_mesh
			wing.position = Vector3(side * 0.65, 1.55, 0.05)
			wing.rotation.z = side * -0.28
			wing.material_override = _material(Color(0.70, 0.86, 0.30, 0.8), 0.25)
			actor.add_child(wing)
	elif monster_id == "cartoon_cat":
		for side in [-1.0, 1.0]:
			var ear := MeshInstance3D.new()
			var ear_mesh := BoxMesh.new()
			ear_mesh.size = Vector3(0.25, 0.85, 0.24)
			ear.mesh = ear_mesh
			ear.position = Vector3(side * 0.38, 3.1, 0)
			ear.material_override = _material(Color(0.06, 0.06, 0.08))
			actor.add_child(ear)
	elif monster_id == "twixxel":
		var halo := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.60
		torus.outer_radius = 0.78
		halo.mesh = torus
		halo.position.y = 3.35
		halo.rotation.x = 0.25
		halo.material_override = _material(Color(0.70, 0.10, 0.90), 0.25)
		actor.add_child(halo)
	else:
		var badge := MeshInstance3D.new()
		var sphere2 := SphereMesh.new()
		sphere2.radius = 0.15
		badge.mesh = sphere2
		badge.position = Vector3(0, 0.95, -0.43)
		badge.material_override = _material(Color(0.25, 0.86, 1.0), 0.3)
		actor.add_child(badge)

func _create_actor(actor_name: String, color: Color, is_monster: bool = false, monster_id: String = "") -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = actor_name.replace(" ", "_")
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.52 if is_monster else 0.38
	capsule_shape.height = 2.7 if is_monster else 1.9
	collision.shape = capsule_shape
	collision.position.y = 1.0 if is_monster else 0.95
	actor.add_child(collision)
	_actor_visual(actor, color, monster_id)
	return actor

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui_root)
	lobby_panel = PanelContainer.new()
	lobby_panel.anchor_left = 0.5
	lobby_panel.anchor_right = 0.5
	lobby_panel.anchor_top = 0.5
	lobby_panel.anchor_bottom = 0.5
	lobby_panel.offset_left = -250
	lobby_panel.offset_right = 250
	lobby_panel.offset_top = -240
	lobby_panel.offset_bottom = 240
	lobby_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.075, 0.94)))
	ui_root.add_child(lobby_panel)
	var lobby_box := VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 13)
	lobby_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_panel.add_child(lobby_box)
	var title := Label.new()
	title.text = "HIDE AND SURVIVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.35, 0.83, 1.0))
	lobby_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "5 ЧЕЛОВЕК  •  1 МОНСТР  •  5 МИНУТ"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.76, 0.85, 0.94))
	lobby_box.add_child(subtitle)
	coins_label = Label.new()
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", 18)
	lobby_box.add_child(coins_label)
	var start_btn := _make_button("НАЧАТЬ РАУНД", Color(0.08, 0.48, 0.72))
	start_btn.pressed.connect(_start_round)
	lobby_box.add_child(start_btn)
	var shop_btn := _make_button("МАГАЗИН КЛАССОВ И ПРЕДМЕТОВ", Color(0.20, 0.30, 0.48))
	shop_btn.pressed.connect(_open_shop)
	lobby_box.add_child(shop_btn)
	class_button = _make_button("КЛАСС: ЧЕЛОВЕК", Color(0.20, 0.36, 0.42))
	class_button.pressed.connect(_cycle_class)
	lobby_box.add_child(class_button)
	var note := Label.new()
	note.text = "Выживи до конца таймера и помоги команде"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	lobby_box.add_child(note)

	shop_panel = PanelContainer.new()
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_right = 0.5
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_left = -300
	shop_panel.offset_right = 300
	shop_panel.offset_top = -285
	shop_panel.offset_bottom = 285
	shop_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.075, 0.98)))
	ui_root.add_child(shop_panel)
	var shop_box := VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 8)
	shop_panel.add_child(shop_box)
	var shop_title := Label.new()
	shop_title.text = "МАГАЗИН"
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 30)
	shop_title.add_theme_color_override("font_color", Color(0.35, 0.83, 1.0))
	shop_box.add_child(shop_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_box.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shop_list)
	var back_btn := _make_button("НАЗАД", Color(0.25, 0.31, 0.42))
	back_btn.pressed.connect(_close_shop)
	shop_box.add_child(back_btn)

	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(hud_root)
	var topbar := PanelContainer.new()
	topbar.position = Vector2(18, 14)
	topbar.size = Vector2(520, 76)
	topbar.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.06, 0.78)))
	hud_root.add_child(topbar)
	var topbox := VBoxContainer.new()
	topbox.add_theme_constant_override("separation", 1)
	topbar.add_child(topbox)
	timer_label = Label.new()
	timer_label.text = "ВРЕМЯ  05:00"
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.add_theme_color_override("font_color", Color(0.48, 0.90, 1.0))
	topbox.add_child(timer_label)
	hud_label = Label.new()
	hud_label.text = "HP 100"
	hud_label.add_theme_font_size_override("font_size", 16)
	topbox.add_child(hud_label)
	team_label = Label.new()
	team_label.text = "КОМАНДА 5/5"
	team_label.add_theme_font_size_override("font_size", 16)
	topbox.add_child(team_label)
	var right_panel := PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.offset_left = -236
	right_panel.offset_right = -14
	right_panel.offset_top = 14
	right_panel.offset_bottom = 220
	right_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.06, 0.82)))
	hud_root.add_child(right_panel)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 7)
	right_panel.add_child(right_box)
	var class_ability := _make_button("СПОСОБНОСТЬ КЛАССА", Color(0.10, 0.42, 0.60))
	class_ability.pressed.connect(_use_class_ability)
	right_box.add_child(class_ability)
	var magic_help := _make_button("МАГ: ЛЕЧЕНИЕ", Color(0.34, 0.25, 0.62))
	magic_help.pressed.connect(_use_magic_heal)
	right_box.add_child(magic_help)
	var item_label := Label.new()
	item_label.text = "ПРЕДМЕТЫ"
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.add_theme_color_override("font_color", Color(0.52, 0.83, 0.98))
	right_box.add_child(item_label)
	ability_list = HBoxContainer.new()
	ability_list.add_theme_constant_override("separation", 5)
	right_box.add_child(ability_list)
	joystick_hint = Label.new()
	joystick_hint.text = "◉"
	joystick_hint.position = Vector2(40, 526)
	joystick_hint.size = Vector2(145, 145)
	joystick_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joystick_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	joystick_hint.add_theme_font_size_override("font_size", 60)
	joystick_hint.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 0.55))
	hud_root.add_child(joystick_hint)
	hud_root.visible = false
	shop_panel.visible = false

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.20, 0.62, 0.82, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _make_button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 47)
	button.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _show_lobby() -> void:
	round_state = "lobby"
	lobby_panel.visible = true
	shop_panel.visible = false
	hud_root.visible = false
	coins_label.text = "МОНЕТЫ: %d 💰" % coins
	class_button.text = "КЛАСС: " + str(CLASS_DATA[current_class]["title"]).to_upper()
	_clear_lobby_actors()
	var colors := [Color(0.22, 0.64, 0.93), Color(0.88, 0.55, 0.26), Color(0.33, 0.78, 0.54), Color(0.74, 0.44, 0.85), Color(0.82, 0.83, 0.88)]
	var spots := [Vector3(-4, 0, 4), Vector3(-2, 0, 5), Vector3(0, 0, 5), Vector3(2, 0, 5), Vector3(4, 0, 4)]
	for i in range(5):
		var actor := _create_actor("LobbyMember" + str(i + 1), colors[i])
		actor.position = spots[i]
		world_root.add_child(actor)
		lobby_actors.append(actor)
	camera.global_position = Vector3(0, 9, 16)
	camera.look_at(Vector3(0, 1, 0), Vector3.UP)

func _clear_lobby_actors() -> void:
	for actor in lobby_actors:
		if is_instance_valid(actor):
			actor.queue_free()
	lobby_actors.clear()

func _open_shop() -> void:
	lobby_panel.visible = false
	shop_panel.visible = true
	for child in shop_list.get_children():
		child.queue_free()
	var header := Label.new()
	header.text = "МОНЕТЫ: %d 💰" % coins
	header.add_theme_font_size_override("font_size", 18)
	shop_list.add_child(header)
	var classes_header := Label.new()
	classes_header.text = "КЛАССЫ"
	classes_header.add_theme_font_size_override("font_size", 21)
	shop_list.add_child(classes_header)
	for id in CLASS_DATA.keys():
		var data: Dictionary = CLASS_DATA[id]
		var owned := owned_classes.has(id)
		var text_value := "%s  •  %d HP  •  %d 💰" % [data["title"], data["hp"], data["price"]]
		if owned:
			text_value += "  ✓"
		var b := _make_button(text_value, Color(0.13, 0.30, 0.43))
		b.pressed.connect(_buy_class.bind(id))
		shop_list.add_child(b)
		var desc := Label.new()
		desc.text = str(data["description"])
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		shop_list.add_child(desc)
	var items_header := Label.new()
	items_header.text = "ПРЕДМЕТЫ И СПОСОБНОСТИ"
	items_header.add_theme_font_size_override("font_size", 21)
	shop_list.add_child(items_header)
	for id in ITEM_DATA.keys():
		var data: Dictionary = ITEM_DATA[id]
		var owned := owned_items.has(id)
		var text_value := "%s  •  %d 💰" % [data["title"], data["price"]]
		if owned:
			text_value += "  ✓ КУПЛЕНО"
		var b := _make_button(text_value, Color(0.20, 0.25, 0.42))
		b.pressed.connect(_buy_item.bind(id))
		shop_list.add_child(b)
		var desc := Label.new()
		desc.text = str(data["description"]) + " • 1 раз за раунд"
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		shop_list.add_child(desc)

func _close_shop() -> void:
	shop_panel.visible = false
	lobby_panel.visible = true
	_show_lobby()

func _buy_class(id: String) -> void:
	if owned_classes.has(id):
		current_class = id
	else:
		var price: int = CLASS_DATA[id]["price"]
		if coins < price:
			_show_toast("Не хватает монет")
			return
		coins -= price
		owned_classes.append(id)
		current_class = id
	_save_game()
	_open_shop()

func _buy_item(id: String) -> void:
	if owned_items.has(id):
		_show_toast("Уже куплено")
		return
	var price: int = ITEM_DATA[id]["price"]
	if coins < price:
		_show_toast("Не хватает монет")
		return
	coins -= price
	owned_items.append(id)
	_save_game()
	_open_shop()

func _cycle_class() -> void:
	var index := owned_classes.find(current_class)
	current_class = owned_classes[(index + 1) % owned_classes.size()]
	class_button.text = "КЛАСС: " + str(CLASS_DATA[current_class]["title"]).to_upper()
	_save_game()

func _start_round() -> void:
	shop_panel.visible = false
	lobby_panel.visible = false
	hud_root.visible = true
	_clear_lobby_actors()
	_clear_round_actors()
	round_state = "playing"
	round_time = ROUND_SECONDS
	used_class = false
	used_magic_heal = false
	used_items.clear()
	monster_stun = 0.0
	monster_slow = 0.0
	monster_attack_cd = 1.0
	monster_special_cd = 7.0
	monster_dash_time = 0.0
	twixxel_stalk_cd = 38.0
	stalk_time = 0.0
	hunt_time = 0.0
	beacon.clear()
	trap_nodes.clear()
	var class_stats: Dictionary = CLASS_DATA[current_class]
	var player_color := Color(0.18, 0.64, 0.92)
	var player_node := _create_actor("Player", player_color)
	player_node.position = Vector3(-3, 0, 0)
	world_root.add_child(player_node)
	survivors.append({"node": player_node, "name": "Ты", "hp": class_stats["hp"], "max_hp": class_stats["hp"], "alive": true, "is_player": true, "stun": 0.0, "cloak": 0.0, "invuln": 0.0, "moving": false, "ai_time": 0.0, "ai_dir": Vector3.ZERO})
	var bot_names := ["Рэй", "Мика", "Нова", "Бруно"]
	var bot_colors := [Color(0.92, 0.57, 0.22), Color(0.36, 0.77, 0.49), Color(0.76, 0.44, 0.86), Color(0.86, 0.82, 0.65)]
	var positions := [Vector3(-10, 0, -8), Vector3(10, 0, -8), Vector3(-12, 0, 11), Vector3(11, 0, 12)]
	for i in range(4):
		var bot := _create_actor(bot_names[i], bot_colors[i])
		bot.position = positions[i]
		world_root.add_child(bot)
		survivors.append({"node": bot, "name": bot_names[i], "hp": 100, "max_hp": 100, "alive": true, "is_player": false, "stun": 0.0, "cloak": 0.0, "invuln": 0.0, "moving": false, "ai_time": rng.randf_range(0.0, 2.0), "ai_dir": Vector3.ZERO})
	selected_monster = MONSTER_DATA[rng.randi_range(0, MONSTER_DATA.size() - 1)]
	monster_node = _create_actor(str(selected_monster["title"]), selected_monster["color"], true, str(selected_monster["id"]))
	monster_node.position = Vector3(0, 0, -31)
	world_root.add_child(monster_node)
	monster = {"id": selected_monster["id"], "title": selected_monster["title"], "speed": selected_monster["speed"]}
	_build_ability_buttons()
	_update_hud()
	_show_toast("Монстр: " + str(selected_monster["title"]))

func _clear_round_actors() -> void:
	for d in survivors:
		if is_instance_valid(d.get("node")):
			d["node"].queue_free()
	survivors.clear()
	if is_instance_valid(monster_node):
		monster_node.queue_free()
	monster_node = null
	if beacon.has("node") and is_instance_valid(beacon["node"]):
		turret["node"].queue_free()
	turret.clear()
	for trap in trap_nodes:
		if is_instance_valid(trap):
			trap.queue_free()
	trap_nodes.clear()

func _update_survivors(delta: float) -> void:
	if survivors.is_empty():
		return
	var player_data: Dictionary = survivors[0]
	var player_node: CharacterBody3D = player_data["node"]
	var move_input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	move_input += joystick_value
	move_input = move_input.limit_length(1.0)
	for i in range(survivors.size()):
		var d: Dictionary = survivors[i]
		if not d["alive"]:
			continue
		var body: CharacterBody3D = d["node"]
		d["stun"] = maxf(0.0, float(d["stun"]) - delta)
		d["cloak"] = maxf(0.0, float(d["cloak"]) - delta)
		d["invuln"] = maxf(0.0, float(d["invuln"]) - delta)
		var direction := Vector3.ZERO
		if stalk_time > 0.0:
			if d["is_player"] and move_input.length() > 0.12:
				_damage_survivor(d, 999, true)
			direction = Vector3.ZERO
		elif float(d["stun"]) <= 0.0:
			if d["is_player"]:
				direction = Vector3(move_input.x, 0, move_input.y)
			else:
				d["ai_time"] = float(d["ai_time"]) - delta
				if float(d["ai_time"]) <= 0.0:
					d["ai_time"] = rng.randf_range(1.4, 3.2)
					var player_pos := player_node.global_position
					var away := body.global_position - monster_node.global_position if is_instance_valid(monster_node) else Vector3.ZERO
					if is_instance_valid(monster_node) and body.global_position.distance_to(monster_node.global_position) < 19.0:
						d["ai_dir"] = Vector3(away.x, 0, away.z).normalized()
					elif body.global_position.distance_to(player_pos) > 14.0:
						d["ai_dir"] = (player_pos - body.global_position).normalized()
					else:
						var angle := rng.randf_range(-PI, PI)
						d["ai_dir"] = Vector3(cos(angle), 0, sin(angle))
				direction = d["ai_dir"]
		d["moving"] = direction.length() > 0.12
		var speed := 6.2 if d["is_player"] else 4.4
		body.velocity.x = direction.x * speed
		body.velocity.z = direction.z * speed
		body.velocity.y = 0
		if direction.length() > 0.1:
			body.rotation.y = atan2(direction.x, direction.z)
		body.move_and_slide()
		if stalk_time > 0.0 and d["moving"] and body.global_position.distance_to(monster_node.global_position) < 35.0:
			_damage_survivor(d, 999, true)
		survivors[i] = d

func _nearest_target() -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for d in survivors:
		if not d["alive"] or float(d["cloak"]) > 0.0:
			continue
		var body: CharacterBody3D = d["node"]
		var dist := body.global_position.distance_to(monster_node.global_position)
		if dist < best_distance:
			best_distance = dist
			best = d
	return best

func _update_monster(delta: float) -> void:
	if not is_instance_valid(monster_node):
		return
	monster_stun = maxf(0.0, monster_stun - delta)
	monster_slow = maxf(0.0, monster_slow - delta)
	monster_attack_cd = maxf(0.0, monster_attack_cd - delta)
	monster_special_cd = maxf(0.0, monster_special_cd - delta)
	monster_dash_time = maxf(0.0, monster_dash_time - delta)
	twixxel_stalk_cd = maxf(0.0, twixxel_stalk_cd - delta)
	if hunt_time > 0.0 and (hunt_target.is_empty() or not hunt_target.get("alive", false)):
		hunt_time = 0.0
		hunt_target = {}
	if monster_stun > 0.0:
		monster_node.velocity = Vector3.ZERO
		monster_node.move_and_slide()
		return
	if stalk_time > 0.0:
		stalk_time = maxf(0.0, stalk_time - delta)
		monster_node.velocity = Vector3.ZERO
		monster_node.move_and_slide()
		return
	var target: Dictionary = {}
	if str(monster["id"]) == "twixxel" and hunt_time > 0.0 and not hunt_target.is_empty() and hunt_target.get("alive", false):
		target = hunt_target
		hunt_time = maxf(0.0, hunt_time - delta)
	elif str(monster["id"]) == "twixxel" and monster_special_cd <= 0.0:
		var alive: Array[Dictionary] = []
		for d in survivors:
			if d["alive"]:
				alive.append(d)
		if not alive.is_empty():
			hunt_target = alive[rng.randi_range(0, alive.size() - 1)]
			hunt_time = 10.0
			monster_special_cd = 24.0
			_show_toast("TWixxel выбрал цель! Беги!")
			target = hunt_target
	if target.is_empty():
		target = _nearest_target()
	if target.is_empty():
		return
	var target_body: CharacterBody3D = target["node"]
	var offset := target_body.global_position - monster_node.global_position
	var distance := offset.length()
	var dir := offset.normalized()
	if str(monster["id"]) == "twixxel" and monster_attack_cd <= 0.0 and distance < 2.2:
		_damage_survivor(target, 30)
		monster_attack_cd = 2.0
	if str(monster["id"]) == "twixxel" and twixxel_stalk_cd <= 0.0 and hunt_time <= 0.0 and stalk_time <= 0.0:
		stalk_time = 20.0
		twixxel_stalk_cd = 58.0
		monster_node.velocity = Vector3.ZERO
		monster_node.move_and_slide()
		_show_toast("СТАЛКЕРСТВО! НЕ ДВИГАЙСЯ!")
		return
	if str(monster["id"]) != "twixxel":
		var speed: float = monster["speed"]
		if monster_slow > 0.0:
			speed *= 0.52
		if monster_dash_time > 0.0:
			speed *= 1.5
		monster_node.velocity.x = dir.x * speed
		monster_node.velocity.z = dir.z * speed
		monster_node.velocity.y = 0
		if distance > 0.1:
			monster_node.rotation.y = atan2(dir.x, dir.z)
		monster_node.move_and_slide()
		var id := str(monster["id"])
		if id == "locust" and monster_attack_cd <= 0.0 and distance < 2.0:
			var dmg := 50 if rng.randf() < 0.22 else 25
			_damage_survivor(target, dmg)
			monster_attack_cd = 2.1
		elif id == "hat_cat":
			if monster_special_cd <= 0.0 and distance < 7.0:
				target["stun"] = 3.0
				monster_special_cd = 13.0
				_show_toast("СКРИМЕР! ТЫ ЗАМЕР НА 3 СЕКУНДЫ")
			elif monster_attack_cd <= 0.0 and distance < 2.1:
				_damage_survivor(target, 20)
				monster_attack_cd = 1.8
		elif id == "cartoon_cat":
			if monster_special_cd <= 0.0 and distance < 2.6:
				_damage_survivor(target, 75)
				monster_special_cd = 10.0
				monster_attack_cd = 2.0
			elif monster_attack_cd <= 0.0 and distance < 2.3:
				_damage_survivor(target, 25)
				monster_attack_cd = 2.3
			elif monster_special_cd <= 0.0 and distance > 4.5:
				monster_dash_time = 3.0
				monster_special_cd = 8.0
				_show_toast("КАРТУН КЭТ УСКОРЯЕТСЯ!")
	else:
		var speed: float = float(monster["speed"]) * (1.9 if hunt_time > 0.0 else 1.0)
		if monster_slow > 0.0:
			speed *= 0.55
		monster_node.velocity.x = dir.x * speed
		monster_node.velocity.z = dir.z * speed
		monster_node.velocity.y = 0
		if distance > 0.1:
			monster_node.rotation.y = atan2(dir.x, dir.z)
		monster_node.move_and_slide()
		if hunt_time > 0.0 and distance < 1.65:
			_damage_survivor(target, 999, true)
			hunt_time = 0.0

func _damage_survivor(d: Dictionary, amount: int, instant: bool = false) -> void:
	if not d["alive"] or float(d["invuln"]) > 0.0:
		return
	d["hp"] = 0 if instant else max(0, int(d["hp"]) - amount)
	if int(d["hp"]) <= 0:
		d["alive"] = false
		var body: CharacterBody3D = d["node"]
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		_show_toast(str(d["name"]) + " выбыл!")
	else:
		if d["is_player"]:
			_show_toast("Получено %d урона" % amount)

func _use_class_ability() -> void:
	if round_state != "playing" or used_class or survivors.is_empty():
		return
	var player_data: Dictionary = survivors[0]
	if not player_data["alive"]:
		_show_toast("Ты выбыл из раунда")
		return
	var nearest := _nearest_target()
	match current_class:
		"person":
			player_data["hp"] = mini(int(player_data["max_hp"]), int(player_data["hp"]) + 20)
		"medic":
			var target := _lowest_health_survivor()
			if target.is_empty():
				return
			target["hp"] = mini(int(target["max_hp"]), int(target["hp"]) + 25)
			_show_toast("Медик восстановил здоровье союзнику")
		"military":
			if is_instance_valid(monster_node):
				var player_node: CharacterBody3D = player_data["node"]
				var away: Vector3 = (monster_node.global_position - player_node.global_position).normalized()
				monster_node.global_position += away * 5.0
				_stun_monster(1.1)
		"hacker":
			_stun_monster(5.0)
			_show_toast("Разум монстра взломан на 5 секунд")
		"builder":
			_place_stasis_beacon()
		"mage":
			monster_slow = 10.0
			_show_toast("Проклятие замедлило монстра на 10 секунд")
	used_class = true
	_update_hud()

func _use_magic_heal() -> void:
	if round_state != "playing" or current_class != "mage" or used_magic_heal or survivors.is_empty():
		return
	var target := _lowest_health_survivor()
	if target.is_empty():
		return
	target["hp"] = int(target["max_hp"])
	used_magic_heal = true
	_show_toast("Маг полностью восстановил здоровье!")
	_update_hud()

func _lowest_health_survivor() -> Dictionary:
	var best: Dictionary = {}
	var ratio := 1.1
	for d in survivors:
		if not d["alive"]:
			continue
		var r := float(d["hp"]) / maxf(1.0, float(d["max_hp"]))
		if r < ratio:
			ratio = r
			best = d
	return best

func _place_stasis_beacon() -> void:
	if turret.has("node") and is_instance_valid(turret["node"]):
		return
	var player_node: CharacterBody3D = survivors[0]["node"]
	var t := Node3D.new()
	t.position = player_node.global_position + Vector3(2, 0, 0)
	var base := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.65
	cylinder.bottom_radius = 0.85
	cylinder.height = 0.5
	base.mesh = cylinder
	base.position.y = 0.25
	base.material_override = _material(Color(0.18, 0.52, 0.72), 0.35)
	t.add_child(base)
	var beacon_core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	beacon_core.mesh = core_mesh
	beacon_core.position.y = 1.05
	beacon_core.material_override = _material(Color(0.35, 0.9, 1.0), 0.2)
	t.add_child(beacon_core)
	var aura := MeshInstance3D.new()
	var aura_mesh := TorusMesh.new()
	aura_mesh.inner_radius = 0.78
	aura_mesh.outer_radius = 0.90
	aura.mesh = aura_mesh
	aura.position.y = 0.20
	aura.material_override = _material(Color(0.2, 0.75, 1.0), 0.2)
	t.add_child(aura)
	world_root.add_child(t)
	beacon = {"node": t, "hp": 3}
	_show_toast("Маяк стазиса активирован! Он выдержит 3 удара")

func _update_stasis_beacon(delta: float) -> void:
	if not turret.has("node") or not is_instance_valid(turret["node"]):
		return
	beacon_tick -= delta
	if turret_tick <= 0.0 and is_instance_valid(monster_node) and turret["node"].global_position.distance_to(monster_node.global_position) < 13.0:
		monster_slow = maxf(monster_slow, 1.7)
		turret_tick = 0.9
		if turret["node"].global_position.distance_to(monster_node.global_position) < 2.0:
			beacon["hp"] = int(turret["hp"]) - 1
			if int(turret["hp"]) <= 0:
				turret["node"].queue_free()
				turret.clear()
				_show_toast("Монстр разрушил маяк стазиса!")

func _stun_monster(seconds: float) -> void:
	monster_stun = maxf(monster_stun, seconds)
	if is_instance_valid(monster_node):
		monster_node.velocity = Vector3.ZERO

func _build_ability_buttons() -> void:
	for child in ability_list.get_children():
		child.queue_free()
	for id in owned_items:
		var data: Dictionary = ITEM_DATA[id]
		var b := _make_button(str(data["title"]), Color(0.19, 0.35, 0.55))
		b.custom_minimum_size = Vector2(118, 44)
		b.pressed.connect(_use_item.bind(id))
		ability_list.add_child(b)

func _use_item(id: String) -> void:
	if round_state != "playing" or used_items.get(id, false) or survivors.is_empty() or not survivors[0]["alive"]:
		return
	var player_data: Dictionary = survivors[0]
	match id:
		"glove":
			_stun_monster(2.5)
		"block":
			player_data["invuln"] = 3.0
		"trap":
			_place_trap()
		"pulse":
			_stun_monster(5.0)
		"gravity_orb":
			if is_instance_valid(monster_node):
				var player_node: CharacterBody3D = player_data["node"]
				var away: Vector3 = (monster_node.global_position - player_node.global_position).normalized()
				monster_node.global_position += away * 10.0
				_stun_monster(1.5)
		"cloak":
			player_data["cloak"] = 10.0
		"elixir":
			player_data["invuln"] = 10.0
		"revive":
			var dead: Dictionary = {}
			for d in survivors:
				if not d["alive"]:
					dead = d
					break
			if dead.is_empty():
				_show_toast("Некого возрождать")
				return
			dead["alive"] = true
			dead["hp"] = int(dead["max_hp"])
			dead["node"].visible = true
			dead["node"].global_position = player_data["node"].global_position + Vector3(2, 0, 2)
	used_items[id] = true
	_show_toast(str(ITEM_DATA[id]["title"]) + ": использовано")
	_update_hud()

func _place_trap() -> void:
	var area := Area3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.35
	shape.height = 2.0
	shape_node.shape = shape
	area.add_child(shape_node)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.9
	ring.mesh = torus
	ring.position.y = 0.12
	ring.material_override = _material(Color(0.95, 0.45, 0.16), 0.3)
	area.add_child(ring)
	area.position = survivors[0]["node"].global_position
	world_root.add_child(area)
	trap_nodes.append(area)
	area.body_entered.connect(_on_trap_body_entered.bind(area))

func _on_trap_body_entered(body: Node3D, area: Area3D) -> void:
	if body == monster_node:
		_stun_monster(10.0)
		_show_toast("Монстр попал в капкан на 10 секунд!")
		if is_instance_valid(area):
			trap_nodes.erase(area)
			area.queue_free()

func _update_traps() -> void:
	for trap in trap_nodes.duplicate():
		if is_instance_valid(trap) and is_instance_valid(monster_node):
			if trap.global_position.distance_to(monster_node.global_position) < 1.5:
				_stun_monster(10.0)
				trap_nodes.erase(trap)
				trap.queue_free()
				_show_toast("Монстр попал в капкан!")

func _alive_count() -> int:
	var count := 0
	for d in survivors:
		if d["alive"]:
			count += 1
	return count

func _update_hud() -> void:
	if survivors.is_empty() or round_state != "playing":
		return
	var p: Dictionary = survivors[0]
	hud_label.text = "HP %d/%d  •  %s" % [p["hp"], p["max_hp"], str(CLASS_DATA[current_class]["title"])]
	team_label.text = "КОМАНДА %d/5  •  МОНСТР: %s" % [_alive_count(), selected_monster.get("title", "—")]
	if p["hp"] <= 35:
		hud_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.30))
	else:
		hud_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))

func _end_round(success: bool) -> void:
	if round_state != "playing":
		return
	round_state = "result"
	var alive := _alive_count()
	var reward := 100 + alive * 100 if success else 50
	coins += reward
	_save_game()
	hud_root.visible = false
	lobby_panel.visible = true
	var box := lobby_panel.get_child(0) as VBoxContainer
	var title := box.get_child(0) as Label
	title.text = "ПОБЕДА!" if success else "КОМАНДА ПРОИГРАЛА"
	title.add_theme_color_override("font_color", Color(0.36, 0.9, 0.64) if success else Color(1.0, 0.40, 0.38))
	var subtitle := box.get_child(1) as Label
	subtitle.text = "Выжили: %d из 5  •  Награда: %d 💰" % [alive, reward]
	coins_label.text = "МОНЕТЫ: %d 💰" % coins
	var start_btn := box.get_child(3) as Button
	start_btn.text = "ИГРАТЬ ЕЩЁ РАЗ"
	var note := box.get_child(box.get_child_count() - 1) as Label
	note.text = "Новый монстр будет выбран случайно"
	_clear_round_actors()
	_show_lobby()

func _show_toast(message: String) -> void:
	if not is_instance_valid(ui_root):
		return
	var toast := Label.new()
	toast.text = message
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.82
	toast.anchor_bottom = 0.82
	toast.offset_left = -260
	toast.offset_right = 260
	toast.offset_top = -20
	toast.offset_bottom = 28
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
	ui_root.add_child(toast)
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)

func _save_game() -> void:
	config.set_value("progress", "coins", coins)
	config.set_value("progress", "current_class", current_class)
	config.set_value("progress", "owned_classes", owned_classes)
	config.set_value("progress", "owned_items", owned_items)
	config.save("user://save.cfg")

func _load_save() -> void:
	var err := config.load("user://save.cfg")
	if err != OK:
		return
	coins = int(config.get_value("progress", "coins", 0))
	current_class = str(config.get_value("progress", "current_class", "person"))
	owned_classes = config.get_value("progress", "owned_classes", ["person"])
	owned_items = config.get_value("progress", "owned_items", [])
	if not CLASS_DATA.has(current_class):
		current_class = "person"
	if not owned_classes.has("person"):
		owned_classes.append("person")

