extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0

#assign values to names, Low = 0, Medium =1, High =2
enum FrequencyBand {Low, Medium, High}
enum Bandwidth {Narrow, MediumBand, Wide}

func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return (height_tx + height_rx) / 20.0


func calculate_distance_loss(dis: float) -> float:
	return pow(dis + 1.0, 2.0)

func frequency_check(emit: FrequencyBand, receiver: Bandwidth) -> bool:
	match receiver:
		Bandwidth.Narrow:
			return emit == FrequencyBand.Low
		Bandwidth.MediumBand:
			return emit == FrequencyBand.Medium or emit == FrequencyBand.Low
		Bandwidth.Wide:
			return true
		_:
			return false

func bandwidth_penalty(receiver: Bandwidth) -> float:
	match receiver:
		Bandwidth.Narrow:
			return 0.0
		Bandwidth.MediumBand:
			return 2.0
		Bandwidth.Wide:
			return 5.0
		_:
			return 0.0


func calculate_Srx(
	ptx: float,
	height_tx: float,
	height_sensor: float,
	distance: float,
	terrain_loss: float = 1
) -> float:
	var p := clampf(ptx, 0.0, 10.0)

	var hf = calculate_height_factor(height_tx, height_sensor)
	var dl = calculate_distance_loss(distance)
	
	return (p * hf) / (dl * terrain_loss)

func is_detected(
	emit: FrequencyBand,
	receiver: Bandwidth,
	sensitivity: float,
	ptx: float,
	height_tx: float,
	height_sensor: float,
	dis: float,
	terrain_loss: float = 1
	) -> bool:
	if not frequency_check(emit, receiver):
		return false
	
	var threshold = sensitivity + bandwidth_penalty(receiver)

	var srx = calculate_Srx(ptx, height_tx, height_sensor, dis, terrain_loss)
	
	return srx > threshold
