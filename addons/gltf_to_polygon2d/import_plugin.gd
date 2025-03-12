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
	var surfaces_as_nodes :bool = options.get("surfaces_as_nodes", false)
	var importer := GLTFDocument.new()
	var state := GLTFState.new()

	var err = importer.append_from_file(source_file, state)
	if err != OK:
		push_error("Failed to import GLTF: " + source_file)
		return err

	var scene_root: Node3D = importer.generate_scene(state)
	if not scene_root:
		push_error("Failed to generate scene from GLTF: " + source_file)
		return ERR_CANT_CREATE
	
	var node2d = Node2D.new()
	node2d.name = source_file.get_file().split('.')[0]
#-------------------------------------------------------------------------------
#-------     SKELETON AND BONES
#-------------------------------------------------------------------------------
	var skeletonsData = {}
	_process_bone_nodes(scene_root, skeletonsData)
	var skeletons_data = {}
	
	for skel_name in skeletonsData.keys():
		var skeleton2d = Skeleton2D.new()
		skeleton2d.name = skel_name
		node2d.add_child(skeleton2d, true)
		skeleton2d.owner = node2d
		skeletons_data[skel_name] = {}
		skeletons_data[skel_name]["skeleton"] = skeleton2d
		
		var bone_data = _convert_skeleton(skeletonsData[skel_name], scale)
		var bones = {}
		for bone_id in bone_data.keys():
			var bone_info = bone_data[bone_id]
			var bone2d = Bone2D.new()
			bone2d.name = bone_info["name"]
			bone2d.position = bone_info["position"]
			bones[bone_id] = bone2d
		
		for bone_id in bone_data.keys():
			var parent_id = bone_data[bone_id]["parent"]
			if parent_id == null:
				skeleton2d.add_child(bones[bone_id])  # Коренева кістка
			else:
				bones[parent_id].add_child(bones[bone_id])
		for bone : Bone2D in bones.values():
			bone.owner = node2d
			bone.rest = bone.transform
		
		skeletons_data[skel_name]["bones"] = bones
		
#-------------------------------------------------------------------------------
#-------     POLYGON
#-------------------------------------------------------------------------------
	var meshes = {}
	_process_node(scene_root, meshes, scale)
	for key in meshes.keys():
		var polygon2d := Polygon2D.new()
		polygon2d.name = key
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
		if "skeleton_name" in meshes[key].keys() and meshes[key]["skeleton_name"] in skeletons_data.keys():
			var skeleton_name = meshes[key]["skeleton_name"]
			var skeleton = skeletons_data[skeleton_name]["skeleton"]
			var bones = skeletons_data[skeleton_name]["bones"]
			var bone_count = bones.keys().size()
			polygon2d.set_skeleton(polygon2d.get_path_to(skeleton))
			for i in range(bones.keys().size()):
				if i in meshes[key]["weights_dict"].keys():
					var bone_weights = meshes[key]["weights_dict"][i]
					polygon2d.add_bone(polygon2d.get_path_to(bones[i]), bone_weights)
	var packed_scene = PackedScene.new()
	packed_scene.pack(node2d)
	var animation_data = {}
	_process_animation(scene_root, animation_data)
	
	return ResourceSaver.save(packed_scene, save_path + ".scn")


func _process_bone_nodes(node: Node, skeletonsData: Dictionary, parent_path: String = ""):
	if node is Skeleton3D:
		var key_name = node.name
		if node.get_parent():
			key_name = node.get_parent().name
		skeletonsData[key_name] = node
	for child in node.get_children():
		_process_bone_nodes(child, skeletonsData, parent_path)


func _process_animation(node: Node, animation_data: Dictionary, parent_path: String = ""):
	if node is AnimationPlayer:
		var animation_player : AnimationPlayer = node
		var anim_lib : AnimationLibrary = animation_player.get_animation_library("")
		
		for anim_name in anim_lib.get_animation_list():
			var anim : Animation = anim_lib.get_animation(anim_name)
			for i in range(anim.get_track_count()):
				
				print(anim.track_get_type(i))
				print(anim.track_get_path(i))
				for k in range(anim.track_get_key_count(i)):
					print(anim.track_get_key_value(i, k))
		
	for child in node.get_children():
		_process_animation(child, animation_data, parent_path)



func _convert_skeleton(skeleton3d: Skeleton3D, scale: float) -> Dictionary:
	var bonesData = {}
	for i in range(skeleton3d.get_bone_count()):
		var bone_name = skeleton3d.get_bone_name(i)
		var transform = skeleton3d.get_bone_global_rest(i)
		var parent_idx = skeleton3d.get_bone_parent(i)
		
		var local_position: Vector3
		if parent_idx != -1:
			var parent_global_position = skeleton3d.get_bone_global_rest(parent_idx).origin
			local_position = transform.origin - parent_global_position
		else:
			local_position = transform.origin
		bonesData[i] = {
			"name": bone_name,
			"position": Vector2(local_position.x, -local_position.y) * scale,
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
				if texture_path != "":
					meshes[mesh_name]["texture_path"] = texture_path
				if node.get_parent() and node.get_parent() is Skeleton3D and node.get_parent().get_parent():
					meshes[mesh_name]["skeleton_name"] = node.get_parent().get_parent().name
				if len(uv_array) > 0:
					meshes[mesh_name]["uv_array"] = uv_array

	for child in node.get_children():
		_process_node(child, meshes, scale, parent_path)
