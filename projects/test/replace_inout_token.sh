#!/bin/bash
cat build/mkTop.v | ../../tools/bin/replacetoken ".XX_sdram_d_XX(mem_xx_inout16_XX_inout_pins)," "sdram_d," "mem_xx_inout16_XX_inout_pins" "sdram_d" > build/mkTop.v.new
mv build/mkTop.v.new build/mkTop.v



#cat build/mkTop.v | ../../tools/bin/replacetoken ".XX_sdram_d_XX(sdram_XX_sdram_d_XX)," "sdram_d," "sdram_XX_sdram_d_XX" "sdram_d" ".XX_sdram_d_XX(" ".sdram_d(" > build/mkTop.v.new
#cat build/mkUlx3sSdram.v | ../../tools/bin/replacetoken ".XX_sdram_d_XX(xx_inout16_XX_inout_pins)," "sdram_d," "xx_inout16_XX_inout_pins" "sdram_d" > build/mkUlx3sSdram.v.new
#mv build/mkUlx3sSdram.v.new build/mkUlx3sSdram.v
