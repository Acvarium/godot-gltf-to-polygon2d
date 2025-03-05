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
	polygon2d.name = "Polygon2D"
	var vertices = []

	_process_node(scene_root, vertices)
	
	polygon2d.polygon = vertices

	var node2d = Node2D.new()
	node2d.name = source_file.get_file().split('.')[0]
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
			var edges = _extract_boundary_edges(mesh)
			var ordered_vertices = _order_boundary_vertices(edges)
			if ordered_vertices.size() > 0:

			
				var vert_array = []
				for i in range(mesh.get_surface_count()):
					var array = mesh.surface_get_arrays(i)
					if array.size() > Mesh.ARRAY_VERTEX:
						var verts = array[Mesh.ARRAY_VERTEX]
						for v in verts:
							vert_array.append(Vector2(v.x, -v.y))  # Проєкція на XY (вид з Z+)
							
				for i in range(ordered_vertices.size()):
					vertices.append(vert_array[int(ordered_vertices[i])])
	for child in node.get_children():
		_process_node(child, vertices, parent_path)


func _extract_boundary_edges(mesh: Mesh) -> Dictionary:
	var edges = {}
	if mesh is ArrayMesh:
		for i in range(mesh.get_surface_count()):
			var array = mesh.surface_get_arrays(i)
			if array.size() > Mesh.ARRAY_VERTEX:
				var verts = array[Mesh.ARRAY_VERTEX]
				var indices = array[Mesh.ARRAY_INDEX] if array.size() > Mesh.ARRAY_INDEX else []
				for j in range(0, indices.size(), 3):
					var edge_list = [[indices[j], indices[j+1]], [indices[j+1], indices[j+2]], [indices[j+2], indices[j]]]
					for edge in edge_list:
						var key = Vector2(min(edge[0], edge[1]), max(edge[0], edge[1]))
						print("key " + str(key))
						if key in edges:
							edges[key] += 1
							print("added key")
						else:
							edges[key] = 1
							print("new key")
	# Заміна dictionary comprehension на цикл
	var filtered_edges = {}
	for key in edges.keys():
		if edges[key] == 1:
			filtered_edges[key] = edges[key]
	return filtered_edges


func _order_boundary_vertices(edges: Dictionary) -> Array:
	var edge_keys = edges.keys()
	if edge_keys.size() == 0:
		return []

	var ordered = [edge_keys[0].x, edge_keys[0].y]
	print("edges " + str(edges))
	while true:
		var found = false
		for i in range(edge_keys.size()):
			if edge_keys[i].x == ordered[-1] and not edge_keys[i].y in ordered:
				ordered.append(edge_keys[i].y)
				found = true
				break
			elif edge_keys[i].y == ordered[-1] and not edge_keys[i].x in ordered:
				ordered.append(edge_keys[i].x)
				found = true
				break
		if not found:
			break
	for o in ordered:
		print("o " + str(o))
	return ordered
