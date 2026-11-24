module vtk

fn test_min_max_abs() {
	assert min(2, 3) == 2
	assert min(3, 2) == 2
	assert max(2, 3) == 3
	assert max(3, 2) == 3
	assert abs(-4) == 4
	assert abs(4) == 4
	assert abs(0) == 0
	assert clamp(5, 1, 3) == 3
	assert clamp(-1, 1, 3) == 1
	assert clamp(2, 1, 3) == 2
}
