#include "nn_fc.h"

extern void send_weight(float data);
extern void send_input(float value, int input_idx);
extern FC_Result recv_result();


void nn_fc(float* matrix, float* input, int input_cnt, int input_dim, int output_dim, float* answer) {
	for ( int i = 0; i < output_dim; i++ ) {
		for ( int j = 0; j < input_dim; j++ ) {
			send_weight(matrix[i*input_dim + j]);
		}
	}

	int done_cnt = 0;
	for ( int i = 0; i < input_cnt; i++ ) {
		for ( int j = 0; j < output_dim; j++ ) {
			for ( int k = 0; k < input_dim; k++ ) {
				send_input(input[i*input_dim + k], i);
			}

			FC_Result res = recv_result();
			while (res.valid) {
				answer[res.input_idx*output_dim + res.output_idx] = res.value;
				done_cnt++;
				res = recv_result();
			}
		}
	}
	while (done_cnt < output_dim*input_cnt) {
		FC_Result res = recv_result();
		if ( !res.valid ) continue;

		answer[res.input_idx*output_dim + res.output_idx] = res.value;
		done_cnt++;
	}

}
