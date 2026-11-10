extends SceneTree
## 最小验证：.tscn 里那 12 个数怎么映射成 basis。
##
## ⚠️ GDScript 的 `Transform3D` **没有 12 参数构造**（那是 .tscn 文件格式），
##    只能用 `Transform3D(Basis, Vector3)`。这里用 `Basis()` 逐列构造来对照。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# `.tscn` 里写 Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)
	# Godot 的 Basis(xx,xy,xz, yx,yy,yz, zx,zy,zz) 是**按列给 3 个基向量**
	# → Transform3D 的 9 个数等价于 Basis(x列, y列, z列)
	var cases := {
		"C: 0,0,1, 0,1,0, -1,0,0": Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)),
		"D: -1,0,0, 0,1,0, 0,0,-1": Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)),
		"E: 单位": Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)),
	}
	for label in cases.keys():
		var b: Basis = cases[label]
		print("[m] %s" % label)
		print("[m]    basis.x = %s" % str(b.x))
		print("[m]    basis.y = %s   (y分量 %.1f)" % [str(b.y), b.y.y])
		print("[m]    basis.z = %s   <- 本地+Z 映射到的世界方向（门朝向）" % str(b.z))
		print("[m]    行列式 = %.3f" % b.determinant())
	print("[m] --------------------------------------------------")
	print("[m] 目标：basis.y.y > 0（不倒立）+ basis.z = (-1,0,0)（门朝 -X）")
	quit(0)
