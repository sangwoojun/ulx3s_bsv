#ifndef __NN_FC_H__
#define __NN_FC_H__

#include <stdio.h>
#include <stdint.h>

void nn_fc(uint8_t* matrix, float* input, int input_cnt, int input_dim, int output_dim, float* answer);

typedef struct {
	float value;
	int input_idx;
	int output_idx;
	bool valid;
} FC_Result;


#endif
