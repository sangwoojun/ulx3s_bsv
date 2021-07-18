#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>


#define SDRAM_BYTES (1024*1024*32)
bool sdram_init_ready = false;
uint16_t* sdram_buffer = NULL;

extern "C" void bdpiWriteSdram(uint32_t addr, uint32_t data) {
	if ( !sdram_init_ready ) {
		sdram_buffer = (uint16_t*)malloc(SDRAM_BYTES);
		sdram_init_ready = true;
	}
	sdram_buffer[addr] = data;
}

extern "C" uint32_t bdpiReadSdram(uint32_t addr) {
	if ( !sdram_init_ready ) {
		sdram_buffer = (uint16_t*)malloc(SDRAM_BYTES);
		sdram_init_ready = true;
	}
	return sdram_buffer[addr];
}
