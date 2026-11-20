module support

#include <windows.h>

fn C.MoveFileExW(&u16, &u16, u32) bool

fn rename_atomic(from string, to string) ! {
	if !C.MoveFileExW(from.to_wide(), to.to_wide(), 3) { return error('cannot replace ${to}') }
}
