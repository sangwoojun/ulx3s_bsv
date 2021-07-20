ROOTDIR=../../../
BSVPATH=$(ROOTDIR)/src/
CPPPATH=$(BSVPATH)/cpp/


all: $(wildcard *.cpp) $(wildcard *.h) $(wildcard $(CPPPATH)/*.cpp) $(wildcard $(CPPPATH)/*.h) $(wildcard *.bin)
	mkdir -p obj
	g++ -o obj/main $(wildcard *.cpp) $(CPPPATH)/ttyifc.cpp -lpthread -Wall -pedantic -DSYNTH
