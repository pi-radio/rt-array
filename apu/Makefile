
BIT_FILE := ../pl/project/zcu111_rfsoc_trd.runs/impl_1/zcu111_rfsoc_trd_wrapper.bit

ifneq ($(filter bin mts.bit.bin,$(MAKECMDGOALS)),)
ifeq ($(wildcard $(BIT_FILE)),)
$(error BIT_FILE not found: $(BIT_FILE))
endif
endif

.PHONY: bin clean uclean

mts.bit.bin: ${BIT_FILE}
	cp ${BIT_FILE} .
	petalinux-package --force --boot --bif convert.bif -o mts.bit.bin

clean:
	rm -f *.jou *.log *.str
	rm -f mts.bit.bin
	rm -f zcu111_rfsoc_trd_wrapper.bit
	rm -f zcu111_rfsoc_trd_wrapper.xsa
	rm -f zcu111_rfsoc_trd_wrapper.zip

uclean:
	rm -rf build/ images/ components/

bin: mts.bit.bin