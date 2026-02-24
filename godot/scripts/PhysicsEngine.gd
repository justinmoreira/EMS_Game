extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
    return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
    return 1.0 + (height_tx + height_rx) / 20.0
