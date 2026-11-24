#ifndef VTK_TTY_WINDOWS_H
#define VTK_TTY_WINDOWS_H

#include <windows.h>

enum {
	VTK_CONSOLE_INTERRUPT = 1,
	VTK_CONSOLE_BREAK = 2,
};

static volatile LONG vtk_console_events;

static BOOL WINAPI vtk_console_control(DWORD type) {
	switch (type) {
	case CTRL_C_EVENT:
		InterlockedOr(&vtk_console_events, VTK_CONSOLE_INTERRUPT);
		return TRUE;
	case CTRL_BREAK_EVENT:
		InterlockedOr(&vtk_console_events, VTK_CONSOLE_BREAK);
		return TRUE;
	default:
		return FALSE;
	}
}

static BOOL vtk_console_watch_control(BOOL enabled) {
	if (enabled) {
		InterlockedExchange(&vtk_console_events, 0);
	}
	return SetConsoleCtrlHandler(vtk_console_control, enabled);
}

static LONG vtk_console_take_control(void) {
	return InterlockedExchange(&vtk_console_events, 0);
}

#endif
