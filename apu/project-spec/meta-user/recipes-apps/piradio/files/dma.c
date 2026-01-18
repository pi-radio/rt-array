#include "piradio.h"

struct dma_state_t dma_state = {0};

// DMA helper functions
static inline void dma_write_reg(uint32_t offset, uint32_t value, uint8_t is_tx)
{
    if(is_tx) {
        dma_state.tx_dma_regs[offset >> 2] = value;
    } else {
        dma_state.rx_dma_regs[offset >> 2] = value;
    }  
}

static inline uint32_t dma_read_reg(uint32_t offset, uint8_t is_tx)
{
    if(is_tx) {
        return dma_state.tx_dma_regs[offset >> 2];
    } else {
        return dma_state.rx_dma_regs[offset >> 2];
    }
}

int dma_init(void)
{
    printf("Initializing DMA...\n");
    
    // Open /dev/mem
    dma_state.mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (dma_state.mem_fd < 0) {
        perror("Failed to open /dev/mem for DMA");
        return -1;
    }
    
    dma_state.tx_dma_regs = (volatile uint32_t *)mmap(NULL, FIR_TX_DMA_MAP_SIZE,
                                                     PROT_READ | PROT_WRITE,
                                                     MAP_SHARED,
                                                     dma_state.mem_fd,
                                                     FIR_TX_DMA_BASE_ADDR);
    if (dma_state.tx_dma_regs == MAP_FAILED) {
        perror("Failed to mmap DMA registers");
        close(dma_state.mem_fd);
        return -1;
    }

    dma_state.rx_dma_regs = (volatile uint32_t *)mmap(NULL, FIR_RX_DMA_MAP_SIZE,
                                                     PROT_READ | PROT_WRITE,
                                                     MAP_SHARED,
                                                     dma_state.mem_fd,
                                                     FIR_RX_DMA_BASE_ADDR);
    if (dma_state.rx_dma_regs == MAP_FAILED) {
        perror("Failed to mmap DMA registers");
        close(dma_state.mem_fd);
        return -1;
    }
        
    // map FIR coeffs buffer
    dma_state.fir_buffer_phys = FIR_BUFFER_BASE;
    dma_state.fir_buffer = (volatile uint32_t *)mmap(NULL, FIR_BUFFER_SIZE,
                                                       PROT_READ | PROT_WRITE,
                                                       MAP_SHARED,
                                                       dma_state.mem_fd,
                                                       (off_t)dma_state.fir_buffer_phys);
    if (dma_state.fir_buffer == MAP_FAILED) {
        perror("Failed to mmap FIR buffer");
        munmap((void*)dma_state.tx_dma_regs, FIR_TX_DMA_MAP_SIZE);
        close(dma_state.mem_fd);
        return -1;
    }
    
    printf("  DMA registers mapped at %p\n", (void*)dma_state.tx_dma_regs);
    printf("  FIR buffer mapped at %p (phys: 0x%llx)\n", 
           (void*)dma_state.fir_buffer, 
           (unsigned long long)dma_state.fir_buffer_phys);
    
    // Reset DMA
    dma_write_reg(MM2S_CONTROL_REGISTER, RESET_DMA);
    usleep(100);
    
    // check if DMA is responding
    uint32_t status = dma_read_reg(MM2S_STATUS_REGISTER);
    printf("  DMA status after reset: 0x%08x\n", status);
    
    if (status == 0xFFFFFFFF || status == 0x00000000) {
        printf("  WARNING: DMA not responding! check hardware.\n");
        // Continue anyway, might work
    }
    
    dma_state.initialized = true;
    printf("DMA initialization complete\n\n");
    
    return 0;
}

// check DMA status
void dma_print_status(void)
{
    uint32_t status = dma_read_reg(MM2S_STATUS_REGISTER);
    printf("DMA Status: 0x%08x - ", status);
    
    if (status & STATUS_HALTED) printf("HALTED ");
    else printf("RUNNING ");
    
    if (status & STATUS_IDLE) printf("| IDLE ");
    if (status & STATUS_DMA_INTERNAL_ERR) printf("| INT_ERR ");
    if (status & STATUS_DMA_SLAVE_ERR) printf("| SLV_ERR ");
    if (status & STATUS_DMA_DECODE_ERR) printf("| DEC_ERR ");
    if (status & STATUS_IOC_IRQ) printf("| IOC_IRQ ");
    if (status & STATUS_ERR_IRQ) printf("| ERR_IRQ ");
    
    printf("\n");
}

// trigger DMA transfer
int dma_transfer(uint64_t src_addr, uint32_t length)
{
    if (!dma_state.initialized) {
        printf("ERROR: DMA not initialized\n");
        return -1;
    }
    
    printf("Starting DMA transfer:\n");
    printf("  Source: 0x%llx\n", (unsigned long long)src_addr);
    printf("  Length: %u bytes\n", length);
    
    // Reset DMA
    dma_write_reg(MM2S_CONTROL_REGISTER, RESET_DMA);
    usleep(100);
    dma_print_status();

    // dma_write_reg(MM2S_CONTROL_REGISTER, ENABLE_ALL_IRQ);
    dma_write_reg(MM2S_CONTROL_REGISTER, RUN_DMA);
    
    // write source address (64-bit)
    uint32_t addr_low = (uint32_t)(src_addr & 0xFFFFFFFF);
    uint32_t addr_high = (uint32_t)(src_addr >> 32);
    
    dma_write_reg(MM2S_SRC_ADDRESS_REGISTER, addr_low);
    dma_write_reg(MM2S_SRC_ADDRESS_MSB, addr_high);
    
    printf("  Address written: 0x%08x%08x\n", addr_high, addr_low);
    
    // start transfer by writing length
    dma_write_reg(MM2S_TRNSFR_LENGTH_REGISTER, length);
    
    // wait for completion with timeout
    int timeout = 10000;  // 10 seconds
    bool completed = false;
    bool error = false;
    
    while (timeout > 0) {
        uint32_t status = dma_read_reg(MM2S_STATUS_REGISTER);
        
        // check for errors
        if (status & (STATUS_DMA_INTERNAL_ERR | STATUS_DMA_SLAVE_ERR | STATUS_DMA_DECODE_ERR)) {
            printf("  ERROR: DMA error detected!\n");
            dma_print_status();
            error = true;
            break;
        }
        
        // check for completion
        if (status & IDLE_FLAG) {
            printf("  Transfer completed successfully\n");
            completed = true;
            break;
        }
        
        usleep(1000);  // 1ms
        timeout--;
    }
    
    if (!completed && !error) {
        printf("  ERROR: Transfer timeout\n");
        dma_print_status();
        return -1;
    }
    
    if (error) {
        return -1;
    }
    
    return 0;
}

// parse coeffs from hex string
// todo: can send 4 characters per coeff instead of 8
int parse_fir_coefficients(const char *hex_data, uint32_t *num_coeffs)
{
    if (!dma_state.initialized) {
        printf("ERROR: DMA not initialized\n");
        return -1;
    }
    
    size_t hex_len = strlen(hex_data);
    
    // each coefficient is 8 hex characters (32 bits)
    if (hex_len % 8 != 0) {
        printf("ERROR: Invalid hex data length (%zu). Must be multiple of 8.\n", hex_len);
        return -1;
    }
    
    *num_coeffs = hex_len / 8;
    
    if (*num_coeffs * 4 > FIR_BUFFER_SIZE) {
        printf("ERROR: Too many coefficients (%u). Max is %u.\n", 
               *num_coeffs, FIR_BUFFER_SIZE / 4);
        return -1;
    }
    
    printf("Parsing %u FIR coefficients...\n", *num_coeffs);
    
    // parse and store
    for (uint32_t i = 0; i < *num_coeffs; i++) {
        char coeff_str[9];
        memcpy(coeff_str, &hex_data[i * 8], 8);
        coeff_str[8] = '\0';
        
        uint32_t coeff_value = (uint32_t)strtoul(coeff_str, NULL, 16);
        dma_state.fir_buffer[i] = coeff_value;
        
        if (i < 4 || i >= *num_coeffs - 4) {
            printf("  Coeff[%u] = 0x%08x\n", i, coeff_value);
            if (i == 3 && *num_coeffs > 8) {
                printf("  ...\n");
            }
        }
    }
    
    if(*num_coeffs == FIR_FRACTIONAL_NTAPS || *num_coeffs == FIR_GAINCORRECTION_NTAPS) {
        dma_state.fir_data_size = *num_coeffs * 4;  // bytes
        
        printf("FIR coefficients stored in buffer\n");
        return 0;
    } else {
        printf("ERROR: Unsupported number of FIR coefficients (%u). Only 33 or 51 supported.\n", *num_coeffs);
        return -1;
    }

}

void dma_cleanup(void)
{
    if (dma_state.initialized) {
        if (dma_state.fir_buffer != MAP_FAILED) {
            munmap((void*)dma_state.fir_buffer, FIR_BUFFER_SIZE);
        }
        if (dma_state.tx_dma_regs != MAP_FAILED) {
            munmap((void*)dma_state.tx_dma_regs, FIR_TX_DMA_MAP_SIZE);
        }
        if (dma_state.mem_fd >= 0) {
            close(dma_state.mem_fd);
        }
        dma_state.initialized = false;
        printf("DMA cleanup complete\n");
    }
}
