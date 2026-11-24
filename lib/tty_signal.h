#ifndef VTK_TTY_SIGNAL_H
#define VTK_TTY_SIGNAL_H

#include <errno.h>
#include <stdbool.h>
#include <signal.h>
#include <unistd.h>

static const int vtk_tty_signals[] = { SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGWINCH, SIGTSTP };
static struct sigaction vtk_tty_previous[sizeof(vtk_tty_signals) / sizeof(vtk_tty_signals[0])];
static size_t vtk_tty_signals_installed;
static volatile sig_atomic_t vtk_tty_terminate;
static volatile sig_atomic_t vtk_tty_interrupt;
static volatile sig_atomic_t vtk_tty_suspend;
static volatile sig_atomic_t vtk_tty_wake_fd = -1;

static void vtk_tty_record_signal(int signal) {
	switch (signal) {
	case SIGINT: vtk_tty_interrupt = 1; break;
	case SIGTSTP: vtk_tty_suspend = 1; break;
	case SIGWINCH: break;
	default: vtk_tty_terminate = 1; break;
	}
	int fd = vtk_tty_wake_fd;
	if (fd >= 0) {
		int saved_errno = errno;
		const char wake = 1;
		(void)write(fd, &wake, sizeof(wake));
		errno = saved_errno;
	}
}

static void vtk_tty_restore_signals(void) {
	vtk_tty_wake_fd = -1;
	while (vtk_tty_signals_installed > 0) {
		size_t i = --vtk_tty_signals_installed;
		sigaction(vtk_tty_signals[i], &vtk_tty_previous[i], NULL);
	}
}

static bool vtk_tty_install_signals(int wake_fd) {
	struct sigaction action = {0};
	action.sa_handler = vtk_tty_record_signal;
	action.sa_flags = SA_RESTART;
	sigemptyset(&action.sa_mask);
	vtk_tty_terminate = vtk_tty_interrupt = vtk_tty_suspend = 0;
	vtk_tty_wake_fd = wake_fd;
	for (size_t i = 0; i < sizeof(vtk_tty_signals) / sizeof(vtk_tty_signals[0]); i++) {
		if (sigaction(vtk_tty_signals[i], &action, &vtk_tty_previous[i]) < 0) {
			vtk_tty_restore_signals();
			return false;
		}
		vtk_tty_signals_installed++;
	}
	return true;
}

static int vtk_tty_take_signal(void) {
	if (vtk_tty_terminate) {
		return SIGTERM;
	}
	if (vtk_tty_suspend) {
		vtk_tty_suspend = 0;
		return SIGTSTP;
	}
	if (vtk_tty_interrupt) {
		vtk_tty_interrupt = 0;
		return SIGINT;
	}
	return 0;
}

#endif
