module common

import os
import vtk

// confirm_replace asks before saving to a new path that already exists.
pub fn confirm_replace(mut app vtk.App, owner &vtk.Ctl, path string) bool {
	return !os.exists(path) || app.confirm_for(owner, 'Replace file', 'Replace ${path}?')
}

pub enum UnsavedChoice {
	save
	discard
	cancel
}

pub fn ask_unsaved(mut app vtk.App, owner &vtk.Ctl, title string) UnsavedChoice {
	return match app.choice_for(owner, title, ['Save', 'Discard', 'Cancel'], 3) {
		0 { .save }
		1 { .discard }
		else { .cancel }
	}
}
