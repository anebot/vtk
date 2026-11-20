module support

import os

fn test_atomic_save_replaces_preserves_permissions_and_cleans_temporary_file() {
	directory := os.join_path(os.temp_dir(), 'vtk-save-${os.getpid()}')
	os.mkdir(directory) or { panic(err) }
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'document.md')
	save(path, 'first') or { panic(err) }
	os.chmod(path, 0o640) or { panic(err) }
	save(path, 'é😀\x00end') or { panic(err) }
	assert os.read_file(path) or { panic(err) } == 'é😀\x00end'
	$if !windows {
		assert (os.stat(path) or { panic(err) }).mode & 0o777 == 0o640
	}
	assert (os.ls(directory) or { panic(err) }).len == 1
	if _ := save(os.join_path(directory, 'missing', 'file'), 'text') {
		assert false
	}
	assert os.read_file(path) or { panic(err) } == 'é😀\x00end'
}
