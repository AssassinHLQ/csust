extends Resource

var size : int
var vertices : PackedFloat32Array
var properties : Array[StringName]

func _init(path:='') -> void:
	if not path.is_empty(): parse(path)

func parse(path : String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	var line := file.get_line().split(' ')
	while not line[0] == 'end_header':
		line = file.get_line().split(' ')
		match line[0]:
			'format':   file.big_endian = line[1] == 'binary_big_endian'
			'element':  size = int(line[2])
			'property': properties.push_back(line[2])
	vertices = file.get_buffer(size*len(properties) * 4).to_float32_array()
	
func get_vertex(index : int) -> Dictionary:
	var start_index := len(properties) * index
	var vertex := {}
	for i in len(properties):
		vertex[properties[i]] = vertices[start_index + i]
	return vertex

static func load_gaussian_splats(point_cloud, stride : int, device, buffer, should_terminate_reference : Array, num_points_loaded : Array, callback : Callable):
	const STRUCT_SIZE = 60
	var num_properties = len(point_cloud.properties)
	var p = point_cloud.vertices
	var total = point_cloud.size
	var i = 0
	while i * stride < total:
		if should_terminate_reference[0]:
			break
		var tile_size = mini(total - i*stride, stride)
		var points = PackedFloat32Array()
		points.resize(STRUCT_SIZE * tile_size)
		for j in tile_size:
			var v = num_properties * (i*stride + j)
			var b = j * STRUCT_SIZE
			for k in 3:
				points[b+k] = p[v+k]
			points[b+3] = 0.0
			var scale = Basis.from_scale(Vector3(exp(p[v+55]), exp(p[v+56]), exp(p[v+57])))
			var rotation = Basis(Quaternion(p[v+59], p[v+60], p[v+61], p[v+58])).transposed()
			var cov_3d = (scale * rotation).transposed() * (scale * rotation)
			points[b+4] = cov_3d.x[0]
			points[b+5] = cov_3d.y[0]
			points[b+6] = cov_3d.z[0]
			points[b+7] = cov_3d.y[1]
			points[b+8] = cov_3d.z[1]
			points[b+9] = cov_3d.z[2]
			points[b+10] = 1.0 / (1.0 + exp(-p[v+54]))
			for k in 3:
				points[b+k+12] = p[v+k+6]
			for k in range(0, 45, 3):
				points[b+(k+0)+15] = p[v+(k/3+0)+9]
				points[b+(k+1)+15] = p[v+(k/3+15)+9]
				points[b+(k+2)+15] = p[v+(k/3+30)+9]
		if should_terminate_reference[0]:
			break
		# 4.7: 主 RenderingDevice 只允许在 render thread 更新 buffer；
		# 这里同步调用（由 init_gpu 在 render thread 触发）。
		device.buffer_update(buffer, i*STRUCT_SIZE*stride * 4, STRUCT_SIZE*tile_size * 4, points.to_byte_array())
		num_points_loaded[0] += tile_size
		i += 1
	callback.call()
