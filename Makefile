MODE ?= mode0
FILE ?= trace_punit

all: work_dir build run

work_dir:	
	vlib work
	vmap work work

build:
ifeq ($(MODE), mode2)
	vlog +define+mode2 cache.sv
else ifeq ($(MODE), mode1)
	vlog +define+mode1 cache.sv
else
	vlog +define+mode0 cache.sv
endif

run:
	vsim -c -novopt -G Tracefile="$(FILE)" -do "run -all" cache

clean:
	rm -rf work modelsim.ini
