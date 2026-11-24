module vtk

fn test_clamp() {
	assert clamp(5, 1, 3) == 3
	assert clamp(-1, 1, 3) == 1
	assert clamp(2, 1, 3) == 2
	assert clamp(5, 3, 1) == 3
}
