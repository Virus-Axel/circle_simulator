extends Control

var frames_since_frame_rate_update = 0
var circles_positions: PackedFloat32Array = [0.0, 1.0, 2.0, 3, 4, 5, 6, 7, 8, 9]
var zone_capacity: PackedInt32Array = []
var zone_indicies : PackedInt32Array = []

var ci_rid: RID
var shader
var test_x = 0.0

var rd : RenderingDevice
var circle_buffer : RID
var zone_buffer : RID
var time_buffer : RID

var ZONES : int = 2000
var show_zone_colors = false

var spawned_circles := 0
var canvases := []
var boundaries : Vector2i

var min_rad: float
var max_rad: float

var g : float
var total_circle = 0
var spawn_chunk = 0

var zone_shape: Vector2i
var boundary_uniform_set

func pos_to_zone(pos: Vector2) -> int:
	var y_index: int = int(zone_shape.y) * pos.y / boundaries.y
	var x_index: int = int(zone_shape.x) * pos.x / boundaries.x
	
	return zone_shape.x * int(y_index) + int(x_index)

func max_circle_per_box():
	return 50

func get_circle_pos(index: int) -> Vector2:
	return Vector2(circles_positions[index * 5], circles_positions[index * 5 + 1])

func set_circle_radius(index: int, radius: float):
	circles_positions[index * 5 + 4] = radius

func set_circle_speed(index: int, velocity: Vector2):
	circles_positions[index * 5 + 2] = velocity.x
	circles_positions[index * 5 + 3] = velocity.y

func set_circle_pos(index: int, pos: Vector2):
	circles_positions[index * 5] = pos.x
	circles_positions[index * 5 + 1] = pos.y

func create_zones(zone_amount):
	if zone_amount <= 0:
		zone_amount = boundaries.x / (6.0 * max_rad) * boundaries.y / (6.0 * max_rad)
	
	var cols = sqrt(float(zone_amount) / boundaries.x * boundaries.y)
	var rows = sqrt(float(zone_amount) / boundaries.y * boundaries.x)
	
	ZONES = (1 + rows) * (1 + cols)
	zone_amount = ZONES
	
	var length_per_zone = max_circle_per_box()
	zone_indicies.resize(length_per_zone * zone_amount)
	zone_indicies.fill(-1)
	zone_capacity.resize(zone_amount)
	zone_capacity.fill(0)
	
	zone_shape = Vector2i(int(rows), int(cols))

	return zone_shape


func create_circle_buffer(amount):
	circles_positions.resize(amount * 5)
	circles_positions.fill(NAN)
	

func setup_gpu_rendering():
	rd = RenderingServer.create_local_rendering_device()
	
	var shader_file := load("res://shaders/compute_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)

	var input_bytes := circles_positions.to_byte_array()
	circle_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)

	var circle_uniform := RDUniform.new()
	circle_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	circle_uniform.binding = 0
	circle_uniform.add_id(circle_buffer)
	
	input_bytes = zone_indicies.to_byte_array()
	zone_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	
	var zone_uniform := RDUniform.new()
	zone_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	zone_uniform.binding = 1
	zone_uniform.add_id(zone_buffer)
	
	var time_input_buffer := PackedByteArray()
	time_input_buffer.resize(4)
	time_input_buffer.encode_float(0, 0.0)
	time_buffer = rd.storage_buffer_create(time_input_buffer.size(), time_input_buffer)
	
	var time_uniform := RDUniform.new()
	time_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	time_uniform.binding = 2
	time_uniform.add_id(time_buffer)
	
	input_bytes = PackedInt32Array([boundaries.x, boundaries.y]).to_byte_array()
	var boundary_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	
	var boundary_uniform := RDUniform.new()
	boundary_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	boundary_uniform.binding = 0
	boundary_uniform.add_id(boundary_buffer)
	
	var g_bytes := PackedByteArray()
	g_bytes.resize(4)
	g_bytes.encode_float(0, g)
	var g_buffer = rd.storage_buffer_create(g_bytes.size(), g_bytes)
	
	var g_uniform := RDUniform.new()
	g_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	g_uniform.binding = 1
	g_uniform.add_id(g_buffer)
	
	var circle_uniform_set := rd.uniform_set_create([circle_uniform, zone_uniform, time_uniform], shader, 0)
	boundary_uniform_set = rd.uniform_set_create([boundary_uniform, g_uniform], shader, 1)

	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, circle_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, boundary_uniform_set, 1)
	
	rd.compute_list_dispatch(compute_list, zone_shape.x, zone_shape.y, 1)
	rd.compute_list_end()
	
	
	RenderingServer.free_rid(shader_spirv)
	
	RenderingServer.free_rid(time_buffer)
	RenderingServer.free_rid(circle_buffer)
	RenderingServer.free_rid(zone_buffer)
	RenderingServer.free_rid(g_buffer)
	RenderingServer.free_rid(boundary_buffer)
	
	RenderingServer.free_rid(boundary_uniform_set)
	RenderingServer.free_rid(circle_uniform_set)
	
	RenderingServer.free_rid(pipeline)
	

func set_frame_rate(frame_rate):
	$HBoxContainer/FrameRate.text = str(frame_rate)

func validate_settings(settings: Dictionary) -> bool:
	for expected in ["x", "y", "rmin", "rmax", "amount", "g"]:
		if settings.get(expected) == null:
			print_help_and_exit("./sim", "missing --" + expected)
			return false
	
	return true

func print_help_and_exit(app_name: String, message: String):
	print(message)
	print("Usage example: ", app_name, " --x=800 --y=600 --rmin=10.0 --rmax=15.0 --amount=5 --g=0.5")
	print("Optional arguments:\n\t--spawn-time\n\t--zones")
	get_tree().quit()

func spawn_circle():
	ci_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ci_rid, get_canvas_item())
	
	var rad = randf_range(min_rad, max_rad)
	
	RenderingServer.canvas_item_add_circle(ci_rid, Vector2(0.0, 0.0), rad, Color.WHITE)
	var circle_pos := Vector2(randf_range(0.0, boundaries.x), randf_range(0.0, boundaries.y))
	set_circle_pos(spawned_circles, circle_pos)
	set_circle_radius(spawned_circles, rad)
	set_circle_speed(spawned_circles, Vector2());
	
	var zone_ind = pos_to_zone(circle_pos)

	var zone_index = max_circle_per_box() * zone_ind
	
	for i in range(max_circle_per_box()):
		if zone_indicies[zone_index + i] == -1:
			zone_indicies[zone_index + i] = spawned_circles
			break
	
	canvases.append(ci_rid)
	spawned_circles += 1

func add_to_zone(zone_index, circle):
	zone_indicies[max_circle_per_box() * zone_index + zone_capacity[zone_index]] = circle
	zone_capacity[zone_index] += 1


func reassign_zones():
	zone_indicies.fill(-1)
	zone_capacity.fill(0)
	for i in range(spawned_circles):
		var ind = pos_to_zone(get_circle_pos(i))
		if ind >= ZONES:
			add_to_zone(ZONES - 1, i)
		else:
			add_to_zone(ind, i)


func set_zone_colors():
	for i in range(spawned_circles):
		var ind = pos_to_zone(get_circle_pos(i))
		var col = Color.WHITE
		col.r = fmod(123.0 * ind, 1.001)
		col.g = fmod(float(ind) * 234.0, 1.001)
		col.b = fmod(float(ind) * 289.0, 1.001)
		RenderingServer.canvas_item_set_modulate(canvases[i], col)


func _ready():
	var args := OS.get_cmdline_args()
	var settings = {}
	
	for argument in args:
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			settings[key_value[0].lstrip("--")] = key_value[1]
	
	if validate_settings(settings):
		var new_x = settings.get("x").to_int()
		var new_y = settings.get("y").to_int()
		boundaries = Vector2i(new_x, new_y)
		get_window().size = boundaries
		
		min_rad = settings.get("rmin").to_float()
		max_rad = settings.get("rmax").to_float()
		g = settings.get("g").to_float()
		
		total_circle = settings.get("amount").to_int()
		create_circle_buffer(settings.get("amount").to_int())

		if settings.has("zones"):
			create_zones(settings.get("zones").to_int())
		else:
			create_zones(0)
		
		var SPAWN_TIME = 3.0
		if settings.has("spawn-time"):
			SPAWN_TIME = settings.get("spawn-time").to_float()
		$spawn_timer.wait_time = SPAWN_TIME / settings.get("amount").to_int()

		if($spawn_timer.wait_time < 0.05):
			spawn_chunk = 0.05 / $spawn_timer.wait_time
		else:
			spawn_chunk = 1
		$spawn_timer.start()
			
		setup_gpu_rendering()
		set_zone_colors()


func update_circles(delta):
	for i in canvases.size():
		RenderingServer.canvas_item_set_transform(canvases[i], Transform2D().translated(get_circle_pos(i)))
	
	var input_bytes := circles_positions.to_byte_array()
	circle_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	
	var circle_uniform := RDUniform.new()
	circle_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	circle_uniform.binding = 0
	circle_uniform.add_id(circle_buffer)
	
	input_bytes = zone_indicies.to_byte_array()
	zone_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	
	var zone_uniform := RDUniform.new()
	zone_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	zone_uniform.binding = 1
	zone_uniform.add_id(zone_buffer)
	
	var time_input_buffer := PackedByteArray()
	time_input_buffer.resize(4)
	time_input_buffer.encode_float(0, delta)
	time_buffer = rd.storage_buffer_create(time_input_buffer.size(), time_input_buffer)
	
	var time_uniform := RDUniform.new()
	time_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	time_uniform.binding = 2
	time_uniform.add_id(time_buffer)
	
	var circle_uniform_set := rd.uniform_set_create([circle_uniform, zone_uniform, time_uniform], shader, 0)
	
	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, circle_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, boundary_uniform_set, 1)
	
	rd.compute_list_dispatch(compute_list, zone_shape.x + 1, zone_shape.y + 1, 1)
	rd.compute_list_end()
	
	RenderingServer.free_rid(time_buffer)
	RenderingServer.free_rid(circle_buffer)
	RenderingServer.free_rid(zone_buffer)
	
	RenderingServer.free_rid(circle_uniform_set)
	RenderingServer.free_rid(circle_uniform_set)
	
	RenderingServer.free_rid(pipeline)
	
	time_uniform.clear_ids()
	zone_uniform.clear_ids()
	circle_uniform.clear_ids()


func _process(delta):
	if(rd == null):
		return
		
	update_circles(delta)
	rd.submit()
	frames_since_frame_rate_update += 1

	
	if show_zone_colors:
		set_zone_colors()
	reassign_zones()
	rd.sync()
	
	var output_bytes := rd.buffer_get_data(circle_buffer)
	var output := output_bytes.to_float32_array()

	circles_positions = output
	pass


func _input(event):
	if event.is_action_pressed("ui_up"):
		if $FrameRateTimer.is_stopped():
			$HBoxContainer.visible = true
			frames_since_frame_rate_update = 0
			$FrameRateTimer.start()
		else:
			$HBoxContainer.visible = false
			$FrameRateTimer.stop()
	
	if event.is_action_pressed("ui_down"):
		show_zone_colors = !show_zone_colors

func _on_frame_rate_timer_timeout():
	set_frame_rate(frames_since_frame_rate_update)
	frames_since_frame_rate_update = 0
	

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		for canvas in canvases:
			if(canvas.is_valid()):
				RenderingServer.free_rid(canvas)
		canvases = []
		RenderingServer.free_rid(shader)
		rd.free()
		get_tree().quit()


func _on_spawn_timer_timeout():
	for i in range(spawn_chunk):
		spawn_circle()
		if total_circle == spawned_circles:
			$spawn_timer.stop()
			return
