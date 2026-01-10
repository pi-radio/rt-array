/*
* Copyright (c) 2012 Xilinx, Inc.  All rights reserved.
*
* Xilinx, Inc.
* XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS" AS A
* COURTESY TO YOU.  BY PROVIDING THIS DESIGN, CODE, OR INFORMATION AS
* ONE POSSIBLE   IMPLEMENTATION OF THIS FEATURE, APPLICATION OR
* STANDARD, XILINX IS MAKING NO REPRESENTATION THAT THIS IMPLEMENTATION
* IS FREE FROM ANY CLAIMS OF INFRINGEMENT, AND YOU ARE RESPONSIBLE
* FOR OBTAINING ANY RIGHTS YOU MAY REQUIRE FOR YOUR IMPLEMENTATION.
* XILINX EXPRESSLY DISCLAIMS ANY WARRANTY WHATSOEVER WITH RESPECT TO
* THE ADEQUACY OF THE IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO
* ANY WARRANTIES OR REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE
* FROM CLAIMS OF INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY
* AND FITNESS FOR A PARTICULAR PURPOSE.
*
*/

#include "piradio.h"

int main()
{
    int server_fd, new_socket, valread;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char command[1024] = {0};
    char response[100];
    response[0] = '\0'; // default

    int status;
    uint32_t addr, value;  
    
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    status = pl_init();
    if(status != 0) {
        perror("pl init failed\n");
    }
    
    // Initialize DMA
    if (dma_init() < 0) {
        printf("WARNING: DMA initialization failed. FIRCOEFF command will not work.\n");
    }
    
    // Creating socket file descriptor
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0)
    {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    // Forcefully attaching socket to the port 8080
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT,
                &opt, sizeof(opt)))
    {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons( PORT );

	// Forcefully attaching socket to the port 8080
	if (bind(server_fd, (struct sockaddr *)&address,
				sizeof(address))<0)
    {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }    
    if (listen(server_fd, 3) < 0)
    {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    printf("Server listening on port %d\n", PORT);
    printf("Available commands:\n");
    printf("  FIRCOEFF <idx> <hex>     - Load FIR coeffs (idx 0-13) and trigger DMA\n");
    printf("  RTCTRL <addr> <val>      - Write to RTCTRL registers\n");
    printf("  +<read> <skip> <nbytes>  - TFLOW command\n");
    printf("  <8_hex_chars>            - SPI command\n");
    printf("  disconnect               - Close connection\n\n");

    // Main loop that process the data comming in the TCP port
    while(1)
    {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address,
                        (socklen_t*)&addrlen))<0)
        {
            perror("accept");
            exit(EXIT_FAILURE);
        }
        printf("New server socket opened\n");

        bool done = 0;
        while(done == 0)
        {
            usleep(10);
            strcpy(command, "");
            valread = read(new_socket, command, 1024);

            if(valread == 0) {
                printf("client disconnected\n");
                break;
            }
            // ensures loop exists if server quits w/o sending disconnect
            if(valread < 0) {
                perror("read");
                break;
            }
            command[valread] = '\0';

            // if (valread <= 0)
            //     continue;

            printf("Received cmd of length %u:%s\n", (unsigned int)(strlen(command)), command);

            if (strcmp(command, "disconnect") == 0)
            {
                strcpy(response, "disconnect\r\n");
                done = 1;
            }            
            else if (strncmp(command, "FIRCOEFF ", 9) == 0)
            {
                char *args = command + 9;
                char *endptr;
                
                unsigned long fir_index = strtoul(args, &endptr, 10);
                
                if (args == endptr) {
                    strcpy(response, "Error: Missing FIR index\r\n");
                } else if (fir_index > 13) {
                    strcpy(response, "Error: Invalid FIR index\r\n");
                } else {
                    // Skip whitespace to get to hex data
                    while (*endptr && isspace(*endptr)) endptr++;
                    char *hex_data = endptr;
                    
                    // Remove any trailing whitespace/newlines
                    size_t len = strlen(hex_data);
                    while (len > 0 && isspace(hex_data[len-1])) {
                        hex_data[len-1] = '\0';
                        len--;
                    }
                    
                    if (strlen(hex_data) == 0) {
                        strcpy(response, "Error: Missing hex data\r\n");
                    } else {
                        printf("Processing FIRCOEFF command (Index: %lu) with %zu hex chars\n", 
                               fir_index, strlen(hex_data));
                        
                        uint32_t num_coeffs = 0;
                        if (parse_fir_coefficients(hex_data, &num_coeffs) == 0) {
                            // COnfigure the switch to fir index
                            pl_axisswitch_setidx(fir_index);
                            // Trigger DMA transfer
                            uint32_t transfer_size = dma_state.fir_data_size;
                            
                            if (dma_transfer(dma_state.fir_buffer_phys, transfer_size) == 0) {
                                strcpy(response, "OK\r\n");                                
                            } else {
                                strcpy(response, "Error: DMA transfer failed\r\n");
                            }
                        } else {
                            strcpy(response, "Error: failed to parse fir coeffs\r\n");
                        }
                    }
                }
            }
            else
            {
                if ((strlen(command) == 8) && (command[0] != '+'))
                {
                    // We have received an SPI command
                    unsigned int val = 0;
					for (int i = 0; i < 8; i++)
					{
						unsigned int a = (unsigned int)command[i];
						if ((a >= 48) && (a <=57))
							a = a-48;
						else if ((a >= 65) && (a <= 70))
							a = a-55;
						else if ((a >= 97) && (a <= 102))
							a = a-87;
						else
							printf("Received garbage!");

						int k = (7-i)*4;
						val = val + (a << k);
					}
                    printf("SPI command: %08x\n", val);    
                    pl_spi_write32(0, val);
                    
                    strcpy(response, "OK\r\n");
                }

                if (command[0] == '+')
                {
					char * cmd =  strtok(command, " ");
					cmd = strtok(NULL," ");
					int read = atoi(cmd);
					cmd = strtok(NULL," ");                    
					int skip = atoi(cmd);
					cmd = strtok(NULL," ");
					int nbytes = atoi(cmd);

                    pl_tflow_write32(0, read);
                    pl_tflow_write32(4, skip);
                    pl_tflow_write32(8, nbytes);

                    printf("TFLOW R0 = %08x\n", pl_tflow_read32(0));
                    printf("TFLOW R1 = %08x\n", pl_tflow_read32(4));
                    printf("TFLOW R2 = %08x\n", pl_tflow_read32(8));
                    
                    strcpy(response, "OK\r\n");
                }
                
                // RTCTRL command format: RTCTRL <addr> <val>
                if (sscanf(command, "RTCTRL %x %x", &addr, &value) == 2)
                {
                    if((addr >= AXI_RTCTRL_MAX_OFFSET) & (addr & 0x3)) {
                        strcpy(response, "Error: RTCTRL addr out of bounds\r\n");
                    } else {
                        if(addr == 0) {
                            // expected flow when switching to correction mode:
                            // send fir coeffs
                            // configure phases if required
                            // set the rtctrl reg0 - this will calling set firreload separately
                            uint8_t opmode = value & 0xFF;
                            uint8_t txrxmode = (value >> 8) & 0xFF;
                            uint8_t firreload = (value >> 24) & 0xFF;
                            printf("Configuring RTCTRL[0]: OPMODE: %u, TXRXMODE: %u, FIRRELOAD: %u\n", opmode, txrxmode, firreload);
                        }
                        pl_rtctrl_write32(addr, value);
                        printf("RTCTRL %08x = %08x\n", addr, pl_rtctrl_read32(addr));
                        strcpy(response, "OK\r\n"); 
                    }
                }
            }

            send(new_socket, response, strlen(response), 0);
            printf("Response sent: %s\n", response);

            if (done)
            {
                printf("Closing the server socket\n");
                close(new_socket);
            }
        }
    }
    
    // will probably never reach here
    dma_cleanup();
    return 0;
}