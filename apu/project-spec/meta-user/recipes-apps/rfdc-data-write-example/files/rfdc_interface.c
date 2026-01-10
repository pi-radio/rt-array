/******************************************************************************
*
* Copyright (C) 2018-2021 Xilinx, Inc.  All rights reserved.
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
#define BUF_MAX_LEN 16384 

/************************** Function Prototypes *****************************/

/************************** Variable Definitions ****************************/

XRFdc RFdcInst;      /* RFdc driver instance */
/* The buffer is cleared following a read log command */
char metalMsgBuf[BUF_MAX_LEN] = {0};
int metalMsgIdx = 0; 



/*
 * libmetal logger handler
 * The function append the log message from the metal_log to a global buffer
 * The global buffer is then cleared by a dedicated command following a read log
 * command
 */

void MetalLoghandler(enum metal_log_level level, const char *format, ...) {
  char msgLocal[BUF_MAX_LEN / 64];

  va_list args;
  static const char *level_strs[] = {
      "metal: emergency: ", "metal: alert:     ", "metal: critical:  ",
      "metal: error:     ", "metal: warning:   ", "metal: notice:    ",
      "metal: info:      ", "metal: debug:     ",
  };
  //pthread_mutex_lock(&mutex);
  va_start(args, format);
  vsnprintf(msgLocal, sizeof(msgLocal), format, args);
  va_end(args);

  if (level <= METAL_LOG_EMERGENCY || level > METAL_LOG_DEBUG)
    level = METAL_LOG_EMERGENCY;

  /* buffer msgLocal into metalMsgBuf */
  strncat(metalMsgBuf, level_strs[level], (BUF_MAX_LEN - 1));
  strncat(metalMsgBuf, msgLocal, (BUF_MAX_LEN - 1));
  /* Increment idx by 1 */
  metalMsgIdx++;
 // pthread_mutex_unlock(&mutex);
}
int rfdc_inst_init(u16 rfdc_id)
{
	XRFdc_Config *ConfigPtr;
	XRFdc *RFdcInstPtr = &RFdcInst;
	int Status;
	struct metal_device *device;
	int ret = 0;
	struct metal_init_params init_param = {
		.log_handler = MetalLoghandler, .log_level = METAL_LOG_ERROR,
	};
	
	if (metal_init(&init_param)) {
	printf("ERROR: metal_init METAL_LOG_INIT_FAILURE");
	return XRFDC_FAILURE;
	}
	
	/* Initialize the RFdc driver. */
	ConfigPtr = XRFdc_LookupConfig(rfdc_id);
	
	Status = XRFdc_RegisterMetal(RFdcInstPtr, rfdc_id, &device);
	if (Status != XRFDC_SUCCESS) {
	printf("ERROR: XRFdc_RegisterMetal METAL_DEV_REGISTER_FAILURE");
	return XRFDC_FAILURE;
	}
	
	/* Initializes the controller */
	Status = XRFdc_CfgInitialize(RFdcInstPtr, ConfigPtr);
	if (Status != XRFDC_SUCCESS) {
	printf("ERROR: XRFdc_CfgInitialize RFDC_CFG_INIT_FAILURE");
	return XRFDC_FAILURE;
	}
	
	
	return XRFDC_SUCCESS;
}


