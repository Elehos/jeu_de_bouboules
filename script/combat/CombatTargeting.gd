extends RefCounted
class_name CombatTargeting

const ENEMY_COLLISION_MASK: int = 0b1000

# Cherche l'ennemi (via son Area2D de clic) sous une position donnée.
# global_pos doit être calculée par l'appelant (get_global_mouse_position())
# pour rester cohérente avec son propre repère de CanvasItem.
static func find_enemy_at(viewport: Viewport, global_pos: Vector2) -> Enemy:
	var space_state := viewport.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_pos
	query.collision_mask = ENEMY_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results := space_state.intersect_point(query)
	for result in results:
		var collider = result.collider
		if collider.get_parent() is Enemy:
			return collider.get_parent()
	return null
