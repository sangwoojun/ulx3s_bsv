#include "nn_fc.h"

extern void send_weight(uint8_t data);
extern void send_input(float value, int input_idx);
extern FC_Result recv_result();


void nn_fc(uint8_t* matrix, float* input, int input_cnt, int input_dim, int output_dim, float* answer) {

	int pe_ways = 8;
	
	for ( int i = 0; i < input_dim; i++ ) {
		for ( int j = 0; j < 80/pe_ways; j++ ) {
			for ( int k = 0; k < pe_ways; k++ ) {
				send_weight(matrix[((j*pe_ways+k)*input_dim) + i]);
			}
		}
	}

	int done_cnt = 0;
	int parallel_rows = 64;
	for ( int i = 0; i < input_cnt/parallel_rows; i++ ) {
		for ( int j = 0; j < input_dim; j++ ) {
			for ( int k = 0; k < parallel_rows; k++ ) {
				send_input(input[(i*64+k)*input_dim + j], (i*64+k));
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
