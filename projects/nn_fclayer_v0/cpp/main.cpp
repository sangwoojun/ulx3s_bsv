#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <queue>

#include "../../../src/cpp/ttyifc.h"
#include "nn_fc.h"

typedef union {
	float f;
	uint8_t c[4];
} FloatBit8;

void send_weight(float data) {
	uart_send(0xff);

	FloatBit8 b;
	b.f = data;
	uart_send(b.c[0]);
	uart_send(b.c[1]);
	uart_send(b.c[2]);
	uart_send(b.c[3]);
}

void send_input(float value, int input_idx) {
	uart_send(input_idx&0xff);
	
	FloatBit8 b;
	b.f = value;
	uart_send(b.c[0]);
	uart_send(b.c[1]);
	uart_send(b.c[2]);
	uart_send(b.c[3]);
}

FC_Result recv_result() {
	FC_Result r;
	r.value = 0;
	r.input_idx = 0;
	r.output_idx = 0;
	r.valid = false;
	uint32_t res = uart_recv();
	if ( res > 0xff ) return r;
	r.input_idx = res;
	r.valid = true;


	res = uart_recv();
	while ( res > 0xff ) res = uart_recv();
	r.output_idx = res;


	FloatBit8 b;
	for ( int i = 0; i < 4; i++ ) {
		uint32_t res = uart_recv();
		while ( res > 0xff ) res = uart_recv();
		b.c[i] = res;
	}
	r.value = b.f;



	return r;
}


void* swmain(void* param) {
	srand(time(NULL));
	int input_cnt = 64;
	int output_dim = 64;
	int input_dim = 1024;
	float* weights = (float*)malloc(sizeof(float)*input_dim*output_dim);
	for ( int i = 0; i < input_dim*output_dim; i++ ) {
		weights[i] = 0;
		if ( rand()%4 == 0 ) {
			weights[i] = ((float)(rand()%10000))/1000;
		}
	}
	float* inputs = (float*)malloc(sizeof(float)*input_dim*input_cnt);
	for ( int i = 0; i < input_dim*input_cnt; i++ ) {
		inputs[i] = 0;
		if ( rand()%4 == 0 ) {
			inputs[i] = ((float)(rand()%10000))/1000;
		}
	}
	float* answer = (float*)malloc(sizeof(float)*output_dim*input_cnt);
	float* answergolden = (float*)malloc(sizeof(float)*output_dim*input_cnt);
	for ( int i = 0; i < input_cnt; i++ ) {
		for ( int j = 0; j < output_dim; j++ ) {
			answergolden[i*output_dim+j] = 0;
			for ( int k = 0; k < input_dim; k++ ) {
				answergolden[i*output_dim+j] += weights[j*input_dim+k]*inputs[i*input_dim+k];
			}
		}
	}
	nn_fc(weights, inputs, input_cnt, input_dim, output_dim, answer);
	printf( "Compute done!" );
	fflush(stdout);

	printf( "Comparing results...\n" );
	float diffsum = 0;
	for ( int i = 0; i < input_cnt*output_dim; i++ ) {
		float diff = answer[i] - answergolden[i];
		if ( diff < 0 ) diff = -diff;
		if ( diff > 1 ) {
			printf( "Error larger than 1 at %d! %f (%f vs %f)\n", i, diff, answer[i], answergolden[i] );
		}
		diffsum += diff;
	}
	printf( "Compare done! Average diff %f\n", diffsum/(input_cnt*output_dim) );
	fflush(stdout);


	exit(0);
	return NULL;
}

int
main() {
	int ret = open_tty("/dev/ttyUSB0");
	if ( ret ) return ret;

	swmain(NULL);
}
