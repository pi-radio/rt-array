#pragma once
#include <stdint.h>

#define AXI_TFLOW_BASE_ADDR 0xB0020000
#define AXI_TFLOW_ADDR_RANGE 0x0FFF

#define AXI_SPI_BASE_ADDR 0xB0010000
#define AXI_SPI_ADDR_RANGE 0xFFFF

// cross check with dtsi
#define AXI_RTCTRL_BASE_ADDR 0xB0000000
#define AXI_RTCTRL_ADDR_RANGE 0x0FFF

#define AXI_RTCTRL_NUM_REGS 8
#define AXI_RTCTRL_MAX_OFFSET (AXI_RTCTRL_NUM_REGS * 4)
// number of parallel processing channels
#define AXI_RTCTRL_NCH 7
#define AXI_RTCTRL_NUMFIR (AXI_RTCTRL_NCH * 2)
#define AXI_RTCTRL_PHASE_OFFSET 0x4
// FIRRELOAD offset in reg0
#define AXI_RTCTRL_FIRRELOAD_BIT 24
#define AXI_RTCTRL_FIRRELOAD_MASK (1u << AXI_RTCTRL_FIRRELOAD_BIT)

#define AXI_AXISSWITCH_BASE_ADDR 0xB0080000
#define AXI_AXISSWITCH_ADDR_RANGE 0xFFFF
#define AXISSWITCH_MUX_OFFSET 0x40

/* Init / deinit */
int  pl_init(void);
void pl_deinit(void);

/* TFLOW block */
uint32_t pl_tflow_read32(uint32_t offset);
void     pl_tflow_write32(uint32_t offset, uint32_t val);

/* SPI block */
uint32_t pl_spi_read32(uint32_t offset);
void     pl_spi_write32(uint32_t offset, uint32_t val);

/* RT CTRL block */
uint32_t pl_rtctrl_read32(uint32_t offset);
void     pl_rtctrl_write32(uint32_t offset, uint32_t val);

/* AXIS Switch block */
uint32_t pl_axisswitch_read32(uint32_t offset);
void     pl_axisswitch_write32(uint32_t offset, uint32_t val);
void     pl_axisswitch_setidx(uint32_t idx);
void     pl_axisswitch_reset();
void     pl_rtctrl_init();
void     pl_rtctrl_set_firreload();