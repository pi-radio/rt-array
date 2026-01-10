`ifndef CALIBRATION_SVH
`define CALIBRATION_SVH

// number of antennas (= DACs/ADCs)
`define N_ANT 8
// number of parallel channels to process. This is fixed to 7 for 8ch phased array
`define NCH 7

typedef struct packed {
    // 0 - calibration mode (non real time)
    // 1 - operation mode (real time)
    logic mode;
    // 0 - tx beamforming
    // 1 - rx beamforming
    logic tx_rx;
    // indicates that the correction factors are updated and must be reloaded.
    logic phase_reload;
    logic fir_reload;
    logic [3:0] reserved;
} rt_proc_ctrl_t;

typedef  struct packed {
    logic [7:0] tdata;
} fir_t;

typedef struct packed {
    logic [`NCH-1:0][31:0] data;
} phaserot_t;

typedef struct packed {
    logic FWD_INV;
    logic [9:0] scale_sch;
    logic [4:0] reserved; // keep linter happy
} fft_t;

`endif // CALIBRATION_SVH
