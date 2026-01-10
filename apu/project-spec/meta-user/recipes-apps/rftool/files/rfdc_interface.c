/******************************************************************************
*
* Copyright (C) 2017 Xilinx, Inc.  All rights reserved.
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
/***************************** Include Files ********************************/
#include "rfdc_interface.h"
/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/
/************************** Function Prototypes *****************************/

/************************** Variable Definitions ****************************/

XRFdc RFdcInst; /* RFdc driver instance */

int rfdc_inst_init(u16 rfdc_id) {
  XRFdc_Config *ConfigPtr;
  XRFdc *RFdcInstPtr = &RFdcInst;
  int Status;
  struct metal_device *device;
  int ret = 0;
  struct metal_init_params init_param = {
      .log_handler = MetalLoghandler, .log_level = METAL_LOG_ERROR,
  };

  if (metal_init(&init_param)) {
    sendString("ERROR: metal_init METAL_LOG_INIT_FAILURE", 40);
    return XRFDC_FAILURE;
  }

  /* Initialize the RFdc driver. */
  ConfigPtr = XRFdc_LookupConfig(rfdc_id);

  Status = XRFdc_RegisterMetal(RFdcInstPtr, rfdc_id, &device);
  if (Status != XRFDC_SUCCESS) {
    sendString("ERROR: XRFdc_RegisterMetal METAL_DEV_REGISTER_FAILURE", 53);
    return XRFDC_FAILURE;
  }

  /* Initializes the controller */
  Status = XRFdc_CfgInitialize(RFdcInstPtr, ConfigPtr);
  if (Status != XRFDC_SUCCESS) {
    sendString("ERROR: XRFdc_CfgInitialize RFDC_CFG_INIT_FAILURE", 48);
    return XRFDC_FAILURE;
  }


  return XRFDC_SUCCESS;
}

int rfdc_init(void) {
  int i, ret, fd;
  u32 max_dac_tiles = MAX_DAC_TILE;
  u32 max_adc_tiles = MAX_ADC_TILE;

  /* Read design type register from the HW */
  info.design_type = MTS;

  /* initialize RFDC instance */
  ret = rfdc_inst_init(RFDC_DEVICE_ID);
  if (ret != XRFDC_SUCCESS) {
    printf("Failed to initialize RFDC instance\n");
  }

  ret = initRFclock(ZCU111, LMK04208_12M8_3072M_122M88_REVA, DAC_3932_16_MHZ,
                    DAC_3932_16_MHZ, ADC_3932_16_MHZ);
  if (ret != SUCCESS) {
    printf("Unable to enable RF clocks\n");
    return ret;
  }

  /* Disable DAC fifo */
  ret = config_all_fifo(DAC, FIFO_DIS);
  if (ret != SUCCESS) {
    printf("Failed to disable DAC FIFO\n");
    return ret;
  }

  /* Disable ADC fifo */
  ret = config_all_fifo(ADC, FIFO_DIS);
  if (ret != SUCCESS) {
    printf("Failed to disable ADC FIFO\n");
    return ret;
  }

  for (i = 0; i < max_adc_tiles; i++) {
    ret = XRFdc_DynamicPLLConfig(&RFdcInst, ADC, i, 0, 3932.16, 3932.16);
    if (ret != SUCCESS) {
      printf("could not set ADC tile %d to 3932.16 freq ret = %d\n", i, ret);
      return ret;
    }
  }

  for (i = 0; i < max_dac_tiles; i++) {
    ret = XRFdc_DynamicPLLConfig(&RFdcInst, DAC, i, 0, 3932.16, 3932.16);
    if (ret != SUCCESS) {
      printf("could not set DAC tile %d to 3932.16 freq ret = %d\n", i, ret);
      return ret;
    }
  }
  return SUCCESS;
}
