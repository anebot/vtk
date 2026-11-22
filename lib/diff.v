module vtk

fn diff_range_count(range string) int {
	return if range.contains(',') { max(0, range.all_after(',').int()) } else { 1 }
}

// Hunk counts distinguish file headers from removed/added text starting --/++.
// This also handles concatenated unified diffs without diff --git separators.
fn diff_rows(text string) []TextRow {
	mut rows := plain_rows(text)
	mut old_left := 0
	mut new_left := 0
	for mut row in rows {
		line := text[row.start..row.end]
		if line.starts_with('@@ ') {
			row.color = cyan
			ranges := line.fields()
			old_left = 0
			new_left = 0
			if ranges.len >= 3 && ranges[1].starts_with('-') && ranges[2].starts_with('+') {
				old_left = diff_range_count(ranges[1])
				new_left = diff_range_count(ranges[2])
			}
		} else if old_left > 0 || new_left > 0 {
			if line.starts_with('-') {
				row.color = red
				old_left = max(0, old_left - 1)
			} else if line.starts_with('+') {
				row.color = green
				new_left = max(0, new_left - 1)
			} else if line.starts_with(' ') {
				old_left = max(0, old_left - 1)
				new_left = max(0, new_left - 1)
			} else if !line.starts_with('\\') {
				old_left = 0
				new_left = 0
			}
		} else if line.starts_with('diff ') || line.starts_with('index ')
			|| line.starts_with('--- ') || line.starts_with('+++ ') {
			row.attr = bold
		}
	}
	return rows
}
