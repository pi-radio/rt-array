#include "pl_if.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>

static int mem_fd = -1;

static volatile uint8_t *tflow_base;
static volatile uint8_t *spi_base;
static volatile uint8_t *rtctrl_base;
static volatile uint8_t *axisswitch_tx_base;
static volatile uint8_t *axisswitch_rx_base;

int pl_init(void)
{
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) {
        perror("open /dev/mem");
        return -1;
    }

    tflow_base = mmap(NULL, AXI_TFLOW_ADDR_RANGE,
                      PROT_READ | PROT_WRITE,
                      MAP_SHARED,
                      mem_fd, AXI_TFLOW_BASE_ADDR);

    if (tflow_base == MAP_FAILED) {
        perror("mmap tflow");
        return -1;
    }

    spi_base = mmap(NULL, AXI_SPI_ADDR_RANGE,
                    PROT_READ | PROT_WRITE,
                    MAP_SHARED,
                    mem_fd, AXI_SPI_BASE_ADDR);

    if (spi_base == MAP_FAILED) {
        perror("mmap spi");
        return -1;
    }

    rtctrl_base = mmap(NULL, AXI_RTCTRL_ADDR_RANGE,
                    PROT_READ | PROT_WRITE,
                    MAP_SHARED,
                    mem_fd, AXI_RTCTRL_BASE_ADDR);

    if (rtctrl_base == MAP_FAILED) {
        perror("mmap rtctrl");
        return -1;
    }

    axisswitch_tx_base = mmap(NULL, AXI_AXISSWITCH_TX_ADDR_RANGE,
                    PROT_READ | PROT_WRITE,
                    MAP_SHARED,
                    mem_fd, AXI_AXISSWITCH_TX_BASE_ADDR);

    if (axisswitch_tx_base == MAP_FAILED) {
        perror("mmap axis switch");
        return -1;
    }

    axisswitch_rx_base = mmap(NULL, AXI_AXISSWITCH_RX_ADDR_RANGE,
                    PROT_READ | PROT_WRITE,
                    MAP_SHARED,
                    mem_fd, AXI_AXISSWITCH_RX_BASE_ADDR);

    if (axisswitch_rx_base == MAP_FAILED) {
        perror("mmap axis switch");
        return -1;
    }
        
    // read check and reset phase factors
    pl_rtctrl_init();
    // reset all routes on startup
    pl_axisswitch_reset();
    return 0;
}

void pl_deinit(void)
{
    if (tflow_base)
        munmap((void *)tflow_base, AXI_TFLOW_ADDR_RANGE);
    if (spi_base)
        munmap((void *)spi_base, AXI_SPI_ADDR_RANGE);
    if (rtctrl_base)
        munmap((void *)rtctrl_base, AXI_RTCTRL_ADDR_RANGE);
    if (axisswitch_tx_base)
        munmap((void *)axisswitch_tx_base, AXI_AXISSWITCH_TX_ADDR_RANGE);       
    if (axisswitch_rx_base)
        munmap((void *)axisswitch_rx_base, AXI_AXISSWITCH_RX_ADDR_RANGE);      
    if (mem_fd >= 0)
        close(mem_fd);
}

uint32_t pl_tflow_read32(uint32_t offset)
{
    return *(volatile uint32_t *)(tflow_base + offset);
}

void pl_tflow_write32(uint32_t offset, uint32_t val)
{
    *(volatile uint32_t *)(tflow_base + offset) = val;
}

uint32_t pl_spi_read32(uint32_t offset)
{
    return *(volatile uint32_t *)(spi_base + offset);
}

void pl_spi_write32(uint32_t offset, uint32_t val)
{
    *(volatile uint32_t *)(spi_base + offset) = val;
}

uint32_t pl_rtctrl_read32(uint32_t offset)
{
    return *(volatile uint32_t *)(rtctrl_base + offset);
}

void pl_rtctrl_write32(uint32_t offset, uint32_t val)
{
    *(volatile uint32_t *)(rtctrl_base + offset) = val;
}

void pl_rtctrl_init() {
    uint32_t wdata; // 1.0 in Q1.15
    uint32_t rdata;

    wdata = 0x00000000;
    pl_rtctrl_write32(0, wdata);
    
    // init all phase factors to 1.0
    wdata = 0x00007FFF;
    for(int i = 0; i < AXI_RTCTRL_NUM_PHASES; i++) {
        pl_rtctrl_write32(AXI_RTCTRL_PHASE_OFFSET + 4*i, wdata);
    }
    
    // readback - not required, but just a safety check
    rdata = pl_rtctrl_read32(0);
    if(rdata != 0) {
        printf("WARNING: rtctrl reg0 not set correctly. Value = %x\n", rdata);
    }

    for(int i = 0; i < AXI_RTCTRL_NUM_PHASES; i++) {
        rdata = pl_rtctrl_read32(AXI_RTCTRL_PHASE_OFFSET + 4*i);
        if(rdata != 0x00007FFF) {
            printf("WANRING: rtctrl phase reg %d readback failed! Value = %x\n", i, rdata);
        }
    }
}

void pl_rtctrl_set_firreload() {
    uint32_t rdata;    
    rdata = pl_rtctrl_read32(0);
    
    // this is a self clearing bit: safety check
    if(rdata & AXI_RTCTRL_FIRRELOAD_MASK) {
        printf("WARNING: previous FIRRELOAD not cleared\n");
    }

    rdata |= AXI_RTCTRL_FIRRELOAD_MASK;
    pl_rtctrl_write32(0, rdata);
}

uint32_t pl_axisswitch_read32(uint32_t offset, uint8_t is_tx)
{
    if(is_tx) {
        return *(volatile uint32_t *)(axisswitch_tx_base + offset);
    } else {
        return *(volatile uint32_t *)(axisswitch_rx_base + offset);
    }
}

void pl_axisswitch_write32(uint32_t offset, uint32_t val, uint8_t is_tx)
{
    if(is_tx) {
        *(volatile uint32_t *)(axisswitch_tx_base + offset) = val;
    } else {
        *(volatile uint32_t *)(axisswitch_rx_base + offset) = val;
    }
}

// 0x00000000 to enable
// 0x80000000 to disble
void pl_axisswitch_setidx(uint32_t idx, uint8_t is_tx) {
    // this is assuming we send all coeffs from host every time we want to reload
    if(idx > 0) {
        // disable previous route
        pl_axisswitch_write32(AXISSWITCH_MUX_OFFSET + 4*(idx - 1), 0x80000000, is_tx);    
    }
    // enable this route
    pl_axisswitch_write32(AXISSWITCH_MUX_OFFSET + 4*idx, 0x00000000, is_tx);

    // load above config (self clearing)
    pl_axisswitch_write32(0, 0x00000002, is_tx);
}

void pl_axisswitch_reset() {
    uint32_t addr;
    uint32_t wdata = 0x80000000;
    // disable all routes
    for(int i = 0; i < AXISWITCH_NUM_FIR; i++) {
        pl_axisswitch_write32(AXISSWITCH_MUX_OFFSET + 4*i, wdata, 0); // rx reset
        pl_axisswitch_write32(AXISSWITCH_MUX_OFFSET + 4*i, wdata, 1); // tx reset
    }
}
