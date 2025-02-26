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

	var objects_data = {}
	_process_node(scene_root, objects_data)

	# Збереження списку у файл
	var json_path = save_path + ".json"
	var file = FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(objects_data, "\t"))
		file.close()
		print("Mesh data saved to: ", json_path)
	else:
		push_error("Failed to save object data to JSON")

	# Зберігаємо імпортовану сцену
	var packed_scene = PackedScene.new()
	packed_scene.pack(scene_root)
	return ResourceSaver.save(packed_scene, save_path + "." + _get_save_extension())

func _process_node(node: Node, objects_data: Dictionary, parent_path: String = ""):
	var node_path = parent_path + "/" + node.name if parent_path != "" else node.name

	print("Processing node:", node.name, "Type:", node.get_class())  # Діагностика

	if node is MeshInstance3D or node.get_class() == "ImporterMeshInstance3D":
		print(" -> Found MeshInstance3D or ImporterMeshInstance3D:", node.name)

		var mesh = node.mesh
		if mesh is ImporterMesh:
			print(" --> ImporterMesh detected! Trying to convert to standard Mesh.")
			mesh = mesh.get_mesh()  # Конвертуємо в стандартний Mesh

		if mesh is ArrayMesh:  # Переконуємось, що тепер це ArrayMesh
			print(" --> Converted to ArrayMesh!")
			var vertices_data = []  # Масив для збереження вершин і UV

			for i in range(mesh.get_surface_count()):
				var array = mesh.surface_get_arrays(i)
				
				if array.size() > Mesh.ARRAY_VERTEX:
					var verts = array[Mesh.ARRAY_VERTEX]
					var uvs = array[Mesh.ARRAY_TEX_UV] if array.size() > Mesh.ARRAY_TEX_UV else []

					for v in range(verts.size()):
						var vertex_data = {
							"position": verts[v],
							"uv": uvs[v] if uvs.size() > v else Vector2()  # Додаємо UV або пусте значення
						}
						vertices_data.append(vertex_data)
			
			objects_data[node_path] = vertices_data
		else:
			print(" --> Mesh is NULL or incompatible!")
			objects_data[node_path] = "Mesh is NULL or incompatible"
	else:
		objects_data[node_path] = "Not a mesh"

	for child in node.get_children():
		_process_node(child, objects_data, node_path)
