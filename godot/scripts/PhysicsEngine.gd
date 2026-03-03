extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
    return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
    return 1.0 + (height_tx + height_rx) / 20.0

func calculate_distance_loss(dis: float) -> float:
     return pow(dis+1.0, 2.0)

func calculate_Srx(
    ptx: float,
    height_tx: float,
    height_sensor: float,
    distance: float,
    terrain_loss: float =1
) -> float:
    var p := clampf(ptx,0.0,10.0)

    var hf = calculate_height_factor(height_tx,height_sensor)
    var dl = calculate_distance_loss(distance)
    
    return (p * hf) /(dl * terrain_loss)

func is_detected() -> bool:
    
