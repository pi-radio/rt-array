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

#define PORT 8083
#define IN 0
#define OUT 1

#define FIR_FRACTIONAL_NTAPS 51
// this is a symmetric filter. Total taps = 2 * NTAPS - 1
#define FIR_GAINCORRECTION_NTAPS 26

// global DMA state
struct dma_state_t {
    int mem_fd;
    volatile uint32_t *tx_dma_regs;
    volatile uint32_t *rx_dma_regs;
    volatile uint32_t *fir_buffer;
    uint64_t fir_buffer_phys;
    size_t fir_data_size;
    bool initialized;
};

extern struct dma_state_t dma_state;
