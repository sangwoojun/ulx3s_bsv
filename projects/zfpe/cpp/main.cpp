#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
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

void send_input(float data, int input_idx) {
	uart_send(input_idx&0xff);
	
	FloatBit8 b;
	b.f = data;
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

void readfromfile(float* data, char* filename, size_t length) {	
	FILE* f_data = fopen(filename, "rb");
	if (f_data == NULL ) {
		printf("File not found: %s\n", filename);
		exit(1);
	}

	fread(data, sizeof(float), length, f_data);

	fclose(f_data);
}

void* swmain(void* param) {
	srand(time(NULL));
	
	// Original dimension
	size_t input_cnt = 64;
	size_t output_dim = 1024;
	size_t input_dim = 4096;

	// Read float numbers from files
	char weights_filename[] = "vgg19.w24.matrix.bin";	
	char bias_filename[] = "vgg19.w24.bias.bin";
	char inputs_filename[] = "inputs.256.bin";
	char outputs_golden_filename[] = "outputs.256.bin";

	float* weights = (float*)malloc(sizeof(float)*output_dim*input_dim);
	float* bias = (float*)malloc(sizeof(float)*output_dim);
	float* inputs = (float*)malloc(sizeof(float)*input_cnt*input_dim);
	float* outputs = (float*)malloc(sizeof(float)*input_cnt*output_dim);
	float* outputs_golden = (float*)malloc(sizeof(float)*input_cnt*output_dim);
	float* add = (float*)malloc(sizeof(float)*input_cnt);

	readfromfile(&weights[0], weights_filename, output_dim*input_dim);
	readfromfile(&bias[0], bias_filename, output_dim);
	readfromfile(&inputs[0], inputs_filename, input_cnt*input_dim);
	readfromfile(&outputs_golden[0], outputs_golden_filename, input_cnt*output_dim);

	for ( size_t i = 0; i < input_cnt; i ++ ) add[i] = 1;
	
	nn_fc(weights, bias, inputs, add, input_cnt, input_dim, output_dim, outputs);
	printf( "Compute done!" );
	fflush(stdout);

	printf( "Comparing results...\n" );
	double totalnoise = 0;
	for ( size_t i = 0; i < input_cnt; i ++ ) {
		size_t origin = i*output_dim;
		float noise = 0;
		for ( size_t j = origin; j < origin + output_dim; j ++ ) {
			noise += std::abs(outputs[j] - outputs_golden[j]);
		}
		totalnoise += noise;
	}	
	printf( "Compare done! Average error: %lf\n", totalnoise/input_cnt );
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
