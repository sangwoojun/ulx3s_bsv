#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

#include "../../../src/cpp/ttyifc.h"


void* swmain(void* param) {

	uart_send(0xff);
	uart_send(0xbe);
	uart_send(0xef);
	uart_send(0);
	uart_send(0);
	uart_send(0);

	uart_send(0xff);
	uart_send(0xde);
	uart_send(0xad);
	uart_send(0);
	uart_send(0);
	uart_send(1);



	uart_send(0);
	uart_send(0xff);
	uart_send(0xff);
	uart_send(0);
	uart_send(0);
	uart_send(0);

	uart_send(0);
	uart_send(0xff);
	uart_send(0xff);
	uart_send(0);
	uart_send(0);
	uart_send(1);

	printf( "Sent!\n" );

	uint32_t inbuf = 0;
	int inbufr = 1;
	while(true) {
		uint32_t c = uart_recv();
		if ( c > 0xff ) continue;
		inbuf = inbuf | (c<<(inbufr*8));
		if ( inbufr > 0 ) inbufr--;
		else {
			inbufr = 1;
			printf( "%x\n", inbuf );
			inbuf = 0;
			fflush(stdout);
		}

	}





	exit(0);


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
	int ret = open_tty("/dev/ttyUSB0");
	if ( ret ) return ret;

	swmain(NULL);
}
