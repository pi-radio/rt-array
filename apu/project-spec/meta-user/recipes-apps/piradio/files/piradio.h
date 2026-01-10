#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <string.h>
#include <ctype.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdint.h>
#include "pl_if.h"

// DMA function declarations
int dma_init(void);
void dma_cleanup(void);
int dma_transfer(uint64_t src_addr, uint32_t length);
int parse_fir_coefficients(const char *hex_data, uint32_t *num_coeffs);

#define PORT 8083
#define IN 0
#define OUT 1

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

#define DMA_BASE_ADDR               0xB0030000
#define DMA_MAP_SIZE                0x10000
#define FIR_BUFFER_BASE             0x10000000ULL // check if DDR High is accessible
#define FIR_BUFFER_SIZE             (64 * 1024)

#define FIR_FRACTIONAL_NTAPS 51
// this is a symmetric filter. Total taps = 2 * NTAPS - 1
#define FIR_GAINCORRECTION_NTAPS 26

// global DMA state
struct dma_state_t {
    int mem_fd;
    volatile uint32_t *dma_regs;
    volatile uint32_t *fir_buffer;
    uint64_t fir_buffer_phys;
    size_t fir_data_size;
    bool initialized;
};

extern struct dma_state_t dma_state;
