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
	return [        {
			"name": "scale",
			"default_value": 50.0,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "1.0,500,0.1"
		}]  

func _get_option_visibility(preset_name: String, option_name: StringName, options: Dictionary) -> bool:
	return true  
	

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array[String], r_gen_files: Array[String]) -> int:
	var scale = options.get("scale", 1.0)
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
	var skeletons3D = {}
	_process_bone_nodes(scene_root, skeletons3D)
	for k in skeletons3D.keys():
		var skeleton2d = Skeleton2D.new()
		skeleton2d.name = "Skeleton2D"
		node2d.add_child(skeleton2d, true)
		skeleton2d.owner = node2d
		var bone_data = _convert_skeleton(skeletons3D[k], scale)
		print(bone_data)
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
		for bone in bones.values():
			bone.owner = node2d

#-------------------------------------------------------------------------------
#-------     POLYGON
#-------------------------------------------------------------------------------
	var meshes = {}
	var polygons = {}
	_process_node(scene_root, meshes, polygons, scale)
	for key in meshes.keys():
		var polygon2d = Polygon2D.new()
		polygon2d.name = key
		polygon2d.polygon = meshes[key]
		polygon2d.polygons = polygons[key]
		node2d.add_child(polygon2d, true)
		polygon2d.owner = node2d

	var packed_scene = PackedScene.new()
	packed_scene.pack(node2d)
	return ResourceSaver.save(packed_scene, save_path + ".scn")


func _process_bone_nodes(node: Node, skeletons3D: Dictionary, parent_path: String = ""):
	if node is Skeleton3D:
		skeletons3D[node.name] = node
	for child in node.get_children():
		_process_bone_nodes(child, skeletons3D, parent_path)


func _convert_skeleton(skeleton3d: Skeleton3D, scale: float) -> Dictionary:
	var bones = {}

	# Збираємо дані про всі кістки
	for i in range(skeleton3d.get_bone_count()):
		var bone_name = skeleton3d.get_bone_name(i)
		var transform = skeleton3d.get_bone_rest(i)
		var parent_idx = skeleton3d.get_bone_parent(i)

		bones[i] = {
			"name": bone_name,
			"position": Vector2(transform.origin.x, -transform.origin.y) * scale,
			"parent": parent_idx if parent_idx != -1 else null
		}

	return bones



func _process_node(node: Node, meshes: Dictionary, polygons : Dictionary, scale : float = 1.0, parent_path: String = ""):
	if node is MeshInstance3D or node.get_class() == "ImporterMeshInstance3D":
		var mesh = node.mesh
		if mesh is ImporterMesh:
			mesh = mesh.get_mesh()
			if mesh is ArrayMesh:
				var world_offset = node.transform.origin
				var vert_array = []
				var index_array = []
				for i in range(mesh.get_surface_count()):
					var array = mesh.surface_get_arrays(i)
					if array.size() > Mesh.ARRAY_VERTEX:
						var verts = array[Mesh.ARRAY_VERTEX]
						for v in verts:
							vert_array.append(Vector2(v.x + world_offset.x, -v.y - world_offset.y)  * scale)  

					if array.size() > Mesh.ARRAY_INDEX:
						var indices = array[Mesh.ARRAY_INDEX]
						var triangles = []
						for j in range(0, indices.size(), 3):  # Групуємо по 3, бо трикутники
							triangles.append([indices[j], indices[j+1], indices[j+2]])
						index_array.append_array(triangles)
					
				var mesh_name = node.name
				meshes[mesh_name] = vert_array
				polygons[mesh_name] = index_array

	for child in node.get_children():
		_process_node(child, meshes, polygons, scale, parent_path)
