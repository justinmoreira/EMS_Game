extends Node


func assert_eq(actual, expected, description := ""):
	if is_equal_approx(actual, expected) if actual is float else actual == expected:
		print("[PASS] ", description)
	else:
		print("[FAIL] ", description, ": Expected ", expected, ", Got ", actual)


func assert_true(condition: bool, description := ""):
	assert_eq(condition, true, description)


func assert_false(condition: bool, description := ""):
	assert_eq(condition, false, description)


func assert_approx(actual: float, expected: float, tolerance: float, description := ""):
	if abs(actual - expected) < tolerance:
		print("[PASS] ", description)
	else:
		print("[FAIL] ", description, ": Expected ~", expected, ", Got ", actual)
