#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

#include "../../../src/cpp/ttyifc.h"


void* swmain(void* param) {
	float matrix_a[4][4];
	float matrix_b[4][4];
	float matrix_c[4][4];
	float matrix_c_golden[4][4] = {0};

	srand(time(NULL));
	for ( int i = 0; i < 4; i++ ) {
		for ( int j = 0; j < 4; j++ ) {
			//matrix_a[i][j] = 2*i+j;
			matrix_a[i][j] = ((rand()%128)*1.0-64)/32;
			for ( int k = 0; k < 4; k++ ) {
				float* v = &(matrix_a[i][j]);
				uart_send(((uint8_t*)v)[k]);
			}
		}
	}
	for ( int i = 0; i < 4; i++ ) {
		for ( int j = 0; j < 4; j++ ) {
			//matrix_b[i][j] = 1.0+j;
			matrix_b[i][j] = ((rand()%128)*1.0-64)/32;
			for ( int k = 0; k < 4; k++ ) {
				float* v = &(matrix_b[i][j]);
				uart_send(((uint8_t*)v)[k]);
			}
		}
	}

	
	for ( int i = 0; i < 4; i++ ) {
		for ( int j = 0; j < 4; j++ ) {
			for ( int k = 0; k < 4; k++ ) {
				uint32_t rcheck = uart_recv();
				while (rcheck > 0xff) rcheck = uart_recv();

				uint8_t rv = *((uint8_t*)&rcheck);
				float* v = &(matrix_c[i][j]);
				((uint8_t*)v)[k] = rv;

				matrix_c_golden[i][j] += matrix_a[i][k]*matrix_b[j][k];
			}
		}
	}

	printf( "Results from accelerator:\n" );
	for ( int i = 0; i < 4; i++ ) {
		for ( int j = 0; j < 4; j++ ) {
			printf( "%2.02f ", matrix_c[i][j] );
		}
		printf("\n");
	}
	printf("\n");

	printf( "Results golden:\n" );
	for ( int i = 0; i < 4; i++ ) {
		for ( int j = 0; j < 4; j++ ) {
			printf( "%2.02f ", matrix_c_golden[i][j] );
		}
		printf("\n");
	}
	printf("\n");

	printf( "Finished execution!\n" );
	fflush(stdout);
	exit(0);
}

int
main() {
	int ret = open_tty("/dev/ttyUSB0");
	if ( ret ) return ret;

	swmain(NULL);
}
