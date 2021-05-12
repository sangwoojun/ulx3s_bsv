all: $(wildcard *.cpp) $(wildcard *.h)
	mkdir -p obj
	g++ -o obj/main main.cpp ttyifc.cpp -lpthread -Wall -pedantic -DSYNTH
