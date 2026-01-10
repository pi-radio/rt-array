/******************************************************************************
 *
 * Copyright (C) 2018 Xilinx, Inc.  All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Use of the Software is limited solely to applications:
 * (a) running on a Xilinx device, or
 * (b) that interact with a Xilinx device through a bus or interconnect.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
 * OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Except as contained in this notice, the name of the Xilinx shall not be used
 * in advertising or otherwise to promote the sale, use or other dealings in
 * this Software without prior written authorization from Xilinx.
 *
 ******************************************************************************/

/***************************** Include Files *********************************/
#include "data_interface.h"
#include "cmd_interface.h"
#include "error_interface.h"
#include "rfdc_interface.h"
#include <pthread.h>
#include <unistd.h>

/************************** Constant Definitions *****************************/

extern XRFdc RFdcInst; /* RFdc driver instance */
extern int enTermMode;
extern int thread_stat;

char mem_path_dac[MAX_DAC][MAX_STRLEN] = {"/dev/plmem0"};
char mem_path_adc[MAX_ADC][MAX_STRLEN] = {"/dev/plmem8"};
char mem_type_path_dac[MAX_DAC][MAX_STRLEN] = {"/sys/class/plmem/plmem0/device/select_mem"};
char mem_type_path_adc[MAX_ADC][MAX_STRLEN] = {"/sys/class/plmem/plmem8/device/select_mem"};
char bram_ddr_path_dac[MAX_DAC][MAX_STRLEN] = {"/sys/class/plmem/plmem0/device/mem_type"};
char bram_ddr_path_adc[MAX_ADC][MAX_STRLEN] = {"/sys/class/plmem/plmem8/device/mem_type"};

/*
 * GPIO mapping notes:
 * - Updated GPIO mapping since the gpiochip base is 334 (not 338).
 * - Only the following EMIO pins are connected in the design:
 *     EMIO 0, 2, 3, 32, 34  → GPIO 412, 414, 415, 444, 446
 *
 * - GPIO 476 (EMIO64) is used for DAC select and GPIO 492 (EMIO80) for ADC select.
 *   This is consistent with the design, which has a single DAC and ADC DMA block
 *   (unlike the reference design that has 8 of each), so no additional selection
 *   logic is required.
 *
 * - The purpose of the IQ GPIO is currently unclear.
 *
 * - GPIO 480 and 496 (used for multi-tile control) are unconnected, including in
 *   the reference design.
*/

/* GPIO0,4,8,12,16,20,24,28 */
int dac_reset_gpio[MAX_DAC] = {412};

/* GPIO2,6,10,14,18,22,26,30  */
int dac_localstart_gpio[MAX_DAC] = {414};

/* GPIO2,6,10,14,18,22,26,30  */
int dac_loopback_gpio[MAX_DAC] = {415};

/* Starts from GPIO64 to GPIO67 */
int dac_select_gpio[DAC_MUX_GPIOS] = {476};

/* GPIO32,36,40,44,48,52,56,60 */
int adc_reset_gpio[MAX_ADC] = {444};

/* GPIO33,37,41,45,49,53,57,61 */
int adc_iq_gpio[MAX_ADC] = {445};

/* GPIO34,38,42,46,50,54,58,62 */
int adc_localstart_gpio[MAX_ADC] = {446};

/* Starts from GPIO80 to GPIO82 */
int adc_select_gpio[ADC_MUX_GPIOS] = {492};

#define DAC_MULTITILE_CTL_GPIO 480
#define DAC_MULTITILE_CTL_GPIO_STR "/sys/class/gpio/gpio480/"

#define ADC_MULTITILE_CTL_GPIO 496
#define ADC_MULTITILE_CTL_GPIO_STR "/sys/class/gpio/gpio496/"

struct rfsoc_info info;
pthread_mutex_t count_mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t design_lk_mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t adc_mutex = PTHREAD_MUTEX_INITIALIZER;

int init_mem()
{
  int ret;
  void *base_dac;
  void *base_adc;
  u32 max_dac = MAX_DAC;
  u32 max_adc = MAX_ADC;

  // Set memory type
  ret = write_to_file(mem_type_path_dac[0], PL_MEM);
  if (ret != SUCCESS)
  {
    printf("[init_mem] Error configuring memory\n");
    return FAIL;
  }

  // Open memory file
  info.fd_dac[0] = open(mem_path_dac[0], O_RDWR);
  if (info.fd_dac[0] < 0)
  {
    printf("[init_mem] file %s open failed\n", mem_path_dac[0]);
    return FAIL;
  }

  // Map size of memory
  info.map_dac[0] = (signed char *)mmap(0, DAC_MAP_SZ, PROT_READ | PROT_WRITE,
                                        MAP_SHARED, info.fd_dac[0], 0);
  if ((info.map_dac[0]) == MAP_FAILED)
  {
    printf("[init_mem] Error mmapping the file dac_0\r\n");
    return FAIL;
  }

  // Set memory type
  ret = write_to_file(mem_type_path_adc[0], PL_MEM);
  if (ret != SUCCESS)
  {
    printf("[init_mem] Error configuring memory\r\n");
    return FAIL;
  }

  // open memory file
  info.fd_adc[0] = open(mem_path_adc[0], O_RDWR);
  if ((info.fd_adc[0]) < 0)
  {
    printf("[init_mem] file %s open failed\r\n", mem_path_adc[0]);
    return FAIL;
  }

  // Map size of memory
  info.map_adc[0] = (signed char *)mmap(0, ADC_MAP_SZ, PROT_READ | PROT_WRITE,
                                        MAP_SHARED, info.fd_adc[0], 0);
  if ((info.map_adc[0]) == MAP_FAILED)
  {
    printf("[init_mem] Error mmapping the file adc_0\n");
    return FAIL;
  }

  return SUCCESS;
}

int deinit_path(int *fd, signed char *map, unsigned int sz)
{
  if ((*fd) != 0)
    fsync(*fd);

  if (map != NULL)
    if (munmap(map, sz) == -1)
      printf("[deinit_path] unmap failed\n");

  if ((*fd) != 0)
  {
    close(*fd);
    *fd = 0;
  }
}

int deinit_mem(void)
{
  int ret;

  ret = write_to_file(mem_type_path_dac[0], NO_MEM);
  if (ret != SUCCESS)
    printf("[deinit_mem] Error configuring dac memory: DAC mem index: 0\n");

  ret = write_to_file(bram_ddr_path_dac[0], BRAM);
  if (ret != SUCCESS)
    printf("[deinit_mem] Error configuring dac memory: DAC mem index: 0\n");

  deinit_path(&info.fd_dac[0], info.map_dac[0], DAC_MAP_SZ);

  ret = write_to_file(mem_type_path_adc[0], NO_MEM);
  if (ret != SUCCESS) 
    printf("[deinit_mem] Error configuring ADC memory: ADC mem index: 0\r\n");

  ret = write_to_file(bram_ddr_path_adc[0], BRAM);
  if (ret != SUCCESS)
    printf("[deinit_mem] Error configuring dac mem type:  mem index: 0\n");

  deinit_path(&info.fd_adc[0], info.map_adc[0], ADC_MAP_SZ);
}

int init_gpio()
{
  int ret;

  /*
   * GPIO initialization for D/A Converter
   */

  // Enable/Export reset GPIO
  ret = enable_gpio(dac_reset_gpio[0]);
  if (ret)
  {
    printf("cUnable to enable reset GPIO\r\n");
    return ret;
  }
  ret = config_gpio_op(dac_reset_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for reset gpio of dac\r\n");
    return ret;
  }

  // Enable/Export localstart GPIO
  ret = enable_gpio(dac_localstart_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to enable localstart gpio of dac\r\n");
    return ret;
  }
  ret = config_gpio_op(dac_localstart_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for localstart of dac\r\n");
    return ret;
  }
  
  // Enable/Export localstart GPIO
  ret = enable_gpio(dac_loopback_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to enable loopback gpio of dac\r\n");
    return ret;
  }
  ret = config_gpio_op(dac_loopback_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for loopback of dac\r\n");
    return ret;
  }

  // Enable/Export channel select GPIO
  ret = enable_gpio(dac_select_gpio[0]);
  if (ret) {
    printf("[init_gpio] Unable to enable select GPIO of dac\r\n");
    return ret;
  }  
  ret = config_gpio_op(dac_select_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for select gpio of dac\r\n");
    return ret;
  }

  // Enable/Export DAC Multi tile control GPIO
  ret = enable_gpio(DAC_MULTITILE_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to enable multitile ctrl gpio of dac\r\n");
    return ret;
  }
  ret = config_gpio_op(DAC_MULTITILE_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for multitile ctrl of dac\r\n");
    return ret;
  }

  // Enable/Export DAC SSR control GPIO
  ret = enable_gpio(DAC_SSR_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to enable SSR ctrl gpio of dac\r\n");
    return ret;
  }
  ret = config_gpio_op(DAC_SSR_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for SSR ctrl of dac\r\n");
    return ret;
  }

  /*
   * GPIO initialization for A/D Converter
   */

  // Enable/Export reset GPIO
  ret = enable_gpio(adc_reset_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to enable reset GPIO\r\n");
    return ret;
  }
  ret = config_gpio_op(adc_reset_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for reset gpio of adc\r\n");
    return ret;
  }

  // Enable/Export localstart GPIO
  ret = enable_gpio(adc_localstart_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to enable localstart gpio of adc\r\n");
    return ret;
  }
  ret = config_gpio_op(adc_localstart_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for localstart of adc\r\n");
    return ret;
  }

  // Enable/Export channel select GPIO
  ret = enable_gpio(adc_select_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to enable select GPIO of adc\r\n");
    return ret;
  }
  ret = config_gpio_op(adc_select_gpio[0]);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for select gpio of adc\r\n");
    return ret;
  }

  // Enable/Export ADC Multi tile control GPIO
  ret = enable_gpio(ADC_MULTITILE_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to enable multitile control gpio of adc\r\n");
    return ret;
  }
  ret = config_gpio_op(ADC_MULTITILE_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for multitile ctrl of adc\r\n");
    return ret;
  }

  // Enable/Export ADC SSR control GPIO
  ret = enable_gpio(ADC_SSR_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to enable SSR control gpio of adc\r\n");
    return ret;
  }
  ret = config_gpio_op(ADC_SSR_CTL_GPIO);
  if (ret)
  {
    printf("[init_gpio] Unable to set direction for SSR ctrl of adc\r\n");
    return ret;
  }

  return ret;
}

int deinit_gpio()
{
  int i, ret;
  u32 max_dac = MAX_DAC;
  u32 max_adc = MAX_ADC;

  if (info.design_type == DAC1_ADC1) {
    max_dac = 1;
    max_adc = 1;
  } else {
  }
  for (i = 0; i < max_dac; i++) {
    /* Release reset GPIO */
    ret = disable_gpio(dac_reset_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret, "Unable to release reset GPIO of dac\n");
      return ret;
    }
    /* Release localstart GPIO */
    ret = disable_gpio(dac_localstart_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret,
                               "Unable to release localstart gpio of dac\n");
      return ret;
    }
    /* Release loopback GPIO */
    ret = disable_gpio(dac_loopback_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret,
                               "Unable to release localstart gpio of dac\n");
      return ret;
    }
  }

  for (i = 0; i < DAC_MUX_GPIOS; i++) {
    /* Release channel select GPIO */
    ret = disable_gpio(dac_select_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret, "Unable to release select GPIO of dac\n");
      return ret;
    }
  }
  /* Release DAC Multitile GPIO */
  ret = disable_gpio(DAC_MULTITILE_CTL_GPIO);
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to release DAC Multitile GPIO\n");
    return ret;
  }
  /* Release DAC SSR control GPIO */
  ret = disable_gpio(DAC_SSR_CTL_GPIO);
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to release DAC SSR CTRL GPIO\n");
    return ret;
  }
  /* GPIO de-initialistion for ADC */
  for (i = 0; i < max_adc; i++) {
    /* Release reset GPIO */
    ret = disable_gpio(adc_reset_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret, "Unable to release reset GPIO of adc\n");
      return ret;
    }
    /* Release localstart GPIO */
    ret = disable_gpio(adc_localstart_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret,
                               "Unable to release localstart gpio of adc\n");
      return ret;
    }
  }

  for (i = 0; i < ADC_MUX_GPIOS; i++) {
    /* Release channel select GPIO */
    ret = disable_gpio(adc_select_gpio[i]);
    if (ret) {
      MetalLoghandler_firmware(ret, "Unable to release select GPIO of adc\n");
      return ret;
    }
  }
  /* Release ADC Multitile GPIO */
  ret = disable_gpio(ADC_MULTITILE_CTL_GPIO);
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to release ADC Multitile GPIO\n");
    return ret;
  }
  /* Release ADC SSR CTRL GPIO */
  ret = disable_gpio(ADC_SSR_CTL_GPIO);
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to release ADC SSR CTRL GPIO\n");
    return ret;
  }
}

int channel_select_gpio(int *sel_gpio_path, int val, int type)
{
  int ret;

  if (type == DAC)
  {
    // Toggle gpio64
    ret = set_gpio(dac_select_gpio[0], 0);
    if (ret)
    {
      printf("[channel_select_gpio] Unable to set dac_select_gpio\r\n");
      return ret;
    }

    usleep(10);

    ret = set_gpio(dac_select_gpio[0], 1);
    if (ret)
    {
      printf("[channel_select_gpio] Unable to set dac_select_gpio\r\n");
      return ret;
    }
  }
}

int change_fifo_stat(int fifo_id, int tile_id, int stat)
{
  int ret;

  // Disable FIFO
  ret = XRFdc_SetupFIFO(&RFdcInst, fifo_id, tile_id, stat);
  if (ret != SUCCESS)
  {
    printf("[change_fifo_stat] Unable to disable FIFO\r\n");
    return ret;
  }
  return SUCCESS;
}

int config_all_fifo(int fifo_id, int enable)
{
  int ret, ct;

  u32 max_dac_tiles = MAX_DAC_TILE;
  u32 max_adc_tiles = MAX_ADC_TILE;

  if (fifo_id == DAC)
  {
    for (ct = 0; ct < max_dac_tiles; ct++)
    {
      ret = change_fifo_stat(fifo_id, ct, enable);
      if (ret != SUCCESS)
      {
        printf("[config_all_fifo] Unable to disable DAC FIFO\n");
        return ret;
      }
    }
  } else if (fifo_id == ADC)
  {
    for (ct = 0; ct < max_adc_tiles; ct++)
    {
      ret = change_fifo_stat(fifo_id, ct, enable);
      if (ret != SUCCESS)
      {
        printf("[config_all_fifo] Unable to disable ADC FIFO\n");
        return ret;
      }
    }
  }

  return SUCCESS;
}

int reset_pipe(int *reset_gpio, int *localstart_gpio) {
  int i;
  int ret;
  u32 max_dac, max_adc;

  if (info.design_type == DAC1_ADC1) {
    max_dac = 1;
    max_adc = 1;
  } else {
    max_dac = MAX_DAC;
    max_adc = MAX_ADC;
  }

  /* disable local start gpio for all dac/adc's*/
  for (i = 0; i < max_dac; i++) {
    ret = set_gpio(localstart_gpio[i], 0);
    if (ret) {
      ret = GPIO_SET_FAIL;
      MetalLoghandler_firmware(ret, "unable to assert reset gpio value\n");
      goto err;
    }
  }

  /* assert reset fifo gpio for all dac/adc's*/
  for (i = 0; i < max_dac; i++) {
    ret = set_gpio(reset_gpio[i], 1);
    if (ret) {
      ret = GPIO_SET_FAIL;
      MetalLoghandler_firmware(ret, "unable to assert reset gpio value\n");
      goto err;
    }
  }
  usleep(10);
  /* De-Assert reset FIFO GPIO for all DAC/ADC's*/
  for (i = 0; i < max_dac; i++) {
    ret = set_gpio(reset_gpio[i], 0);
    if (ret) {
      ret = GPIO_SET_FAIL;
      MetalLoghandler_firmware(ret, "Unable to de-assert reset GPIO value\n");
      goto err;
    }
  }
  return SUCCESS;
err:
  return ret;
}

void SetMemtype(convData_t *cmdVals, char *txstrPtr, int *status) {
  int i;
  int ret;
  char buff[BUF_MAX_LEN] = {0};
  int *reset_gpio;
  int *localstart_gpio;
  unsigned int mem_type;
  u32 max_dac = MAX_DAC;
  u32 max_adc = MAX_ADC;

  mem_type = cmdVals[0].u;
  if (info.mem_type == mem_type) {
    printf("Already in the selected mode, no need to do anything\n");
    *status = SUCCESS;
    return;
  }
  info.mem_type = mem_type;

  for (i = 0; i < max_dac; i++) {
    /* Set memory type for DAC */
    ret = write_to_file(bram_ddr_path_dac[i], info.mem_type);
    if (ret != SUCCESS) {
      MetalLoghandler_firmware(ret, "Error configuring memory\n");
      goto err;
    }
  }
  for (i = 0; i < max_adc; i++) {
    /* Set memory type for ADC */
    ret = write_to_file(bram_ddr_path_adc[i], info.mem_type);
    if (ret != SUCCESS) {
      MetalLoghandler_firmware(ret, "Error configuring memory\n");
      goto err;
    }
  }
  info.scratch_value_dac = 0;
  info.scratch_value_adc = 0;

  for (i = 0; i < MAX_DAC; i++)
    info.channel_size[i] = 0;
  info.invalid_size = 0;
  info.adc_channels = 0;
  info.dac_channels = 0;
  /* write to channel select GPIO */
  ret = channel_select_gpio(dac_select_gpio, 0, DAC);
  if (ret) {
    ret = GPIO_SET_FAIL;
    MetalLoghandler_firmware(ret, "Unable to set channelselect GPIO value\n");
    goto err;
  }
  for (i = 0; i < max_dac; i++) {
    ret = set_gpio(dac_loopback_gpio[i], 0);
    if (ret) {
      ret = GPIO_SET_FAIL;
      MetalLoghandler_firmware(ret, "Unable to re-set loopback GPIO value\n");
      goto err;
    }
    /* Reset DMA */
    fsync((info.fd_dac[i]));
  }

  for (i = 0; i < 1; i++) {
    if (i == ADC) {
      reset_gpio = adc_reset_gpio;
      localstart_gpio = adc_localstart_gpio;
    } else if (i == DAC) {
      reset_gpio = dac_reset_gpio;
      localstart_gpio = dac_localstart_gpio;
    }
    ret = reset_pipe(reset_gpio, localstart_gpio);
    if (ret < 0) {
      MetalLoghandler_firmware(ret, "Unable to re-set loopback GPIO value\n");
      goto err;
    }
  }

  *status = SUCCESS;
  return;
err:
  if (enTermMode) {
    MetalLoghandler_firmware(ret, "cmd = SetMemtype\n"
                                  "mem_type = %d\n",
                             info.mem_type);
  }
  /* append error code */
  sprintf(buff, " %d", ret);
  strcat(txstrPtr, buff);
  *status = FAIL;
}

void GetMemtype(convData_t *cmdVals, char *txstrPtr, int *status) {
  char buff[BUF_MAX_LEN] = {0};

  sprintf(buff, " %d ", info.mem_type);
  strncat(txstrPtr, buff, BUF_MAX_LEN);
  *status = SUCCESS;
  return;
}

int WriteDataToMemory_bram(u32 block_id, int tile_id, u32 size, u32 il_pair) {
  int in_val_len = 0;
  int dac;
  int ret;

  if ((size == 0) || ((size % ADC_DAC_DMA_SZ_ALIGNMENT) != 0)) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(ret, "size should be multiples of 32\n");
    in_val_len = 1;
  }

  if (size > FIFO_SIZE) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(
        ret, "Requested size is bigger than available size(%d bytes)\n",
        FIFO_SIZE);
    in_val_len = 1;
  }

  /* extract DAC number from tile_id and block_id */
  dac = (((tile_id & 0x1) << 2) | (block_id & 0x3));

  /*
   * SSR IP design supports only one DAC(DAC7) and one ADC(ADC0)
   * So irrespective of channel force the channel to 1, as supported
   * DAC uses gpio's correponding to DAC0
   */
  if (info.design_type == DAC1_ADC1)
    dac = 0;

  /* get data from socket */
  ret = getSamples((info.map_dac[dac]), size);
  if (ret != size) {
    ret = RCV_SAMPLE_FAIL;
    MetalLoghandler_firmware(
        ret, "Unable to read %d bytes of data, received : %d\n", size, ret);
    goto err;
  }

  if (in_val_len) {
    ret = INVAL_ARGS;
    goto err;
  }
  info.channel_size[dac] = size;
  return 0;
err:
  return ret;
}

int WriteDataToMemory_ddr(u32 block_id, int tile_id, u32 size, u32 il_pair) {
  int in_val_len = 0;
  int dac;
  int ret;
  int *reset_gpio;
  int *local_start_gpio;

  if ((size == 0) || ((size % ADC_DAC_DMA_SZ_ALIGNMENT) != 0)) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(ret, "size should be multiples of 32\n");
    in_val_len = 1;
  }

  if (size > DAC_MAP_SZ) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(
        ret, "Requested size is bigger than available size(%d bytes)\n",
        DAC_MAP_SZ);
    in_val_len = 1;
  }

  if (info.mts_enable_dac) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(ret, "MTS not supported in DDR mode\n");
    goto err;
  }

  /* extract DAC number from tile_id and block_id */
  dac = (((tile_id & 0x1) << 2) | (block_id & 0x3));

  /*
   * SSR IP design supports only one DAC(DAC7) and one ADC(ADC0)
   * So irrespective of channel force the channel to 1, as supported
   * DAC uses gpio's correponding to DAC0
   */
  if (info.design_type == DAC1_ADC1)
    dac = 0;
  /* get data from socket */
  ret = getSamples((info.map_dac[dac]), size);
  if (ret != size) {
    ret = RCV_SAMPLE_FAIL;
    MetalLoghandler_firmware(
        ret, "Unable to read %d bytes of data, received : %d\n", size, ret);
    goto err;
  }

  if (in_val_len) {
    ret = INVAL_ARGS;
    goto err;
  }
  /* check if channel size is same for all channels */
  if (info.channel_size[0]) {
    if (info.channel_size[0] != size) {
      info.invalid_size = -1;
      ret = INVAL_ARGS;
      goto err;
    }
  }
  info.channel_size[0] = size;
  return 0;
err:
  return ret;
}

void WriteDataToMemory(convData_t *cmdVals, char *txstrPtr, int *status) {
  u32 block_id;
  int tile_id;
  u32 size, il_pair;
  int ret;

  tile_id = cmdVals[0].i;
  block_id = cmdVals[1].u;
  size = cmdVals[2].u;
  il_pair = cmdVals[3].u;

  ret = WriteDataToMemory_bram(block_id, tile_id, size, il_pair);
  if (ret < 0)
  {
    printf("Error in executing WriteDataToMemory_bram :%d\n", ret);
    goto err;
  }
  *status = SUCCESS;
  return;
err:
  if (enTermMode) {
    printf("cmd = WriteDataToMemory\n"
           "tile_id = %d\n"
           "block_id = %u\n"
           "size = %u\n"
           "interleaved_pair = %u\n\n",
           tile_id, block_id, size, il_pair);
  }

  *status = FAIL;
}

void * ReadDataFromMemory_td(void *arg)
{
  // Read number of bytes
  u32 size = * ((u32*) arg);
  
  // Unlock mutex to indicate that DMA started
  pthread_mutex_unlock(&adc_mutex);
  
  // Start DMA 
  int ret = read(info.fd_adc[0], info.map_adc[0], (size * sizeof(signed char)));
  
  // if `ret` is negative print and error
  if (ret < 0)
  {
    printf("[ReadDataFromMemory_td] Error reading data from ADCs\r\n");
  }
}

void ReadDataFromMemory(convData_t *cmdVals, char *txstrPtr, int *status)
{
  u32 size;
  int ret;
  size = cmdVals[2].u;

  printf("[ReadDataFromMemory_td] Begin\r\n");

  // Check if the size is valid
  if ((size == 0) || ((size % ADC_DAC_DMA_SZ_ALIGNMENT) != 0))
  {
    printf("[ReadDataFromMemory] `size` should be multiples of 32\n");
    goto err;
  }

  // Disable `adc_control`
  ret = set_gpio(adc_localstart_gpio[0], 0);
  if (ret)
  {
    printf("[ReadDataFromMemory] Unable to assert adc global start gpio\n");
    goto err;
  }

  // Assert ADC reset
  ret = set_gpio(adc_reset_gpio[0], 1);
  if (ret)
  {
    MetalLoghandler_firmware(ret,"unable to assert reset gpio value\n");
    goto err;
  }

  usleep(10);

  // De-assert ADC reset
  ret = set_gpio(adc_reset_gpio[0], 0);
  if (ret)
  {
    printf("[ReadDataFromMemory] Unable to de-assert reset GPIO value\n");
    goto err;
  }

  // Reset DMA
  fsync(info.fd_adc[0]);

  // Wait for 1 msec for DMA SW reset
  usleep(1000);

  // Start DMA on a new thread
  pthread_t thread_id;
  pthread_create(&thread_id, NULL, ReadDataFromMemory_td, (void *) &size);

  // Wait for the DMA to start
  pthread_mutex_lock(&adc_mutex);

  // Then, enable `adc_control`
  ret = set_gpio(adc_localstart_gpio[0], 1);
  if (ret)
  {
    printf("[ReadDataFromMemory] Unable to assert adc global start gpio\n");
    goto err;
  }

  // Wait for the DMA to finish
  pthread_join(thread_id, NULL);

  // Send data back to the host
  ret = sendSamples(info.map_adc[0], (size * sizeof(signed char)));
  if (ret != (size * sizeof(signed char)))
  {
    printf("[ReadDataFromMemory] Unable to send %d bytes, sent %d bytes\n", (size * sizeof(signed char)), ret);
    goto err;
  }

  printf("[ReadDataFromMemory_td] End\r\n");
  *status = SUCCESS;
  return;
err:
  if (enTermMode) {
    printf("cmd = ReadDataFromMemory\n"
           "tile_id = %d\n"
           "block_id = %u\n"
           "size = %u\n"
           "interleaved_pair = %u\n\n",
           cmdVals[0].u, cmdVals[1].u, cmdVals[2].u, cmdVals[3].u);
  }

  *status = FAIL;
}

/*
 * The API is a wrapper function used as a bridge with the command interface.
 * The function disable hardware fifo and disable datapath memory.
 */
void disconnect(convData_t *cmdVals, char *txstrPtr, int *status) {
  int ret;
  char buff[BUF_MAX_LEN] = {0};

  /* disable ADC and DAC fifo */
  ret = config_all_fifo(DAC, FIFO_DIS);
  if (ret != SUCCESS) {
    ret = DIS_FIFO_FAIL;
    MetalLoghandler_firmware(ret, "Failed to disable DAC FIFO\n");
    goto err;
  }

  ret = config_all_fifo(ADC, FIFO_DIS);
  if (ret != SUCCESS) {
    ret = DIS_FIFO_FAIL;
    MetalLoghandler_firmware(ret, "Failed to disable ADC FIFO\n");
    goto err;
  }

  printf("%s: waiting for lock\n", __func__);
  pthread_mutex_lock(&count_mutex);
  printf("%s: acquired lock\n", __func__);
  /* clear memory initialized for data path */
  deinit_mem();
  /* clear/release the gpio's */
  deinit_gpio();
  printf("%s:Releasing lock\n", __func__);
  pthread_mutex_unlock(&count_mutex);

  *status = SUCCESS;
  return;

err:
  if (enTermMode) {
    MetalLoghandler_firmware(ret, "cmd = shutdown\n");
  }

  /* Append Error code */
  sprintf(buff, " %d", ret);
  strcat(txstrPtr, buff);

  *status = FAIL;
}

/* Thread function for data path. It receives command/data from data socket
 */
void *datapath_t(void *args) {
  int ret;
  /* receive buffer of BUF_MAX_LEN character */
  char rcvBuf[BUF_MAX_LEN] = {0};
  /* tx buffer of BUF_MAX_LEN character */
  char txBuf[BUF_MAX_LEN] = {0};
  /* buffer len must be set to max buffer minus 1 */
  int bufLen = BUF_MAX_LEN - 1;
  /* number of character received per command line */
  int numCharacters;
  /* status of the command: XST_SUCCES - ERROR_CMD_UNDEF
   * - ERROR_NUM_ARGS - ERROR_EXECUTE
   */
  int cmdStatus;
  int i;

  /* initialse the memory for data path */
  printf("%s: waiting for lock\n", __func__);
  pthread_mutex_lock(&count_mutex);
  printf("%s: acquired lock\n", __func__);
  ret = init_mem();
  if (ret) {
    deinit_mem();
    MetalLoghandler_firmware(ret, "Unable to initialise memory\n");
    return NULL;
  }
  /* initialise the gpio's for data path */
  ret = init_gpio();
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to initialise gpio's\n");
    deinit_gpio();
    goto gpio_init_failed;
  }
  printf("%s:Releasing lock\n", __func__);
  pthread_mutex_unlock(&count_mutex);
  info.mts_enable_adc = 0;
  info.mts_enable_dac = 0;
  info.scratch_value_dac = 0;
  info.scratch_value_adc = 0;
  for (i = 0; i < MAX_DAC; i++)
    info.channel_size[i] = 0;
  info.invalid_size = 0;
  info.adc_channels = 0;
  info.dac_channels = 0;
  info.mem_type = BRAM;
whileloop:
  while (thread_stat) {
    /* get string from io interface (Non blocking) */
    numCharacters = getdataString(rcvBuf, bufLen);
    if (numCharacters > 0) {
      /* parse and run with error check */
      cmdStatus = data_cmdParse(rcvBuf, txBuf);
      /* check cmParse status - return an error message or the response */
      if (cmdStatus != SUCCESS) {
        /* command returned an errors */
        errorIf_data(txBuf, cmdStatus);
      } else {
        /* send response */
        senddataString(txBuf, strlen(txBuf));
      }

      /* clear rcvBuf each time anew command is received and processed */
      memset(rcvBuf, 0, sizeof(rcvBuf));
      /* clear txBuf each time anew command is received and a response returned
       */
      memset(txBuf, 0, sizeof(txBuf));

    } else if (numCharacters == 0) {
      goto whileloop;
    }
  }
gpio_init_failed:
  deinit_mem();
}

void SetBitstream(convData_t *cmdVals, char *txstrPtr, int *status) {
  int i;
  int ret;
  char buff[BUF_MAX_LEN] = {0};
  pthread_t thread_id;

  info.new_design = cmdVals[0].u;
  if (info.new_design >= DESIGN_MAX || (!info.new_design)) {
    ret = INVAL_ARGS;
    MetalLoghandler_firmware(ret, "Error incorrect design type\n");
    goto err;
  }
  pthread_create(&thread_id, NULL, dynamic_load, NULL);

  *status = SUCCESS;
  return;
err:
  if (enTermMode) {
    MetalLoghandler_firmware(ret, "SetBitstream cmd= \n"
                                  "new_design = %d\n",
                             info.new_design);
  }
  /* append error code */
  sprintf(buff, " %d", ret);
  strcat(txstrPtr, buff);
  *status = FAIL;
}

void GetBitstreamStatus(convData_t *cmdVals, char *txstrPtr, int *status) {
  char buff[BUF_MAX_LEN] = {0};
  int ret;

  ret = pthread_mutex_trylock(&design_lk_mutex);
  if (ret < 0) {
    sprintf(buff, " %d ", PL_NOT_READY);
    goto done;
  }
  if (info.design_type >= DESIGN_MAX) {
    sprintf(buff, " %d ", PL_NOT_READY);
  } else if (info.design_type == info.new_design) {
    sprintf(buff, " %d ", PL_READY);
  }
  pthread_mutex_unlock(&design_lk_mutex);

done:
  strncat(txstrPtr, buff, BUF_MAX_LEN);
  *status = SUCCESS;
  return;
}

void GetBitstream(convData_t *cmdVals, char *txstrPtr, int *status) {
  char buff[BUF_MAX_LEN] = {0};

  sprintf(buff, " %d ", info.design_type);
  strncat(txstrPtr, buff, BUF_MAX_LEN);
  *status = SUCCESS;
  return;
}

void *dynamic_load(void *args) {

  int ret, i;
  char buffer[BUF_MAX_LEN];
  char design[100];
  struct stat file_stat;
  char filepath[BUF_MAX_LEN];

  if (info.design_type == DESIGN_MAX)
    goto load_pl;

  /*
   * Deinit/clear everything
   * 1. Disable DAC and ADC FIFO's.
   * 2. De-initialise memory.
   * 3. De-initialise gpio's.
   * 4. Reset all the local variables.
   */
  /* disable ADC and DAC fifo */
  ret = config_all_fifo(DAC, FIFO_DIS);
  if (ret != SUCCESS) {
    ret = DIS_FIFO_FAIL;
    MetalLoghandler_firmware(ret, "Failed to disable DAC FIFO\n");
    goto err;
  }

  ret = config_all_fifo(ADC, FIFO_DIS);
  if (ret != SUCCESS) {
    ret = DIS_FIFO_FAIL;
    MetalLoghandler_firmware(ret, "Failed to disable ADC FIFO\n");
    goto err;
  }

  pthread_mutex_lock(&count_mutex);
  /* clear memory initialized for data path */
  deinit_mem();
  /* clear/release the gpio's */
  deinit_gpio();
  if (info.design_type == MTS)
    strcpy(design, "mts/");
  else if (info.design_type == NON_MTS)
    strcpy(design, "nonmts/");
  else if (info.design_type == DAC1_ADC1)
    strcpy(design, "ssr/");

  pthread_mutex_unlock(&count_mutex);

  pthread_mutex_lock(&design_lk_mutex);
  info.design_type = DESIGN_MAX;
  info.mts_enable_adc = 0;
  info.mts_enable_dac = 0;
  info.scratch_value_dac = 0;
  info.scratch_value_adc = 0;
  for (i = 0; i < MAX_DAC; i++)
    info.channel_size[i] = 0;
  info.invalid_size = 0;
  info.adc_channels = 0;
  info.dac_channels = 0;
  info.mem_type = BRAM;

  sprintf(buffer, "%s%smts.dtbo", UNLOAD_PL_PATH, design);
  ret = system(buffer);
  if (ret == -1) {
    printf("could not create child to execute system command \n");
    MetalLoghandler_firmware(FAIL, "Failed to load bitstream - check if "
                                   "folders are copied properly in SDcard\n");
    goto err1;
  } else if (WEXITSTATUS(ret) == 127) {
    MetalLoghandler_firmware(FAIL, "Failed to load bitstream - check if "
                                   "folders are copied properly in SDcard\n");
    printf("could not execute system command \n");
    goto err1;
  } else if (ret != 0) {
    MetalLoghandler_firmware(FAIL, "Failed to load bitstream - check if "
                                   "folders are copied properly in SDcard\n");
    printf("could not execute fpgautils command \n");
    goto err1;
  }

  usleep(2000);
  pthread_mutex_unlock(&design_lk_mutex);
load_pl:
  if (info.new_design == MTS)
    strcpy(design, "mts/");
  else if (info.new_design == NON_MTS)
    strcpy(design, "nonmts/");
  else if (info.new_design == DAC1_ADC1)
    strcpy(design, "ssr/");

  sprintf(
      buffer,
      "%s%smts.bit.bin -o /lib/firmware/xilinx/%smts.dtbo",
      LOAD_PL_PATH, design, design);
  sprintf(filepath, "/lib/firmware/xilinx/%smts.bit.bin",
          design);
  if (stat(filepath, &file_stat) < 0) {
    MetalLoghandler_firmware(FAIL, "check whether mts, nonmts and ssr folders "
                                   "are present with correct content in "
                                   "SDcard\n");
    goto err;
  }

  sprintf(filepath, "/lib/firmware/xilinx/%smts.dtbo", design);
  if (stat(filepath, &file_stat) < 0) {
    MetalLoghandler_firmware(FAIL, "check whether mts, nonmts and ssr folders "
                                   "are present with correct content in "
                                   "SDcard\n");
    goto err;
  }

  ret = system(buffer);
  if (ret == -1) {
    MetalLoghandler_firmware(
        FAIL, "Failed to load bitstream - check if fpgautil is available\n");
    printf("could not create child to execute system command \n");
    goto err;
  } else if (WEXITSTATUS(ret) == 127) {
    MetalLoghandler_firmware(
        FAIL, "Failed to load bitstream - check if fpgautil is available\n");
    printf("could not execute system command \n");
    goto err;
  } else if (ret != 0) {
    MetalLoghandler_firmware(
        FAIL, "Failed to load bitstream - check if fpgautil is available\n");
    printf("could not execute fpgautils command \n");
    goto err;
  }

  usleep(300000);

  pthread_mutex_lock(&design_lk_mutex);

  /* Re-initialize RFDC  */
  ret = rfdc_init();
  if (ret != SUCCESS) {
    printf("Failed to re-initialize RFDC\n");
    goto err1;
  }

  /* initialse the memory for data path */
  ret = init_mem();
  if (ret) {
    deinit_mem();
    MetalLoghandler_firmware(ret, "Unable to initialise memory\n");
    goto err1;
  }

  /* initialise the gpio's for data path */
  ret = init_gpio();
  if (ret) {
    MetalLoghandler_firmware(ret, "Unable to initialise gpio's\n");
    deinit_gpio();
    goto gpio_init_failed;
  }

  info.mts_enable_adc = 0;
  info.mts_enable_dac = 0;
  info.scratch_value_dac = 0;
  info.scratch_value_adc = 0;
  for (i = 0; i < MAX_DAC; i++)
    info.channel_size[i] = 0;

  info.invalid_size = 0;
  info.adc_channels = 0;
  info.dac_channels = 0;
  info.mem_type = BRAM;

  pthread_mutex_unlock(&design_lk_mutex);

  return NULL;

gpio_init_failed:
  deinit_mem();

err1:
  info.design_type = DESIGN_MAX;
  info.new_design = DESIGN_MAX;
  pthread_mutex_unlock(&design_lk_mutex);
  return NULL;
err:
  pthread_mutex_lock(&design_lk_mutex);
  info.design_type = DESIGN_MAX;
  info.new_design = DESIGN_MAX;
  pthread_mutex_unlock(&design_lk_mutex);
  return NULL;
}
