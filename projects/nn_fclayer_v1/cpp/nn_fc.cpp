#include "nn_fc.h"

extern void send_weight(uint8_t data);
extern void send_input(uint8_t data, int input_idx);
extern FC_Result recv_result();


void nn_fc(uint8_t* comp_weights, uint8_t* comp_inputs, size_t input_cnt, size_t input_dim, size_t output_dim, float* answer) {

	size_t done_cnt = 0;

	size_t comp_buffer_size = 5;
	size_t comp_input_cnt = (input_cnt/4)*comp_buffer_size;
	size_t comp_output_dim = (output_dim/4)*comp_buffer_size;

	size_t pe_ways = 8;
	// Send compressed weights
	for ( size_t i = 0; i < input_dim; i++ ) {
		for ( size_t j = 0; j < comp_output_dim/pe_ways; j++ ) {
			for ( size_t k = 0; k < pe_ways; k++ ) {
				send_weight(comp_weights[((j*pe_ways+k)*input_dim) + i]);
			}
		}
	}
	// Send compressed inputs
	size_t parallel_rows = comp_input_cnt;
	for ( size_t i = 0; i < comp_input_cnt/parallel_rows; i++ ) {
		for ( size_t j = 0; j < input_dim; j++ ) {
			for ( size_t k = 0; k < parallel_rows; k++ ) {
				send_input(comp_inputs[((i*parallel_rows)+k)*input_dim + j], ((i*parallel_rows)+k));
			}
		}		
			
		FC_Result res = recv_result();
		while (res.valid) {
			int idx = res.input_idx*output_dim + res.output_idx;
			answer[idx] = res.value;
			done_cnt++;
			printf( "Writing %f to mem %d <%d,%d> (%d)\n", res.value, idx, res.input_idx, res.output_idx, done_cnt );
			fflush(stdout);
			res = recv_result();	
		}
	}

	printf( "Finished sending all data\n" );
	fflush(stdout);

	while (done_cnt < output_dim*input_cnt) {
		FC_Result res = recv_result();
		if ( !res.valid ) continue;

		int idx = res.input_idx*output_dim + res.output_idx;
		answer[idx] = res.value;
		//printf( "Writing %f to mem %d <%d,%d> (%d)\n", res.value, idx, res.input_idx, res.output_idx, done_cnt );
		fflush(stdout);
		done_cnt++;
		//printf( "done cnt: %d\n", done_cnt );
	}

}
