module vtk

import io.util
import os

// save_atomic writes text to path through a temporary file beside it, so a
// failed write or replace keeps the previous contents. The temporary file
// inherits the target's permissions and replaces it atomically.
pub fn save_atomic(path string, text string) ! {
	target := if os.exists(path) { os.real_path(path) } else { os.abs_path(path) }
	mut file, temporary := util.temp_file(path: os.dir(target), pattern: '.vtk-*.tmp')!
	defer {
		file.close()
		if os.exists(temporary) { os.rm(temporary) or {} }
	}
	// Use a standard writable stdio mode on all libc implementations.
	file.reopen(temporary, 'wb')!
	mut offset := 0
	for offset < text.len {
		written := file.write_string(text[offset..])!
		if written <= 0 { return error('short write: ${path}') }
		offset += written
	}
	file.close()
	if stat := os.stat(target) { os.chmod(temporary, int(stat.mode & 0o777))! }
	rename_atomic(temporary, target)!
}
