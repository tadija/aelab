#pragma once
#include <stddef.h>
int ae_spawn_pty(const char *file, char *const argv[], int *master);
int ae_resize_pty(int master, unsigned short cols, unsigned short rows);
