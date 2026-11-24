module main

import vtk

fn test_parse_chart() {
	text := 'columns|Revenue\n|Q1|Q2|Q3|Q4\nRevenue|12|18|15|24\nPlan|10|14|18|20'
	data := parse_chart(text)
	assert data.kind == 'columns'
	assert data.title == 'Revenue'
	assert data.labels == ['Q1', 'Q2', 'Q3', 'Q4']
	assert data.names == ['Revenue', 'Plan']
	assert data.series.len == 2
	assert data.series[0] == [12.0, 18.0, 15.0, 24.0]
	assert data.series[1] == [10.0, 14.0, 18.0, 20.0]
}

fn test_parse_single_series_chart() {
	data := parse_chart('lines\nJan,10\nFeb,20\nMar,15')
	assert data.kind == 'lines'
	assert data.labels == ['Jan', 'Feb', 'Mar']
	assert data.names == ['Value']
	assert data.series[0] == [10.0, 20.0, 15.0]
}

fn test_parse_shapes_with_colors() {
	area := vtk.Rect{0, 0, 100, 50}
	rect := parse_shape('rect 10 20 40 30 #ff8800', area, vtk.cyan) or {
		panic('missing rectangle')
	}
	assert rect.kind == 'rect'
	assert rect.a == 10
	assert rect.b == 10
	assert rect.c == 40
	assert rect.d == 15
	assert rect.color == vtk.color_rgb(255, 136, 0)
	line := parse_shape('line 0 100 100 100 #00ff00', area, vtk.cyan) or {
		panic('missing line')
	}
	assert line.kind == 'line'
	assert line.b == 49
	assert line.d == 49
	assert line.color == vtk.color_rgb(0, 255, 0)
}

fn test_deck_roundtrip() {
	slides := [Slide{
		id:    1
		body:  '# One'
		notes: 'Only the speaker sees this.'
	}, Slide{
		id:    2
		body:  '# Two\n\n```slide\nrect 10 10 20 20 #59adff\n```'
		notes: 'Second note.'
	}]
	mut deck := Deck{ slides: slides }
	text := deck.text()
	assert text.contains('<!-- slide -->')
	parsed := parse_deck(text)
	assert parsed.len == 2
	assert parsed[0].body == '# One'
	assert parsed[0].notes == 'Only the speaker sees this.'
	assert parsed[1].body == '# Two\n\n```slide\nrect 10 10 20 20 #59adff\n```'
	assert parsed[1].notes == 'Second note.'
}
