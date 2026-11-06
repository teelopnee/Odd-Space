class_name ViewLod
## Cheap "can the camera possibly see this?" test for crowd LOD. The camera has a fixed yaw looking
## down -Z at the player from behind (+Z): on a wide phone screen it shows about +-21 m sideways,
## ~20 m ahead and ~8 m behind the player. The box below adds a margin for look-ahead and tall sprites.
## Off-screen people think 4x less often and skip their animation work (see NPC, Enemy, BillboardSprite).

const HALF_X := 28.0
const AHEAD := 28.0
const BEHIND := 14.0

## Where the camera is looking (the player), set every frame by CameraRig; INF = unknown.
static var focus := Vector3.INF


static func off_screen(pos: Vector3, center: Vector3 = focus) -> bool:
	if not center.is_finite():
		return false
	var dz := pos.z - center.z
	return absf(pos.x - center.x) > HALF_X or dz < -AHEAD or dz > BEHIND
