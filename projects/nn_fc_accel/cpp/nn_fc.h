#ifndef __NN_FC_H__
#define __NN_FC_H__

#include <stdio.h>
#include <stdint.h>

void nn_fc(uint8_t* comp_weights, uint8_t* comp_bias, uint8_t* comp_inputs, uint8_t* comp_add, size_t input_cnt, size_t input_dim, size_t output_dim, float* answer);

typedef struct {
	float value;
	int input_idx;
	int output_idx;
	bool valid;
} FC_Result;


#endif
