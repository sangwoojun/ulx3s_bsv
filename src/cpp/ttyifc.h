#ifndef __TTYIFC_H__
#define __TTYIFC_H__

#include <errno.h>
#include <fcntl.h> 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <stdint.h>
#include <queue>
#include <pthread.h>

void set_tty_attributes(int fd, int baud);
extern "C" uint32_t bdpiUartGet(uint8_t idx);
extern "C" void bdpiUartPut(uint32_t d);
uint32_t uart_recv();
void uart_send(uint8_t data);
int open_tty(char* path);

#endif
