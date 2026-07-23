.PHONY: vivado sim clean uclean

vivado:
	vivado -mode batch -source scripts/create_project.tcl -nolog -nojournal

sim:
	python3 srcs/tb/rt_sim.py
	vivado -mode batch -source scripts/rt_sim.tcl -nojournal -nolog

clean:
	rm -f *.jou *.log *.str

uclean:
	rm -rf project/
