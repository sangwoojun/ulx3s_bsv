#ifndef __TTYIFC_H__
#define __TTYIFC_H__

#include <errno.h>
#include <fcntl.h> 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

void set_tty_attributes(int fd, int baud);

#endif
