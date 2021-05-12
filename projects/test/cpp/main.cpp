#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

pthread_mutex_t g_mutex;
pthread_t g_thread;
std::queue<uint8_t> sw2hwq;
std::queue<uint8_t> hw2swq;
int swmain();

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
	init();
	uint32_t r = 0xffffffff;

	pthread_mutex_lock(&g_mutex);
	if ( !hw2swq.empty() ) {
		r = hw2swq.front();
		hw2swq.pop();
	}
	pthread_mutex_unlock(&g_mutex);
	return r;
}
void uart_send(uint8_t data) {
	init();

	pthread_mutex_lock(&g_mutex);
	sw2hwq.push(data);
	pthread_mutex_unlock(&g_mutex);
}


int swmain() {
	float fd[3] = {0.2,4.8726, 1.12};
	uint32_t* fdi = (uint32_t*)fd;

	for ( int i = 0; i < 3; i++ ) {
		for ( int j = 3; j >= 0; j-- ) {
			uint32_t sval = fdi[i]>>(j*8);
			uart_send(sval&0xff);
		}
	}

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
