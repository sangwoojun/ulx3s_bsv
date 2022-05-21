#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

#include "../../../src/cpp/ttyifc.h"


void* swmain(void* param) {

	FILE* fin = fopen("example.dat", "rb");
	FILE* fout = fopen("output.dat", "wb");
	if ( fin == NULL ) {
		printf( "Input file not found!\n" );
		exit(0);
	}
	if ( fout == NULL ) {
		printf( "Output file failed to open\n" );
		exit(0);
	}
	
	printf( "Starting image processing!\n" );

	int pixcount = 0;
	int writecnt = 0;
	while (!feof(fin)) {
		uint8_t pix;
		size_t r = fread(&pix, sizeof(uint8_t), 1, fin);
		if ( r != 1 ) continue;
		uart_send(pix);

		pixcount++;

		uint32_t rcheck = uart_recv();
		while (rcheck <= 0xff) {
			fwrite(&rcheck, sizeof(uint8_t), 1, fout);
			writecnt++;
			rcheck = uart_recv();
		}
		if (pixcount >= 512*256) break;
	}

	while (writecnt < 256*512) {
		uint32_t rcheck = uart_recv();
		while ( rcheck > 0xff ) {
			rcheck = uart_recv();
		}
		fwrite(&rcheck, sizeof(uint8_t), 1, fout);
		writecnt++;
	}

	printf( "Image processing done! %d pixels\n", pixcount );
	printf( "Output written to output.dat\n" );
	exit(0);
}

int
main() {
	int ret = open_tty("/dev/ttyUSB0");
	if ( ret ) return ret;

	swmain(NULL);
}
