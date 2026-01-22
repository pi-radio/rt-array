//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description:
//
// Last update on Sep 24, 2025
//
// Copyright @ 2025
//

`timescale 1ns / 1ps

`include "rt_proc_core.svh"

module rt_proc_core #(
    parameter int     DW                = 32,
    parameter integer SAMPLES_PER_CLOCK = 2,
    parameter int     DW_DATA           = DW * SAMPLES_PER_CLOCK,  // bit width of all data buses
    parameter int     COEFF_WIDTH       = 16,
    // axil parameters
    parameter integer DATA_WIDTH        = 32,
    parameter integer ADDR_WIDTH        = 8,
    parameter integer STRB_WIDTH        = (DATA_WIDTH / 8)
) (
    input clk,
    input reset_n,

    input axil_clk,
    input axil_reset_n,

    // axi4-lite interface
    input  wire [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire [           2:0] s_axil_awprot,   // unused
    input  wire                  s_axil_awvalid,
    output wire                  s_axil_awready,
    input  wire [DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [STRB_WIDTH-1:0] s_axil_wstrb,
    input  wire                  s_axil_wvalid,
    output wire                  s_axil_wready,
    output wire [           1:0] s_axil_bresp,
    output reg                   s_axil_bvalid,
    input  wire                  s_axil_bready,
    input  wire [ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire [           2:0] s_axil_arprot,   // unused
    input  wire                  s_axil_arvalid,
    output wire                  s_axil_arready,
    output reg  [DATA_WIDTH-1:0] s_axil_rdata,
    output wire [           1:0] s_axil_rresp,
    output reg                   s_axil_rvalid,
    input  wire                  s_axil_rready,

    input  logic [COEFF_WIDTH * `NCH - 1:0] rx_fir0_reload_tdata,
    input  logic [              `NCH - 1:0] rx_fir0_reload_tvalid,
    output logic [              `NCH - 1:0] rx_fir0_reload_tready,
    input  logic [              `NCH - 1:0] rx_fir0_reload_tlast,

    input  logic [COEFF_WIDTH * `NCH - 1:0] rx_fir1_reload_tdata,
    input  logic [              `NCH - 1:0] rx_fir1_reload_tvalid,
    output logic [              `NCH - 1:0] rx_fir1_reload_tready,
    input  logic [              `NCH - 1:0] rx_fir1_reload_tlast,

    input  logic [COEFF_WIDTH * `NCH - 1:0] tx_fir0_reload_tdata,
    input  logic [              `NCH - 1:0] tx_fir0_reload_tvalid,
    output logic [              `NCH - 1:0] tx_fir0_reload_tready,
    input  logic [              `NCH - 1:0] tx_fir0_reload_tlast,

    input  logic [COEFF_WIDTH * `NCH - 1:0] tx_fir1_reload_tdata,
    input  logic [              `NCH - 1:0] tx_fir1_reload_tvalid,
    output logic [              `NCH - 1:0] tx_fir1_reload_tready,
    input  logic [              `NCH - 1:0] tx_fir1_reload_tlast,

    output logic [1:0] operation_mode,

    // no backpressure on the data ports.
    // adc0 to adc7
    input  logic [DW_DATA * `N_ANT - 1:0] s_tdata,
    input  logic                          s_tvalid,
    output logic                          s_tready,

    // dac0 to dac7
    output logic [DW_DATA * `N_ANT - 1:0] m_tdata,
    output logic                          m_tvalid
);

    localparam int W_FIR0_OUT = 16;
    localparam int I_FIR0_OUT = 1;
    localparam int F_FIR0_OUT = W_FIR0_OUT - I_FIR0_OUT;

    localparam int W_FIR0_FULL_PRECISION = 40;
    localparam int I_FIR0_FULL_PRECISION = 8;
    localparam int F_FIR0_FULL_PRECISION =
        30;  // note that the ip sign extends the data from 38 to 40 bits

    localparam int W_FIR1_OUT = 16;
    localparam int I_FIR1_OUT = 1;
    localparam int F_FIR1_OUT = W_FIR1_OUT - I_FIR1_OUT;

    localparam int W_FIR1_FULL_PRECISION = 40;
    localparam int I_FIR1_FULL_PRECISION = 10;
    localparam int F_FIR1_FULL_PRECISION =
        30;  // note that the ip sign extends the data from 38 to 40 bits

    localparam int DW_FFT_OUT = 16;
    localparam int DW_REAL = DW / 2;

    // internal params
    fir_t param_fir0_tdata;
    logic param_fir0_tvalid;
    logic param_fir0_tready;

    fir_t param_fir1_tdata;
    logic param_fir1_tvalid;
    logic param_fir1_tready;

    fir_t param_fir0_tdata_axil;
    logic param_fir0_tvalid_axil;
    logic param_fir0_tready_axil;

    fir_t param_fir1_tdata_axil;
    logic param_fir1_tvalid_axil;
    logic param_fir1_tready_axil;

    // tx broadcasted data
    logic [DW_DATA * `NCH - 1:0] s_tdata_i;
    logic [`NCH - 1:0] s_tvalid_i;
    logic [`NCH - 1:0] s_tready_i;

    logic s_tready_tx;
    logic s_tready_rx;

    logic [32 * `NCH - 1:0] phase_tx, phase_rx;
    logic [32 * `NCH - 1:0] phase_tx_axil, phase_rx_axil;
    logic [1:0] operation_mode_axil;

    // TODO: generate overflow signals and map
    logic [7:0] overflow;
    // TODO: generate errors and map
    logic [7:0] error;

    axil_io axil_io_inst (
        .clk    (axil_clk),
        .reset_n(axil_reset_n),

        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_awprot (s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid),
        .s_axil_wready (s_axil_wready),
        .s_axil_bresp  (s_axil_bresp),
        .s_axil_bvalid (s_axil_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_arprot (s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata  (s_axil_rdata),
        .s_axil_rresp  (s_axil_rresp),
        .s_axil_rvalid (s_axil_rvalid),
        .s_axil_rready (s_axil_rready),

        .phase_tx(phase_tx_axil),
        .phase_rx(phase_rx_axil),

        .operation_mode(operation_mode_axil),

        .fir0_tdata (param_fir0_tdata_axil),
        .fir0_tvalid(param_fir0_tvalid_axil),
        .fir0_tready(param_fir0_tready_axil),

        .fir1_tdata (param_fir1_tdata_axil),
        .fir1_tvalid(param_fir1_tvalid_axil),
        .fir1_tready(param_fir1_tready_axil)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),  // DECIMAL; range: 2-10
        .INIT_SYNC_FF(
            1),  // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
        .SIM_ASSERT_CHK(1),  // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .SRC_INPUT_REG(1),  // DECIMAL; 0=do not register input, 1=register input
        .WIDTH(2)
    ) xpm_cdc_operation_mode (
        .dest_out(operation_mode),
        .dest_clk(clk),
        .src_clk (axil_clk),
        .src_in  (operation_mode_axil)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF  (4),
        .INIT_SYNC_FF  (0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG (1),
        .WIDTH         (32 * `NCH)
    ) xpm_cdc_array_phase_tx (
        .dest_out(phase_tx),
        .dest_clk(clk),
        .src_clk (axil_clk),
        .src_in  (phase_tx_axil)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF  (4),
        .INIT_SYNC_FF  (0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG (1),
        .WIDTH         (32 * `NCH)
    ) xpm_cdc_array_phase_rx (
        .dest_out(phase_rx),
        .dest_clk(clk),
        .src_clk (axil_clk),
        .src_in  (phase_rx_axil)
    );

    xpm_fifo_axis #(
        .CDC_SYNC_STAGES(2),
        .CLOCKING_MODE  ("independent_clock"),
        .FIFO_DEPTH     (16),
        .TDATA_WIDTH    (8)
    ) xpm_fifo_cdc_fir0 (
        .s_aclk   (axil_clk),
        .s_aresetn(axil_reset_n),

        .s_axis_tready(param_fir0_tready_axil),
        .s_axis_tdata (param_fir0_tdata_axil),
        .s_axis_tvalid(param_fir0_tvalid_axil),

        .m_aclk(clk),

        .m_axis_tdata (param_fir0_tdata),
        .m_axis_tvalid(param_fir0_tvalid),
        .m_axis_tready(param_fir0_tready)
    );

    xpm_fifo_axis #(
        .CDC_SYNC_STAGES(2),
        .CLOCKING_MODE  ("independent_clock"),
        .FIFO_DEPTH     (16),
        .TDATA_WIDTH    (8)
    ) xpm_fifo_cdc_fir1 (
        .s_aclk   (axil_clk),
        .s_aresetn(axil_reset_n),

        .s_axis_tready(param_fir1_tready_axil),
        .s_axis_tdata (param_fir1_tdata_axil),
        .s_axis_tvalid(param_fir1_tvalid_axil),

        .m_aclk(clk),

        .m_axis_tdata (param_fir1_tdata),
        .m_axis_tvalid(param_fir1_tvalid),
        .m_axis_tready(param_fir1_tready)
    );

    always_comb begin
        s_tready = s_tready_tx & s_tready_rx;
    end

    // broadcast for tx
    axis_broadcast #(
        .DW           (DW_DATA),
        .NUM          (`NCH),
        .EN_IN_BUFFER (1),
        .EN_OUT_BUFFER(0)
    ) broadcast (
        .clk    (clk),
        .reset_n(reset_n),

        .s_tdata (s_tdata[0+:DW_DATA]),  // take adc0
        .s_tvalid(s_tvalid),
        .s_tready(s_tready_tx),

        .m_tdata (s_tdata_i),          // create 7 copies
        .m_tvalid(s_tvalid_i),
        .m_tready({7{s_tready_i[0]}})
    );

    core_unit #(
        .DW               (DW),
        .SAMPLES_PER_CLOCK(SAMPLES_PER_CLOCK),
        .DW_DATA          (DW_DATA),
        .COEFF_WIDTH      (COEFF_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .STRB_WIDTH       (STRB_WIDTH),
        .IS_TX            (1)
    ) unit_tx (
        .clk    (clk),
        .reset_n(reset_n),

        .fir0_reload_tdata (tx_fir0_reload_tdata),
        .fir0_reload_tvalid(tx_fir0_reload_tvalid),
        .fir0_reload_tready(tx_fir0_reload_tready),
        .fir0_reload_tlast (tx_fir0_reload_tlast),

        .param_fir0_tdata (param_fir0_tdata),   // common signal for both tx and rx
        .param_fir0_tvalid(param_fir0_tvalid),
        .param_fir0_tready(param_fir0_tready),

        .fir1_reload_tdata (tx_fir1_reload_tdata),
        .fir1_reload_tvalid(tx_fir1_reload_tvalid),
        .fir1_reload_tready(tx_fir1_reload_tready),
        .fir1_reload_tlast (tx_fir1_reload_tlast),

        .param_fir1_tdata (param_fir1_tdata),   // common signal for both tx and rx
        .param_fir1_tvalid(param_fir1_tvalid),
        .param_fir1_tready(param_fir1_tready),
        
        .phase(phase_tx),

        .s_tdata (s_tdata_i),
        .s_tvalid(s_tvalid_i[0]),
        .s_tready(s_tready_i[0]),

        .m_tdata (m_tdata[DW_DATA+:DW_DATA*`NCH]),  // dac1 to dac7
        .m_tvalid(m_tvalid)
    );

    core_unit #(
        .DW               (DW),
        .SAMPLES_PER_CLOCK(SAMPLES_PER_CLOCK),
        .DW_DATA          (DW_DATA),
        .COEFF_WIDTH      (COEFF_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .STRB_WIDTH       (STRB_WIDTH),
        .IS_TX            (0)
    ) unit_rx (
        .clk    (clk),
        .reset_n(reset_n),

        .fir0_reload_tdata (rx_fir0_reload_tdata),
        .fir0_reload_tvalid(rx_fir0_reload_tvalid),
        .fir0_reload_tready(rx_fir0_reload_tready),
        .fir0_reload_tlast (rx_fir0_reload_tlast),

        .param_fir0_tdata (param_fir0_tdata),   // common signal for both tx and rx
        .param_fir0_tvalid(param_fir0_tvalid),
        .param_fir0_tready(),                   // dangling

        .fir1_reload_tdata (rx_fir1_reload_tdata),
        .fir1_reload_tvalid(rx_fir1_reload_tvalid),
        .fir1_reload_tready(rx_fir1_reload_tready),
        .fir1_reload_tlast (rx_fir1_reload_tlast),

        .param_fir1_tdata (param_fir1_tdata),   // common signal for both tx and rx
        .param_fir1_tvalid(param_fir1_tvalid),
        .param_fir1_tready(),                   // dangling

        .phase(phase_rx),

        .s_tdata (s_tdata[DW_DATA+:DW_DATA*`NCH]),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready_rx),

        .m_tdata (m_tdata[0+:DW_DATA]),  // dac0
        .m_tvalid()                      // TODO: check if sync b/w tx and rx is required?
    );

endmodule
