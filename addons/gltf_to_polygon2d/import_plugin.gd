@tool
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "gltf_to_polygon2d.importer"

func _get_visible_name() -> String:
	return "GLTF to Polygon2D"

func _get_recognized_extensions() -> PackedStringArray:
	return ["gltf", "glb"]

func _get_save_extension() -> String:
	return "scn"  # Зберігаємо як PackedScene

func _get_resource_type() -> String:
	return "PackedScene"

func _get_import_order() -> int:
	return 0

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Default"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [        
		{
			"name": "scale",
			"default_value": 50.0,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "1.0,500,0.1"
		},
		{
			"name": "surfaces_as_nodes",
			"default_value": false
		}
		]  

func _get_option_visibility(preset_name: String, option_name: StringName, options: Dictionary) -> bool:
	return true  
	

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array[String], r_gen_files: Array[String]) -> int:
	var scale = options.get("scale", 1.0)
	var surfaces_as_nodes :bool = options.get("surfaces_as_nodes", true)
	var importer := GLTFDocument.new()

	var state := GLTFState.new()
	var nodes = {}

	var err = importer.append_from_file(source_file, state)
	if err != OK:
		push_error("Failed to import GLTF: " + source_file)
		return err

	var scene_root: Node3D = importer.generate_scene(state, 30, false, false)
	if not scene_root:
		push_error("Failed to generate scene from GLTF: " + source_file)
		return ERR_CANT_CREATE
	
	var node2d = Node2D.new()
	node2d.name = source_file.get_file().split('.')[0]
#-------------------------------------------------------------------------------
#-------     SKELETON AND BONES
#-------------------------------------------------------------------------------
	var skeletons_3d = {}
	_process_bone_nodes(scene_root, skeletons_3d)
	var skeletons_2d_data = {}
	for skel_name in skeletons_3d.keys():
		
		var skeleton2d = Skeleton2D.new()
		skeleton2d.name = skel_name
		node2d.add_child(skeleton2d, true)
		skeleton2d.owner = node2d
		skeleton2d.visible = false
		skeletons_2d_data[skel_name] = {}
		skeletons_2d_data[skel_name]["skeleton"] = skeleton2d
		nodes[skel_name] = skeleton2d
		var bones_data = _convert_skeleton(skeletons_3d[skel_name], scale)
		var bones = {}
		for bone_id in bones_data.keys():
			var bone_info = bones_data[bone_id]
			var bone2d = Bone2D.new()
			bone2d.name = bone_info["name"]
			bones_data[bone_id]["rest_transform_3d"] = skeletons_3d[skel_name].get_bone_rest(bone_id)
			bones_data[bone_id]["global_rest_transform_3d"] = skeletons_3d[skel_name].get_bone_global_pose(bone_id)
			
			bones[bone_id] = bone2d
			bone2d.set_meta("bone_id", bone_id)
			bone2d.set_meta("skeleton_name", str(skel_name))
			nodes[bone2d.name] = bone2d
			
		for bone_id in bones_data.keys():
			var parent_id = bones_data[bone_id]["parent"]
			if parent_id == null:
				skeleton2d.add_child(bones[bone_id])  # Коренева кістка
			else:
				bones[parent_id].add_child(bones[bone_id])
		for bone : Bone2D in bones.values():
			bone.owner = node2d
		
		for bone_id in bones_data.keys():
			var bone = bones[bone_id]
			bone.global_position = bones_data[bone_id]["global_position"]
			bone.rest = bone.transform
			
		skeletons_2d_data[skel_name]["bones"] = bones
		skeletons_2d_data[skel_name]["bones_data"] = bones_data
#-------------------------------------------------------------------------------
#-------     POLYGON
#-------------------------------------------------------------------------------
	var meshes = {}
	_process_node(scene_root, meshes, scale)
	
	var sorted_keys = meshes.keys()
	sorted_keys.sort_custom(func(a, b):
		return meshes[a]["z_pos"] < meshes[b]["z_pos"]
	)

	for key in sorted_keys:
		var polygon2d := Polygon2D.new()
		polygon2d.name = key
		nodes[key] = polygon2d
		polygon2d.polygon = meshes[key]["vert_array"]
		polygon2d.polygons = meshes[key]["polygons_array"]
		if "texture_path" in meshes[key].keys():
			var texture: Texture2D = load(meshes[key]["texture_path"]) as Texture2D
			polygon2d.texture = texture
			var texture_width = texture.get_width()
			var texture_height = texture.get_height()
			if "uv_array" in meshes[key].keys():
				var scaled_uv = []
				for i in range(meshes[key]["uv_array"].size()):
					scaled_uv.append(meshes[key]["uv_array"][i] * Vector2(texture_width, texture_height))
				polygon2d.uv = scaled_uv
			
		node2d.add_child(polygon2d, true)
		polygon2d.owner = node2d
		if "skeleton_name" in meshes[key].keys() and meshes[key]["skeleton_name"] in skeletons_2d_data.keys():
			var skeleton_name = meshes[key]["skeleton_name"]
			var skeleton = skeletons_2d_data[skeleton_name]["skeleton"]
			var bones = skeletons_2d_data[skeleton_name]["bones"]
			var bone_count = bones.keys().size()
			polygon2d.set_skeleton(polygon2d.get_path_to(skeleton))
			for i in range(bones.keys().size()):
				if i in meshes[key]["weights_dict"].keys():
					var bone_weights = meshes[key]["weights_dict"][i]
					polygon2d.add_bone(polygon2d.get_path_to(bones[i]), bone_weights)
	var packed_scene = PackedScene.new()
	var animation_data = {}
	_process_animation(scene_root, animation_data)
	if animation_data and not animation_data.is_empty():
		for anim_player_name in animation_data.keys():
#----------------------ANIMATION PLAYER
			var animation_player := AnimationPlayer.new()
			animation_player.name = anim_player_name
			node2d.add_child(animation_player, true)
			animation_player.owner = node2d
#------------------------------------------------------------------------------
#----------------------ANIMATION LIBRARY
			var global_library := AnimationLibrary.new() 
			animation_player.add_animation_library("", global_library)
#------------------------------------------------------------------------------
#----------------------ANIMATIONS
			for anim_name in animation_data[anim_player_name].keys():
				var visibility_anim_data = {}
				var animation := Animation.new()
				animation.loop_mode = Animation.LOOP_LINEAR
				animation.length = animation_data[anim_player_name][anim_name]["length"]
				for track_data : Dictionary in animation_data[anim_player_name][anim_name]["tracks"]:
					var track_node_path : NodePath
					var split_node_name = str(track_data["path"]).split(":")
					var track_node : Node2D
					
					var coordinate_rotation = 0.0
					var rot_correction = 0.0
					var bone_rest_transform_3d = Transform3D()
					var bone_parent_global_rest_3d = Transform3D()
					var track_node_name = split_node_name[0]

					if split_node_name.size() > 1 and split_node_name[1] in nodes.keys():
						if not split_node_name[1] in visibility_anim_data.keys() and split_node_name[1].split('_')[-1] == "visible":
							var vis_node_name = split_node_name[1].replace("_visible", "")
							if vis_node_name in nodes.keys():
								var vis_node_path : NodePath = node2d.get_path_to(nodes[vis_node_name])
								visibility_anim_data[split_node_name[1]] = {}
								visibility_anim_data[split_node_name[1]]["node_path"] = vis_node_path
								
						track_node_path = node2d.get_path_to(nodes[split_node_name[1]])
						
						
						track_node = nodes[split_node_name[1]]
						if track_node is Bone2D:
							var bone_id : int = track_node.get_meta("bone_id")
							var skel_name : String = track_node.get_meta("skeleton_name")
							var bone_parent = skeletons_2d_data[skel_name]["bones_data"][bone_id]["parent"]
							bone_rest_transform_3d =  skeletons_2d_data[skel_name]["bones_data"][bone_id]["rest_transform_3d"]
							if bone_parent != null:
								bone_parent_global_rest_3d = skeletons_2d_data[skel_name]["bones_data"][bone_parent]["global_rest_transform_3d"]
					else:
						continue
					if track_data["type"] == Animation.TrackType.TYPE_POSITION_3D:
						var pos_track_id = animation.add_track(Animation.TYPE_VALUE)
						if track_node_path != null and not track_node_path.is_empty():
							animation.track_set_path(pos_track_id, NodePath(str(track_node_path) + ":position"))
							for i in range(track_data["keyframes"].size()):
								var pos2d = pos3d_to_2d(track_data["keyframes"][i], bone_parent_global_rest_3d, scale)
								animation.track_insert_key(pos_track_id, track_data["key_times"][i], pos2d)
					elif track_data["type"] == Animation.TrackType.TYPE_ROTATION_3D:
						var rot_track_id = animation.add_track(Animation.TYPE_VALUE)
						if track_node_path != null and not track_node_path.is_empty():
							animation.track_set_path(rot_track_id, NodePath(str(track_node_path) + ":rotation"))
						var prev_angle = 0.0
						for i in range(track_data["keyframes"].size()):
							var rot_2d = calc_rotation_key(track_data["keyframes"][i], bone_rest_transform_3d, bone_parent_global_rest_3d)
							var angle_shift = 0.0
							if i > 0:
								var angle_diff = rot_2d - prev_angle
								angle_shift = PI * 2 * (1.0 + int(abs(angle_diff) / (PI * 2)))
								if angle_diff > PI:
									rot_2d -= angle_shift
								elif angle_diff < -PI:
									rot_2d += angle_shift
							animation.track_insert_key(rot_track_id, track_data["key_times"][i], rot_2d)
							prev_angle = rot_2d
					elif track_data["type"] == Animation.TrackType.TYPE_SCALE_3D:
						
						if track_node_path != null and not track_node_path.is_empty():
							var scale_track_id = animation.add_track(Animation.TYPE_VALUE)
							animation.track_set_path(scale_track_id, NodePath(str(track_node_path) + ":scale"))
							var base_scale = Vector2(1.0, 1.0)
							
							for i in range(track_data["keyframes"].size()):
								var scale_value = track_data["keyframes"][i].x
								animation.track_insert_key(scale_track_id, track_data["key_times"][i], base_scale * scale_value)
								if split_node_name[1] in visibility_anim_data.keys():
									if not "keyframes" in visibility_anim_data[split_node_name[1]].keys():
										visibility_anim_data[split_node_name[1]]["keyframes"] = []
									if not "key_times" in visibility_anim_data[split_node_name[1]].keys():
										visibility_anim_data[split_node_name[1]]["key_times"] = []
									visibility_anim_data[split_node_name[1]]["keyframes"].append(scale_value > 0.9)
									visibility_anim_data[split_node_name[1]]["key_times"].append(track_data["key_times"][i])
				
				if visibility_anim_data and visibility_anim_data.keys().size() > 0:
					for vis_key in visibility_anim_data.keys():
						
						if visibility_anim_data[vis_key]["keyframes"].size() > 0:
							var viz_track_id = animation.add_track(Animation.TYPE_VALUE)
							animation.track_set_path(viz_track_id, NodePath(str(visibility_anim_data[vis_key]["node_path"]) + ":visible"))
							for i in range(visibility_anim_data[vis_key]["keyframes"].size()):
								animation.track_insert_key(viz_track_id, visibility_anim_data[vis_key]["key_times"][i], 
									visibility_anim_data[vis_key]["keyframes"][i])
				global_library.add_animation(anim_name, animation)
	packed_scene.pack(node2d)
	return ResourceSaver.save(packed_scene, save_path + ".scn")


func quaternion_to_string(q : Quaternion):
	var qe = q.get_euler()
	return str(Vector3i(rad_to_deg(qe.x), rad_to_deg(qe.y), rad_to_deg(qe.z)))
	

func calc_rotation_key(key_rot_3d : Quaternion, rest_transform_3d : Transform3D, parent_global_rest_3d : Transform3D) -> float:
	var key_vec = Vector3.UP
	key_vec = key_rot_3d * key_vec
	key_vec = parent_global_rest_3d.basis.get_rotation_quaternion() * key_vec
	
	var rest_vec = Vector3.UP
	rest_vec = rest_transform_3d.basis.get_rotation_quaternion() * rest_vec
	rest_vec = parent_global_rest_3d.basis.get_rotation_quaternion() * rest_vec
	
	var _angle = Vector2(key_vec.x, key_vec.y).angle_to(Vector2(rest_vec.x, rest_vec.y))
	return _angle


func _get_bone_initial_rotation(skeleton: Skeleton3D, bone_id: int) -> float:
	var global_xform = skeleton.get_bone_global_pose(bone_id)
	var basis = global_xform.basis
	var rotation = basis.get_euler().z 
	return -rotation


func _apply_parent_rotation(position: Vector2, parent_rotation: float) -> Vector2:
	var cos_theta = cos(parent_rotation)
	var sin_theta = sin(parent_rotation)
	
	return Vector2(
		position.x * cos_theta - position.y * sin_theta,
		position.x * sin_theta + position.y * cos_theta
	)


func pos3d_to_2d(pos_3d : Vector3, parent_global_rest_3d : Transform3D, scale : float = 1.0,) -> Vector2:
	var vec = parent_global_rest_3d.basis.get_rotation_quaternion() * pos_3d
	return Vector2(vec.x, -vec.y) * scale


func _process_bone_nodes(node: Node, skeletons_3d: Dictionary, parent_path: String = ""):
	if node is Skeleton3D:
		var key_name = node.name
		if node.get_parent():
			key_name = node.get_parent().name
		skeletons_3d[key_name] = node
	for child in node.get_children():
		_process_bone_nodes(child, skeletons_3d, parent_path)


func _process_animation(node: Node, animation_data: Dictionary, parent_path: String = ""):
	if node is AnimationPlayer:
		var animation_player : AnimationPlayer = node
		var anim_lib : AnimationLibrary = animation_player.get_animation_library("")
		var anim_player_name = node.name
		animation_data[anim_player_name] = {}
		for anim_name in anim_lib.get_animation_list():
			animation_data[anim_player_name][anim_name] = {}
			var anim : Animation = anim_lib.get_animation(anim_name)
			animation_data[anim_player_name][anim_name]["length"] = anim.length
			animation_data[anim_player_name][anim_name]["tracks"] = []
			for i in range(anim.get_track_count()):
				var current_track = {}
				current_track["type"] = anim.track_get_type(i)
				current_track["path"] = str(anim.track_get_path(i)).replace('.', '_')
				var keyframes = []
				var key_times = []
				for k in range(anim.track_get_key_count(i)):
					if current_track["type"] == 2:
						var q_rot : Quaternion = anim.track_get_key_value(i, k)
					keyframes.append(anim.track_get_key_value(i, k))
					key_times.append(anim.track_get_key_time(i, k))
				current_track["keyframes"] = keyframes
				current_track["key_times"] = key_times
				animation_data[anim_player_name][anim_name]["tracks"].append(current_track)
	for child in node.get_children():
		_process_animation(child, animation_data, parent_path)


func _convert_skeleton(skeleton3d: Skeleton3D, scale: float) -> Dictionary:
	var bonesData = {}
	for i in range(skeleton3d.get_bone_count()):
		var bone_name = skeleton3d.get_bone_name(i)
		var global_transform = skeleton3d.get_bone_global_pose(i)
		var local_transform = skeleton3d.get_bone_rest(i)
		var parent_idx = skeleton3d.get_bone_parent(i)
		
		var global_position: Vector3 = global_transform.origin
		var local_position: Vector3 = local_transform.origin
		
		bonesData[i] = {
			"name": bone_name,
			"position": Vector2(local_position.x, -local_position.y) * scale,
			"global_position": Vector2(global_position.x, -global_position.y) * scale,
			"parent": parent_idx if parent_idx != -1 else null
		}
	return bonesData


func _find_skeleton_for_mesh(node: Node, mesh_name: String) -> Skeleton3D:
	if node is MeshInstance3D or node.get_class() == "ImporterMeshInstance3D":
		if node.name == mesh_name:
			for child in node.get_children():
				if child is Skeleton3D:
					return child  # Повертаємо Skeleton3D, який керує цим мешем
	for child in node.get_children():
		var result = _find_skeleton_for_mesh(child, mesh_name)
		if result:
			return result
	return null


func _process_node(node: Node, meshes: Dictionary, scale: float = 1.0, parent_path: String = ""):
	if node is MeshInstance3D or node.get_class() == "ImporterMeshInstance3D":
		var mesh = node.mesh
		if mesh is ImporterMesh:
			mesh = mesh.get_mesh()
			if mesh is ArrayMesh:
				var z_pos = 0.0
				var texture_path = ""
				var material: Material = mesh.surface_get_material(0)
				if material is BaseMaterial3D:
					var albedo_texture = material.albedo_texture
					if albedo_texture:
						texture_path = albedo_texture.resource_path
						
				var world_offset = node.transform.origin
				var vert_array = []
				var index_array = []
				var weights_dict = {}  # Тепер словник, де ключ - індекс кістки, значення - PackedFloat32Array
				var uv_array = []
				
				var skeleton3d : = node.get_parent()
				if skeleton3d and skeleton3d is Skeleton3D:
					var fill_vert_count = 0
					for i in range(mesh.get_surface_count()):
						var array = mesh.surface_get_arrays(i)
						fill_vert_count = len(array[Mesh.ARRAY_VERTEX])
					for b in range(skeleton3d.get_bone_count()):
						weights_dict[b] = PackedFloat32Array()
						weights_dict[b].resize(fill_vert_count)
						weights_dict[b].fill(0.0)
				var weigth_rec_check = []
				for i in range(mesh.get_surface_count()):
					var array = mesh.surface_get_arrays(i)
					var verts = []
					if array.size() > Mesh.ARRAY_VERTEX:
						verts = array[Mesh.ARRAY_VERTEX]
						z_pos = verts[0].z
						for v in verts:
							vert_array.append(Vector2(v.x + world_offset.x, -v.y - world_offset.y) * scale)
					if array.size() > Mesh.ARRAY_TEX_UV:
						uv_array = array[Mesh.ARRAY_TEX_UV]
					if array.size() > Mesh.ARRAY_INDEX:
						var indices = array[Mesh.ARRAY_INDEX]
						var triangles = []
						for j in range(0, indices.size(), 3):  # Групуємо по 3, бо трикутники
							triangles.append([indices[j], indices[j + 1], indices[j + 2]])
						index_array.append_array(triangles)

					# Обробка ваг кісток
					if skeleton3d and array[Mesh.ARRAY_BONES] and array.size() > Mesh.ARRAY_BONES and array.size() > Mesh.ARRAY_WEIGHTS:
						var bone_indices = array[Mesh.ARRAY_BONES]
						var bone_weights_data = array[Mesh.ARRAY_WEIGHTS]
						var vertex_count = verts.size()
						for j in range(vertex_count):
							for k in range(4):  # До 4 кісток на вершину
								var bone_idx = bone_indices[j * 4 + k]
								if not (bone_idx * 1000000000 + j) in weigth_rec_check:
									var weight = bone_weights_data[j * 4 + k]
									weigth_rec_check.append(bone_idx * 1000000000 + j)
									weights_dict[bone_idx][j] = weight

				var mesh_name = node.name
				meshes[mesh_name] = {}
				meshes[mesh_name]["vert_array"] = vert_array
				meshes[mesh_name]["polygons_array"] = index_array
				meshes[mesh_name]["weights_dict"] = weights_dict  # Тепер словник {bone_idx: PackedFloat32Array}
				meshes[mesh_name]["z_pos"] = z_pos
				if texture_path != "":
					meshes[mesh_name]["texture_path"] = texture_path
				if node.get_parent() and node.get_parent() is Skeleton3D and node.get_parent().get_parent():
					meshes[mesh_name]["skeleton_name"] = node.get_parent().get_parent().name
				if len(uv_array) > 0:
					meshes[mesh_name]["uv_array"] = uv_array

	for child in node.get_children():
		_process_node(child, meshes, scale, parent_path)
