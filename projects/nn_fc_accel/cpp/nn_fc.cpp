#include "nn_fc.h"

extern void send_weight(uint8_t data);
extern void send_input(uint8_t data, int input_idx);
extern FC_Result recv_result();


void nn_fc(uint8_t* comp_weights, uint8_t* comp_bias, uint8_t* comp_inputs, uint8_t* comp_add, size_t input_cnt, size_t input_dim, size_t output_dim, float* outputs) {

	size_t done_cnt = 0;

	size_t comp_buffer_size = 5;
	size_t comp_input_cnt = (input_cnt/4)*comp_buffer_size;
	size_t comp_output_dim = (output_dim/4)*comp_buffer_size;
	
	size_t period = comp_output_dim/64;
	// Send compressed weights & bias
	for ( size_t i = 0; i < comp_output_dim/period; i++ ) {
		for ( size_t j = 0; j < input_dim; j++ ) {
			for ( size_t k = 0; k < period; k++ ) {
				send_weight(comp_weights[((i*period+k)*input_dim) + j]);
			}
		}
		for ( size_t l = (i)*period; l < (i+1)*period; l++ ) {
			send_weight(comp_bias[l]);
		}
	}
	// Send compressed inputs
	for ( size_t i = 0; i < input_dim; i++ ) {
		for ( size_t j = 0; j < comp_input_cnt; j++ ) {
			send_input(comp_inputs[j*input_dim + i], 0);
		}
	}		
	// Send compressed additional values
	for ( size_t i = 0; i < comp_output_dim; i++ ) {
		send_input(comp_add[i], 0);
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
