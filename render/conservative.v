module render

// Keep the nearest basic color for terminals without indexed or RGB color.
fn basic_color(color int) int {
	if color & 0x1000000 == 0 && color & 0x2000000 == 0 { return color & 15 }
	mut r, mut g, mut b := (color >> 16) & 255, (color >> 8) & 255, color & 255
	if color & 0x2000000 != 0 {
		index := color & 255
		if index < 16 { return index }
		if index >= 232 {
			r = 8 + (index - 232) * 10
			g, b = r, r
		} else {
			n := index - 16
			r, g, b = cube_level(n / 36), cube_level(n / 6 % 6), cube_level(n % 6)
		}
	}
	return int(r >= 95) + 2 * int(g >= 95) + 4 * int(b >= 95) +
		8 * int(r >= 200 || g >= 200 || b >= 200)
}

fn cube_level(level int) int { return if level == 0 { 0 } else { 55 + 40 * level } }
