extends CharacterBody2D

# 定义常量 角色朝向的前缀
# := GDScript语法：赋值，作用是告诉Godot在赋值的时候自动推断静态类型
# &"" StringName字面量 告诉godot引擎这是一个固定的名字，性能略好于String
const NORMAL_ANIMATION_PREFIX := &"normal"

const BULLET_SCENE := preload("res://scene/bullet.tscn")
const ARMED_ANIMATION_PREFIX := &"armed"
const DEFAULT_FIRE_RATE_MULTIPLIER := 1.0
const SPIRAL_PHASE_STEP := PI / 12

# 状态机
const PLAYER_FORM_MODE_NORMAL := 0
const PLAYER_FORM_MODE_ARMED := 1
const SHOT_PATTERN_NORMAL := 0
const SHOT_PATTERN_SPIRAL := 1

# 角色动画节点 这一行代码可以通过左侧的节点树拖拽的方式来添加
@onready var body_sprite: AnimatedSprite2D = $BodySprite
# 螺旋强化状态下额外显示的浮游炮特效
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedSprite
# 射击计时器，只负责限制开火频率
@onready var shooting_timer: Timer = $ShootingTimer

# 当前朝向后缀
var facing_suffix: StringName = &"right"

# 普通射速倍率
var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 强化形态自带的射速倍率
var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 当前玩家形态
var current_form_mode: int = PLAYER_FORM_MODE_NORMAL
# 当前弹幕模式
var current_shot_pattern: int = SHOT_PATTERN_NORMAL
# 螺旋弹幕的相位，用来让连续设计形成旋转感
var spiral_phase: float = 0.0


# 玩家移动速度，单位是像素/秒
# @export 在GDScript中，用来将属性暴露到编辑器界面中
@export var move_speed: float = 120.0

# 连续开火之间的最短间隔
@export var fire_interval: float = 0.18

# 子弹生成时相对玩家中心的偏移距离，避免子弹出生在身体内部
@export var bullet_spawn_distance: float = 18.0

func _ready() -> void:
	
	# 测试
	_test_armed_animation()
	
	shooting_timer.one_shot = true
	shooting_timer.wait_time = _get_effective_fire_interval()
	_update_animation()
	_update_armed_effect()

func _physics_process(delta: float) -> void:
	# 读取四个方向输入，并得到标准化后的八向输入向量
	var move_input := Input.get_vector("move_left","move_rigth","move_up","move_down")
	# 读取子弹发射的四个方向
	var shoot_input := Input.get_vector("shoot_left","shoot_right","shoot_up","shoot_down")
	
	# CharacterBody2D 通过 velocity 配合 move_and_slide() 完成移动
	velocity = move_input * move_speed
	move_and_slide()
	
	# 根据发射状态机来判断发射哪种子弹
	if current_shot_pattern == SHOT_PATTERN_SPIRAL:
		_try_auto_spiral_shoot()
	elif shoot_input != Vector2.ZERO:
		_try_shoot(shoot_input)
	
	# 更新动画
	_update_facing(move_input, shoot_input)	
	_update_animation()
	_update_armed_effect()

# 测试强化模式效果
func _test_armed_animation() -> void:
	current_form_mode = PLAYER_FORM_MODE_ARMED
	current_shot_pattern = SHOT_PATTERN_SPIRAL
	form_fire_rate_multiplier = 5.0
	spiral_phase = 0.0

# 根据当前朝向拼出动画名，并在动画实际变化时再切换播放
func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [_get_animation_prefix(),facing_suffix])
	
	if not body_sprite.sprite_frames.has_animation(animation_name):
		var fallback_animtion_name := StringName("%s_%s" % [NORMAL_ANIMATION_PREFIX,facing_suffix])
		if not body_sprite.sprite_frames.has_animation(fallback_animtion_name):
			push_warning("Missing player animation: %s" % animation_name)
			return
		animation_name = fallback_animtion_name
		
	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)

# 射击方向优先于移动方向，用于决定当前显示的角色朝向
# 自动螺旋弹幕期间不再读取射击输入，而是仅按移动方向更新 armed 动画朝向
func _update_facing(move_input: Vector2,shoot_input: Vector2) -> void:
	if current_shot_pattern == SHOT_PATTERN_SPIRAL:
		if move_input != Vector2.ZERO:
			facing_suffix = _vector_to_facing_suffix(move_input)
		return
	
	if shoot_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(shoot_input)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)

# 尝试发射子弹：先检查冷却，再根据当前弹幕模式发射。
func _try_shoot(shoot_input: Vector2) -> void:
	if not shooting_timer.is_stopped():
		return
		
	var shoot_direction := shoot_input.normalized()
	var has_spawned_bullet := _fire_bullets(shoot_direction)
	# 子弹发射成功后，再重制子弹发射冷却时间。这样设计可以用来进行一些类似异常状态时的特殊处理，比如沉默时，发射子弹失败了，就不能重制子弹冷却时间
	if has_spawned_bullet:
		shooting_timer.start(_get_effective_fire_interval())

func _fire_bullets(base_direction: Vector2) -> bool:
	if current_shot_pattern == SHOT_PATTERN_SPIRAL:
		var has_spawned_forward_bullet := _spaw_bullet(base_direction)
		var has_spawned_backward_bullet := _spaw_bullet(base_direction.rotated(PI))
		spiral_phase = wrapf(spiral_phase + SPIRAL_PHASE_STEP, 0.0, TAU)
		return has_spawned_forward_bullet or has_spawned_backward_bullet
		
	return _spaw_bullet(base_direction)

# 实例化并生成一枚子弹
func _spaw_bullet(shoot_direction: Vector2) -> bool:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	if bullet == null:
		return false
	
	bullet.top_level = true
	bullet.setup(shoot_direction)
	
	# 子弹挂到当前主场景下，避免跟随玩家一起移动
	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		return false
		
	spawn_parent.add_child(bullet)
	bullet.global_position = global_position + shoot_direction * bullet_spawn_distance
	return true

# 螺旋形态下自动按固定节奏 360 度方向旋转发射。
func _try_auto_spiral_shoot() -> void:
	if not shooting_timer.is_stopped():
		return
	
	# 向右偏移向量，已做出旋转效果
	var spiral_dirction := Vector2.RIGHT.rotated(spiral_phase)
	var has_spawned_bullet := _fire_bullets(spiral_dirction)
	if has_spawned_bullet:
		shooting_timer.start(_get_effective_fire_interval())
		
# 计算当前有效开火间隔，射速倍率越高，开火间隔越短
func _get_effective_fire_interval() -> float:
	return maxf(fire_interval / _get_effective_fire_rate_multiplier() , 0.01)
	
# 强化形态激活时优先使用形态自带的射速倍率，否则退回普通射速倍率。
func _get_effective_fire_rate_multiplier() -> float:
	if _has_active_form_override():
		return maxf(form_fire_rate_multiplier, 0.01)
		
	return maxf(rapid_fire_rate_multiplier, 0.01)

# 只要玩家仍处于特殊形态或特殊弹幕模式，就视为强化仍在生效
func _has_active_form_override() -> bool:
	return (
		current_form_mode != PLAYER_FORM_MODE_NORMAL
		or current_shot_pattern != SHOT_PATTERN_NORMAL
	)

# 根据当前形态返回动画词前缀
func _get_animation_prefix() -> StringName:
	if current_form_mode == PLAYER_FORM_MODE_ARMED:
		return ARMED_ANIMATION_PREFIX
		
	return NORMAL_ANIMATION_PREFIX
	
# 强化螺旋形态下显示浮游炮动画，结束后隐藏并停止播放。
func _update_armed_effect() -> void:
	var is_armed := current_form_mode == PLAYER_FORM_MODE_ARMED
	
	if not is_armed:
		if armed_effect_sprite.visible:
			armed_effect_sprite.visible = false
		if armed_effect_sprite.is_playing():
			armed_effect_sprite.stop()
		return
		
	if not armed_effect_sprite.visible:
		armed_effect_sprite.visible = true
	if armed_effect_sprite.is_playing():
		return
	if armed_effect_sprite.sprite_frames == null:
		return
		
	if armed_effect_sprite.sprite_frames.has_animation(&"default"):
		armed_effect_sprite.play(&"default")

# 将任意二维向量映射为四分向动画
# 对角输入会优先去绝对值更大的轴，避免在四向动画里出现歧义
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
		
	return &"down" if direction.y > 0.0 else &"up"
