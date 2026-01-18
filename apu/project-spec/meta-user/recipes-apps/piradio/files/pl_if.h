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
#define AXI_RTCTRL_NUM_PHASES 14 // 7 + 7 for tx + rx
// FIRRELOAD offset in reg0
#define AXI_RTCTRL_FIRRELOAD_BIT 24
#define AXI_RTCTRL_FIRRELOAD_MASK (1u << AXI_RTCTRL_FIRRELOAD_BIT)

#define AXI_AXISSWITCH_TX_BASE_ADDR 0xB0080000
#define AXI_AXISSWITCH_TX_ADDR_RANGE 0xFFFF
#define AXI_AXISSWITCH_TX_MUX_OFFSET 0x40
#define AXI_AXISSWITCH_TX_NUM_FIR AXI_RTCTRL_NUMFIR

#define AXI_AXISSWITCH_RX_BASE_ADDR 0xB0080000
#define AXI_AXISSWITCH_RX_ADDR_RANGE 0xFFFF
#define AXI_AXISSWITCH_RX_MUX_OFFSET 0x40
#define AXI_AXISSWITCH_RX_NUM_FIR AXI_RTCTRL_NUMFIR

// DMA register offsets
#define MM2S_CONTROL_REGISTER       0x00
#define MM2S_STATUS_REGISTER        0x04
#define MM2S_SRC_ADDRESS_REGISTER   0x18
#define MM2S_SRC_ADDRESS_MSB        0x1C
#define MM2S_TRNSFR_LENGTH_REGISTER 0x28

// DMA status flags
#define STATUS_HALTED               0x00000001
#define STATUS_IDLE                 0x00000002
#define STATUS_DMA_INTERNAL_ERR     0x00000010
#define STATUS_DMA_SLAVE_ERR        0x00000020
#define STATUS_DMA_DECODE_ERR       0x00000040
#define STATUS_IOC_IRQ              0x00001000
#define STATUS_ERR_IRQ              0x00004000

// DMA control values
#define RESET_DMA                   0x00000004
#define RUN_DMA                     0x00000001
#define HALT_DMA                    0x00000000
#define ENABLE_ALL_IRQ              0x00007000

#define IOC_IRQ_FLAG                (1 << 12)
#define IDLE_FLAG                   (1 << 1)

#define FIR_TX_DMA_BASE_ADDR               0xB0030000
#define FIR_TX_DMA_MAP_SIZE                0x10000
#define FIR_RX_DMA_BASE_ADDR               0xB0030000
#define FIR_RX_DMA_MAP_SIZE                0x10000

#define FIR_BUFFER_BASE             0x10000000ULL // check if DDR High is accessible
#define FIR_BUFFER_SIZE             (64 * 1024)

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
uint32_t pl_axisswitch_read32(uint32_t offset, uint8_t is_tx);
void     pl_axisswitch_write32(uint32_t offset, uint32_t val, uint8_t is_tx);
void     pl_axisswitch_setidx(uint32_t idx, uint8_t is_tx);
void     pl_axisswitch_reset();
void     pl_rtctrl_init();
void     pl_rtctrl_set_firreload();

// DMA function declarations
int dma_init(void);
void dma_cleanup(void);
int dma_transfer(uint64_t src_addr, uint32_t length);
int parse_fir_coefficients(const char *hex_data, uint32_t *num_coeffs);