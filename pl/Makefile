.PHONY: vivado clean uclean

vivado:
	vivado -mode batch -source scripts/create_project.tcl -nolog -nojournal

clean:
	rm -f *.jou *.log *.str

uclean:
	rm -rf project/