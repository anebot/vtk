module support

import io.util
import os

// Keep the previous file intact if writing or replacing the new one fails.
pub fn save(path string, text string) ! {
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
