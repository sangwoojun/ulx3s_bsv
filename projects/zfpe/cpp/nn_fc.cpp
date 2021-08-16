#include "nn_fc.h"

extern void send_weight(float data);
extern void send_input(float data, int input_idx);
extern FC_Result recv_result();


void nn_fc(float* weights, float* bias, float* inputs, float* add, size_t input_cnt, size_t input_dim, size_t output_dim, float* outputs) {

	size_t done_cnt = 0;
	size_t period = output_dim/64;

	// Send weights & bias
	for ( size_t i = 0; i < output_dim/period; i++ ) {
		for ( size_t j = 0; j < input_dim; j++ ) {
			for ( size_t k = 0; k < period; k++ ) {
				send_weight(weights[((i*period+k)*input_dim) + j]);
			}
		}
		for ( size_t l = (i)*period; l < (i+1)*period; l++ ) {
			send_weight(bias[l]);
		}
	}
	// Send inputs
	for ( size_t i = 0; i < input_dim; i++ ) {
		for ( size_t j = 0; j < input_cnt; j++ ) {
			send_input(inputs[j*input_dim + i], 0);
		}
	}		
	// Send additional values
	for ( size_t i = 0; i < input_cnt; i++ ) {
		send_input(add[i], 0);
	}

	printf( "Finished sending all data\n" );
	fflush(stdout);

	while (done_cnt < output_dim*input_cnt) {
		FC_Result res = recv_result();
		if ( !res.valid ) continue;

		int idx = res.input_idx*output_dim + res.output_idx;
		outputs[idx] = res.value;
		//printf( "Writing %f to mem %d <%d,%d> (%zd)\n", res.value, idx, res.input_idx, res.output_idx, done_cnt );
		fflush(stdout);
		done_cnt++;
		//printf( "done cnt: %d\n", done_cnt );
	}

}
