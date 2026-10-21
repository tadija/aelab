#ifndef __APPLE__
#define _GNU_SOURCE
#endif
#include "CPTY.h"
#include <unistd.h>
#include <fcntl.h>
#include <spawn.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#ifdef __APPLE__
#include <util.h>
#include <crt_externs.h>
#else
#include <pty.h>
extern char **environ;
#endif
// posix_spawn avoids running Swift/runtime code in a multithreaded fork child.
int ae_spawn_pty(const char *file, char *const argv[], int *master) {
    int slave; struct winsize size = {.ws_row=24, .ws_col=80};
    if (openpty(master, &slave, NULL, NULL, &size)) return -1;
    // OpenSSH snapshots the local modes for the remote PTY, then enters raw mode itself.
    // Starting raw here propagates -opost/-onlcr and breaks ordinary shell output.
    fcntl(*master, F_SETFD, FD_CLOEXEC); fcntl(slave, F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    char slave_name[128];
    if (ttyname_r(slave, slave_name, sizeof(slave_name))) {
        posix_spawn_file_actions_destroy(&actions); close(slave); close(*master); return -1;
    }
    // Open after POSIX_SPAWN_SETSID so the child acquires its controlling terminal.
    // Merely duplicating the parent's slave FD does not establish terminal ownership.
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, slave_name, O_RDWR, 0);
    posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, *master);
    posix_spawn_file_actions_addclose(&actions, slave);
    posix_spawnattr_t attr; posix_spawnattr_init(&attr);
    // Swift/NIO worker threads may block signals. Never pass that mask to OpenSSH.
    sigset_t mask; sigemptyset(&mask); posix_spawnattr_setsigmask(&attr, &mask);
    sigset_t defaults; sigemptyset(&defaults);
    int signals[] = {SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGCHLD, SIGWINCH};
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) sigaddset(&defaults, signals[i]);
    posix_spawnattr_setsigdefault(&attr, &defaults);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    pid_t pid;
#ifdef __APPLE__
    char **env = *_NSGetEnviron();
#else
    char **env = environ;
#endif
    size_t count = 0; while (env[count]) count++;
    char **terminal_env = calloc(count + 2, sizeof(char *));
    if (!terminal_env) {
        posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&actions);
        close(slave); close(*master); return -1;
    }
    size_t index = 0;
    for (size_t i = 0; i < count; i++) if (strncmp(env[i], "TERM=", 5)) terminal_env[index++] = env[i];
    terminal_env[index] = "TERM=xterm-256color";
    int error = posix_spawn(&pid, file, &actions, &attr, argv, terminal_env);
    free(terminal_env);
    posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&actions); close(slave);
    if (error) { close(*master); return -1; } return pid;
}
int ae_resize_pty(int master, unsigned short cols, unsigned short rows) {
    struct winsize size = {.ws_row=rows, .ws_col=cols}; return ioctl(master, TIOCSWINSZ, &size);
}
