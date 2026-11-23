#ifndef VTK_TTY_SIGNAL_H
#define VTK_TTY_SIGNAL_H

#include <errno.h>
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t vtk_tty_signal = 0;
static volatile sig_atomic_t vtk_tty_wake_fd = -1;

static void vtk_tty_set_wake(int fd) {
	vtk_tty_wake_fd = fd;
}

static void vtk_tty_record_signal(int signal) {
	if (signal != SIGWINCH) {
		vtk_tty_signal = signal;
	}
	int fd = vtk_tty_wake_fd;
	if (fd >= 0) {
		int saved_errno = errno;
		const char wake = 1;
		(void)write(fd, &wake, sizeof(wake));
		errno = saved_errno;
	}
}

static int vtk_tty_take_signal(void) {
	int signal = vtk_tty_signal;
	vtk_tty_signal = 0;
	return signal;
}

#endif
