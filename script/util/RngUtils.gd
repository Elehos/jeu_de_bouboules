extends RefCounted
class_name RngUtils

# Array.shuffle()/Array.pick_random() utilisent toujours le RNG global du
# moteur, jamais une instance RandomNumberGenerator précise — ces deux
# fonctions statiques reproduisent le même contrat en piochant explicitement
# dans le RandomNumberGenerator fourni, pour que tout tirage "gameplay"
# passe par un RNG seedable (RunManager.run_rng) au lieu du RNG global.

static func shuffle(rng: RandomNumberGenerator, array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp

static func pick_random(rng: RandomNumberGenerator, array: Array):
	return array[rng.randi_range(0, array.size() - 1)]
