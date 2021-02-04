ROOTDIR=../../

BSCFLAGS = -show-schedule -show-range-conflict -aggressive-conditions 
BUILD_DIR=./build/
BSIM_DIR=./bsim/
BSVPATH=$(ROOTDIR)/src/
BSVPATH_ALL=$(BSVPATH):./processor

BSCFLAGS_SYNTH = -bdir $(BUILD_DIR) -vdir $(BUILD_DIR) -simdir $(BUILD_DIR) -info-dir $(BUILD_DIR) -fdir $(BUILD_DIR)

BSCFLAGS_BSIM = -bdir $(BSIM_DIR) -vdir $(BSIM_DIR) -simdir $(BSIM_DIR) -info-dir $(BSIM_DIR) -fdir $(BSIM_DIR) -D BSIM -l pthread

BSIM_CPPFILES= ./cpp/main.cpp
#$(ROOTDIR)/cpp/PcieBdpi.cpp \
	$(ROOTDIR)/cpp/ShmFifo.cpp

all: Top.bsv $(wildcard $(BSVPATH)/*.bsv) $(wildcard processor/*.bsv) cpp/main.cpp
	rm -rf build
	mkdir -p build
	cd $(BUILD_DIR); apio init -b ulx3s-85f -p .
	bsc  $(BSCFLAGS) $(BSCFLAGS_SYNTH) -remove-dollar -p +:$(BSVPATH_ALL) -verilog -u -g mkTop ./Top.bsv 
	#cp verilog/*.v build
	cp $(BSVPATH)/*.lpf build
	cp $(BSVPATH)/bsv_verilog/*.v build 
	cd build; apio verify 
	cd build; apio build -v

bsim: Top.bsv $(wildcard $(BSVPATH)/*.bsv) $(wildcard processor/*.bsv) cpp/main.cpp
	mkdir -p $(BSIM_DIR)
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -p +:$(BSVPATH_ALL) -sim -u -g mkTop_bsim ./Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -sim -e mkTop_bsim -o $(BSIM_DIR)/bsim $(BSIM_DIR)/*.ba $(BSIM_CPPFILES)

runsim: bsim
	./bsim/bsim 2> output.log | tee system.log

program:
	cd build; apio upload

clean:
	rm -rf build
	rm -rf bsim

