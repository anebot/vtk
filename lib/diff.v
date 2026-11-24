module vtk

import math { max }

fn diff_range_count(range string) int {
	return if range.contains(',') { max(0, range.all_after(',').int()) } else { 1 }
}

// Hunk counts distinguish file headers from removed/added text starting --/++.
// This also handles concatenated unified diffs without diff --git separators.
fn diff_rows_from(text string, resume TextCheckpoint) ([]TextRow, TextCheckpoint) {
	mut rows := plain_rows(text, resume.offset, resume.line)
	mut diff := resume.highlighter.diff_state
	mut next := resume
	for i, mut row in rows {
		if i == rows.len - 1 {
			next = TextCheckpoint{offset: row.start, line: row.line,
				highlighter: CodeHighlighter{diff_state: diff}}
		}
		diff.highlight(text[row.start..row.end], mut row)
	}
	return rows, next
}

struct DiffHighlighter {
mut:
	old_left int
	new_left int
}

fn (mut diff DiffHighlighter) highlight(line string, mut row TextRow) {
	if line.starts_with('@@ ') {
		row.color = cyan
		ranges := line.fields()
		diff.old_left = 0
		diff.new_left = 0
		if ranges.len >= 3 && ranges[1].starts_with('-') && ranges[2].starts_with('+') {
			diff.old_left = diff_range_count(ranges[1])
			diff.new_left = diff_range_count(ranges[2])
		}
	} else if diff.old_left > 0 || diff.new_left > 0 {
		if line.starts_with('-') {
			row.color = red
			diff.old_left = max(0, diff.old_left - 1)
		} else if line.starts_with('+') {
			row.color = green
			diff.new_left = max(0, diff.new_left - 1)
		} else if line.starts_with(' ') {
			diff.old_left = max(0, diff.old_left - 1)
			diff.new_left = max(0, diff.new_left - 1)
		} else if !line.starts_with('\\') {
			diff.old_left = 0
			diff.new_left = 0
		}
	} else if line.starts_with('diff ') || line.starts_with('index ')
		|| line.starts_with('--- ') || line.starts_with('+++ ') {
		row.attr = bold
	} else if line.starts_with('-') {
		row.color = red
	} else if line.starts_with('+') {
		row.color = green
	}
}
