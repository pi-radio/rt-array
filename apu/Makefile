.PHONY: bin clean uclean

bin:
	petalinux-package --force --boot --bif convert.bif -o mts.bit.bin

clean:
	rm -f *.jou *.log *.str

uclean:
	rm -rf build/ images/ components/