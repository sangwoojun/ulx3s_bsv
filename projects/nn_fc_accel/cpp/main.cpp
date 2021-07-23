#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <algorithm>
#include <cmath>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <queue>

#include "../../../src/cpp/ttyifc.h"
#include "nn_fc.h"

// exponent of single is 8 bit signed integer (-126 to +127)
#define EXP_MAX ((1<<(8-1))-1)

// exponent of the minimum granularity value expressible via single
#define ZFP_MIN_EXP -149
#define ZFP_MAX_PREC 32
#define EBITS (8+1)

typedef union {
	float f;
	uint8_t c[4];
} FloatBit8;

class BitBuffer {
public:
	BitBuffer(int bytes);
	void EncodeBit(uint32_t src);
	void EncodeBits(uint32_t src, int bits);
	int BitCount() { return curbits; };

	void DecodeBit(uint32_t* dst);
	void DecodeBits(uint32_t* dst, int bits);

	uint8_t* buffer;
	int bufferbytes;
	int curbits;
	int decoff;
};
BitBuffer::BitBuffer(int bytes) {
	this->buffer = (uint8_t*)malloc(bytes);
	for ( int i = 0; i < bytes; i++ ) this->buffer[i] = 0;

	this->bufferbytes = bytes;
	this->curbits = 0;
	this->decoff = 0;
}
void
BitBuffer::EncodeBit(uint32_t src) {
	int byteoff = (curbits/8);
	int bitoff = curbits%8;
	buffer[byteoff] |= ((src&1)<<bitoff);

	curbits++;
}
void
BitBuffer::EncodeBits(uint32_t src, int bits) {
	for ( int i = 0; i < bits; i++ ) {
		EncodeBit(src);
		src >>= 1;
	}
}	
void 
BitBuffer::DecodeBit(uint32_t* dst) {
	int byteoff = (decoff/8);
	int bitoff = decoff%8;
	uint8_t buf = buffer[byteoff];
	*dst = (buf>>bitoff) & 1;
	decoff++;
}
void 
BitBuffer::DecodeBits(uint32_t* dst, int bits) {
	*dst = 0;
	for ( int i = 0; i < bits; i++ ) {
		uint32_t o = 0;
		DecodeBit(&o);
		*dst |= (o<<i);
	}
}

void send_weight(uint8_t data) {
	uart_send(0xff);
	uart_send(data);
}
void send_input(uint8_t data, int input_idx) {
	uart_send(input_idx&0xff);
	uart_send(data);
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

// convert int to negabinary uint
static uint32_t int2uint_int32(int32_t x)
{
  return ((uint32_t)x + 0xaaaaaaaa) ^ 0xaaaaaaaa;
}

static void fwd_lift_int32(int32_t* p, uint s)
{
  int32_t x, y, z, w;
  x = *p; p += s;
  y = *p; p += s;
  z = *p; p += s;
  w = *p; p += s;

  x += w; x >>= 1; w -= x;
  z += y; z >>= 1; y -= z;
  x += z; x >>= 1; z -= x;
  w += y; w >>= 1; y -= w;
  w += y >> 1; y -= w >> 1;

  p -= s; *p = w;
  p -= s; *p = z;
  p -= s; *p = y;
  p -= s; *p = x;
}

void compress_1d(float original[4], BitBuffer* output, int bit_budget, bool verbose) {
	if ( verbose ) {
		printf( "Orig: " );
		for ( int i = 0; i < 4; i++ ) {
			printf( "%f ", original[i] );
			if ( (i+1)%4 == 0 ) printf( "\n" );
		}
	}

	int exp_max = -EXP_MAX;
	for ( int i = 0; i < 4; i++ ) {
		if ( original[i] != 0 ) {
			int exp = 0;
			std::frexp(original[i], &exp);
			if ( exp > exp_max ) exp_max = exp;
		}
	}
	int dimension = 1;
	int precision_max = std::min(ZFP_MAX_PREC, std::max(0, exp_max - ZFP_MIN_EXP + (2*(dimension+1))));
	if ( precision_max != 0 ) {
		int e = exp_max + EXP_MAX;
		if ( verbose ) printf( "exp_max: %d e: %d\n", exp_max, e );
		int32_t idata[4];
		for ( int i = 0; i < 4; i++ ) {
			idata[i] = (int32_t)(original[i]*(pow(2, 32-2 - exp_max)));
			//printf( "%d ,", idata[i] );
		}
		//printf( "\n" );
		
		// perform lifting
		fwd_lift_int32(idata, 1);
		
		// convert to negabinary
		uint32_t udata[4];
		for ( int i = 0; i < 4; i++ ) { 
			udata[i] = int2uint_int32(idata[i]);
			//printf( "%8x\n", udata[i] );
		}

		int total_bits = EBITS;
		output->EncodeBits(e, EBITS);


		for ( int i = 0; i < 4; i++ ) {
			uint32_t u = udata[i];
			if ( (u>>28) == 0 ) {
				output->EncodeBit(0);
				output->EncodeBits(u>>(32-bit_budget-4), bit_budget);
				total_bits += bit_budget + 1;
			} else {
				output->EncodeBit(1);
				output->EncodeBits(u>>(32-bit_budget), bit_budget);
				total_bits += bit_budget + 1;
			}
		}
		
		//printf( "Compression done! emitted %d bits from %ld bits across %d bitplanes\n", total_bits, sizeof(float)*8*4, bitplane_cnt );
	} else {
		if ( verbose ) printf( "All zeros\n" );
	}
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
	size_t output_dim = 4096;
	size_t input_dim = 4096;
	// Compressed dimension 
	size_t comp_buffer_size = 5;
	size_t comp_input_cnt = (input_cnt/4)*comp_buffer_size;
	size_t comp_output_dim = (output_dim/4)*comp_buffer_size;

	int bit_budget = 5;
	int cycle = 0;
	
	bool verbose = false;	
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

	readfromfile(&weights[0], weights_filename, output_dim*input_dim);
	readfromfile(&bias[0], bias_filename, output_dim);
	readfromfile(&inputs[0], inputs_filename, input_cnt*input_dim);
	readfromfile(&outputs_golden[0], outputs_golden_filename, input_cnt*output_dim);
	
	// Compressing weights
	float original[4];
	uint8_t* comp_weights = (uint8_t*)malloc(sizeof(uint8_t)*comp_output_dim*input_dim);
	for ( size_t i = 0; i < input_dim; i ++ ) {
		for ( size_t j = 0; j < output_dim; j += 4 ) {
			BitBuffer* output = new BitBuffer(4*sizeof(float));
			for ( size_t k = 0; k < 4; k ++ ) {
				original[k] = weights[(j+k)*input_dim + i];
			}

			compress_1d(original, output, bit_budget, verbose);
			for ( size_t l = 0; l < 5; l ++ ) {
				comp_weights[(cycle+l)*input_dim + i] = output->buffer[l];
			}
			if ( verbose ) printf( "Compressed to %d bits\n", output->BitCount() );
		
			cycle += 5;
	
			delete output;
		}
		cycle = 0;
	}
	// Compressing bias
	uint8_t* comp_bias = (uint8_t*)malloc(sizeof(uint8_t)*comp_output_dim);
	for ( size_t i = 0; i < output_dim; i += 4 ) {
		BitBuffer* output = new BitBuffer(4*sizeof(float));
		for ( size_t j = 0; j < 4; j ++ ) {
			original[j] = bias[i+j];
		}

		compress_1d(original, output, bit_budget, verbose);
		for ( size_t k = 0; k < 5; k ++ ) {
			comp_bias[cycle+k] = output->buffer[k];
		}
		if ( verbose ) printf( "Compressed to %d bits\n", output->BitCount() );

		cycle += 5;

		delete output;
	}
	cycle = 0;
	// Compressing inputs
	uint8_t* comp_inputs = (uint8_t*)malloc(sizeof(uint8_t)*comp_input_cnt*input_dim);
	for ( size_t i = 0; i < input_dim; i ++ ) {
		for ( size_t j = 0; j < input_cnt; j += 4 ) {
			BitBuffer* output = new BitBuffer(4*sizeof(float));
			for ( size_t k = 0; k < 4; k ++ ) {
				original[k] = weights[(j+k)*input_dim + i];
			}

			compress_1d(original, output, bit_budget, verbose);
			for ( size_t l = 0; l < 5; l ++ ) {
				comp_inputs[(cycle+l)*input_dim + i] = output->buffer[l];
			}
			if ( verbose ) printf( "Compressed to %d bits\n", output->BitCount() );
		
			cycle += 5;
	
			delete output;
		}
		cycle = 0;
	}
	//Compressing values that are for bias calculation
	float* add = (float*)malloc(sizeof(float)*output_dim);
	uint8_t* comp_add = (uint8_t*)malloc(sizeof(uint8_t)*comp_output_dim);
	for ( size_t i = 0; i < output_dim; i ++ ) add[i] = 1;
	for ( size_t i = 0; i < output_dim; i += 4 ) {
		BitBuffer* output = new BitBuffer(4*sizeof(float));
		for ( size_t j = 0; j < 4; j ++ ) {
			original[j] = add[i+j];
		}

		compress_1d(original, output, bit_budget, verbose);
		for ( size_t k = 0; k < 5; k ++ ) {
			comp_add[cycle+k] = output->buffer[k];
		}
		if ( verbose ) printf( "Compressed to %d bits\n", output->BitCount() );

		cycle += 5;

		delete output;
	}
	cycle = 0;

	nn_fc(comp_weights, comp_bias, comp_inputs, comp_add, input_cnt, input_dim, output_dim, outputs);
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
