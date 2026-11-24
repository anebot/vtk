module common

import vtk

// pick_font_style asks the user to pick one of the vtk font styles, showing a
// live preview of each style's name.
pub fn pick_font_style(mut app vtk.App, owner &vtk.Ctl) ?vtk.FontStyle {
	mut styles := []vtk.FontStyle{}
	$for member in vtk.FontStyle.values {
		styles << member.value
	}
	names := styles.map(vtk.font_convert(it.str(), it))
	at := app.choice_for(owner, 'Unicode text style', names, 2)
	if at < 0 {
		return none
	}
	return styles[at]
}
