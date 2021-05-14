#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

#include "ttyifc.h"

pthread_mutex_t g_mutex;
pthread_t g_thread;
std::queue<uint8_t> sw2hwq;
std::queue<uint8_t> hw2swq;
void* swmain(void* param);

int tty_fd;

bool g_init_done = false;
void init() {
	if ( g_init_done ) return;
	pthread_mutex_init(&g_mutex, NULL);
	pthread_create(&g_thread, NULL, swmain, NULL);

	g_init_done = true;
}

uint8_t g_outidx = 0xff;
extern "C" uint32_t bdpiUartGet(uint8_t idx) {
	init();

	uint32_t data = 0xffffffff;
	pthread_mutex_lock(&g_mutex);
	if ( idx != g_outidx && !sw2hwq.empty() ) {
		// get new data
		data = sw2hwq.front();
		sw2hwq.pop();
		//printf( "uart get %d %d %d -> %x\n", idx, g_outidx, sw2hwq.size(), data&0xff );
		g_outidx = ((int)g_outidx+1)&0xff;
	}
	pthread_mutex_unlock(&g_mutex);
	return data;
}

uint8_t g_inidx = 0xff;
extern "C" void bdpiUartPut(uint32_t d) {
	init();

	uint8_t idx = 0xff&(d>>8);
	uint8_t data = 0xff&d;
	if ( idx != g_inidx ) {
		g_inidx = idx;
		//printf( "--%d, %d\n",idx, data );
		pthread_mutex_lock(&g_mutex);
		hw2swq.push(data);
		pthread_mutex_unlock(&g_mutex);
	}
}

uint32_t uart_recv() {
	uint32_t r = 0xffffffff;
#ifdef SYNTH
	uint32_t din = 0;
	int rdlen = read(tty_fd, &din, 1);
	if ( rdlen > 0 ) r = din;
	if ( rdlen > 1 ) printf( "received too many bytes from uart! %d\n", rdlen );
#else
	init();

	pthread_mutex_lock(&g_mutex);
	if ( !hw2swq.empty() ) {
		r = hw2swq.front();
		hw2swq.pop();
	}
	pthread_mutex_unlock(&g_mutex);
#endif
	return r;
}
void uart_send(uint8_t data) {
#ifdef SYNTH
	write(tty_fd, &data, sizeof(data));
	tcdrain(tty_fd);
#else
	init();

	pthread_mutex_lock(&g_mutex);
	sw2hwq.push(data);
	pthread_mutex_unlock(&g_mutex);
#endif
}


void* swmain(void* param) {
	//float fd[3] = {0.2,4.8726, 1.12};
	float fd[3] = {1,40.161865, 6};
	uint32_t* fdi = (uint32_t*)fd;

	for ( int i = 0; i < 3; i++ ) {
		for ( int j = 3; j >= 0; j-- ) {
			uint32_t sval = fdi[i]>>(j*8);
			uart_send(sval&0xff);
		}
	}
	printf( "Sent all data\n" );

	uint32_t ir = 0;
	int fc = 3;
	while(true) {
		uint32_t c = uart_recv();
		if ( c > 0xff ) continue;
		ir = ir | (c<<(fc*8));
		if ( fc > 0 ) fc--;
		else {
			fc = 3;
			printf( "%f\n", *(float*)&ir );
		}

	}

}

int
main() {
	char* ttyname = "/dev/ttyUSB0";
	tty_fd = open(ttyname, O_RDWR | O_NOCTTY | O_SYNC);
	if (tty_fd < 0) {
		printf("Error opening TTY %s (%s)\n", ttyname, strerror(errno));
		return 1;
	}
	set_tty_attributes(tty_fd, B115200);

	/* // not necessary since VMIN and VTIME set to zero...?
	int flags = fcntl(tty_fd, F_GETFL, 0);
	fcntl(tty_fd, F_SETFL, flags | O_NONBLOCK);
	*/

	swmain(NULL);
}
