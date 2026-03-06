extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0

#assign values to names, Low = 0, Medium =1, High =2
enum FrequencyBand { Low, Medium, High }
enum Bandwidth { Narrow, MediumBand, Wide }


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return 1.0 + (height_tx + height_rx) / 20.0


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
	ptx: float, height_tx: float, height_sensor: float, distance: float, terrain_loss: float = 1
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


func calculate_received_power(
	tx_power: float,
	height_tx: float,
	height_rx: float,
	frequency: float,
	distance: float,
	terrain_loss: float = 1.0
) -> float:
	"""
	Calculates the signal strength (received power) between two entities.

	Formula: ReceivedPower = (TxPower * HeightFactor * FrequencyFactor) / (DistanceLoss * TerrainLoss)

	Args:
		tx_power: Transmission power (0-10)
		height_tx: Transmitter height in meters
		height_rx: Receiver height in meters
		frequency: Frequency in MHz (30-3000)
		distance: Distance in km (calculated by calculate_distance)
		terrain_loss: Terrain attenuation factor (default 1.0)

	Returns:
		Signal strength as a float
	"""
	var height_factor = calculate_height_factor(height_tx, height_rx)
	var frequency_factor = 1000.0 / frequency
	var distance_loss = pow(distance + 1.0, 2.0)

	# Avoid division by zero
	if terrain_loss <= 0:
		terrain_loss = 1.0

	var received_power = (
		(tx_power * height_factor * frequency_factor) / (distance_loss * terrain_loss)
	)
	return received_power
