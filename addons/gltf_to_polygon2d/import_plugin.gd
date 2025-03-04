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
	return []  # Немає додаткових опцій

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array[String], r_gen_files: Array[String]) -> int:
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

	var polygon2d = Polygon2D.new()
	
	var vertices = []

	_process_node(scene_root, vertices)
	
	polygon2d.polygon = vertices

	var node2d = Node2D.new()
	node2d.add_child(polygon2d, true)
	polygon2d.owner = node2d

	var packed_scene = PackedScene.new()
	packed_scene.pack(node2d)
	return ResourceSaver.save(packed_scene, save_path + ".scn")

func _process_node(node: Node, vertices: Array, parent_path: String = ""):
	if node is MeshInstance3D or node.get_class() == "ImporterMeshInstance3D":
		var mesh = node.mesh
		if mesh is ImporterMesh:
			mesh = mesh.get_mesh()
		
		if mesh is ArrayMesh:
			for i in range(mesh.get_surface_count()):
				var array = mesh.surface_get_arrays(i)
				if array.size() > Mesh.ARRAY_VERTEX:
					var verts = array[Mesh.ARRAY_VERTEX]
					for v in verts:
						vertices.append(Vector2(v.x, -v.y))  # Проєкція на XY (вид з Z+)

	for child in node.get_children():
		_process_node(child, vertices, parent_path)
