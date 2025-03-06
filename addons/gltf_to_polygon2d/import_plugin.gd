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
