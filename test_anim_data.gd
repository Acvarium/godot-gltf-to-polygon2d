extends Node2D
@onready var animation_player : AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	var anim_lib = animation_player.get_animation_library("")
	for anim_name in anim_lib.get_animation_list():
		var anim : Animation = anim_lib.get_animation(anim_name)
		for t in anim.get_track_count():
			print(anim.track_get_type(t))
			print(anim.track_get_path(t))
