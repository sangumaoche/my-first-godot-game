extends CharacterBody2D

# 定义常量 角色朝向的前缀
# := GDScript语法：赋值，作用是告诉Godot在赋值的时候自动推断静态类型
# &"" StringName字面量 告诉godot引擎这是一个固定的名字，性能略好于String
const NORMAL_ANIMATION_PREFIX := &"normal"

# 角色动画节点 这一行代码可以通过左侧的节点树拖拽的方式来添加
@onready var body_sprite: AnimatedSprite2D = $BodySprite

# 当前朝向后缀
var facing_suffix: StringName = &"right"

# 玩家移动速度，单位是像素/秒
# @export 在GDScript中，用来将属性暴露到编辑器界面中
@export var move_speed: float = 120.0

func _ready() -> void:
	_update_animation()

func _physics_process(delta: float) -> void:
	# 读取四个方向输入，并得到标准化后的八向输入向量
	var move_input := Input.get_vector("move_left","move_rigth","move_up","move_down")
	
	# CharacterBody2D 通过 velocity 配合 move_and_slide() 完成移动
	velocity = move_input * move_speed
	move_and_slide()
	
	if move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)
		
	_update_animation()

# 根据当前朝向拼出动画名，并在动画实际变化时再切换播放
func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [NORMAL_ANIMATION_PREFIX,facing_suffix])
	
	if not body_sprite.sprite_frames.has_animation(animation_name):
		push_warning("Missing player animation: %s" % animation_name)
		return
		
	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)
	
# 将任意二维向量映射为四分向动画
# 对角输入会优先去绝对值更大的轴，避免在四向动画里出现歧义
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
		
	return &"down" if direction.y > 0.0 else &"up"
