extends Area2D
class_name Bullet

const WORLD_COLLISION_MASK := 1

# 子弹飞行速度
@export var speed: float = 320.0

# 子弹最大存活时间
@export var max_lifetime: float = 2.0

# 子弹当前飞行方向
var direction: Vector2 = Vector2.RIGHT

# 剩余存活时间
var remaining_lefetime: float = 0.0

# 生命周期初始化，并绑定 Area2D 的碰撞信号
func _ready() -> void:
	remaining_lefetime = max_lifetime
	area_entered.connect(_on_area_entered)

# 外部接口： 注入子弹初始方向
func setup(initial_direction: Vector2) -> void:
	if initial_direction != Vector2.ZERO:
		direction = initial_direction.normalized()
		
	rotation = direction.angle()
	
# 物理帧进程，每帧先检测飞行路径是否会撞到世界，再更新位置并处理超时回收。
func _physics_process(delta: float) -> void:
	var current_position := global_position
	var next_position := current_position + direction * speed * delta
	
	if _will_hit_world(current_position, next_position):
		# 排队，删除
		queue_free()
		return;
		
	# 更新位置
	global_position = next_position
	
	# 计算剩余生命周期，判断是否需要删除
	remaining_lefetime -= delta
	if remaining_lefetime <= 0.0:
		queue_free()
		
# 使用射线查询检测当前这一帧的飞行路径，避免子弹穿过零厚度边界或薄墙体
func _will_hit_world(from_position: Vector2, to_position: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false
		
	var query := PhysicsRayQueryParameters2D.create(from_position,to_position,WORLD_COLLISION_MASK)
	
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var hit_result: Dictionary = space_state.intersect_ray(query)
	return not hit_result.is_empty()
	

	
