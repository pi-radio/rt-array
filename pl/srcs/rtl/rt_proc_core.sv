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
    parameter int DW = 32,
    parameter integer SAMPLES_PER_CLOCK = 2,
    parameter int DW_DATA = DW * SAMPLES_PER_CLOCK,  // bit width of all data buses
    parameter int COEFF_WIDTH = 16,
    // axil parameters
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 8,
    parameter integer STRB_WIDTH = (DATA_WIDTH / 8)
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

    input logic [COEFF_WIDTH * `NCH - 1:0] fir0_reload_tdata,
    input logic [`NCH - 1:0] fir0_reload_tvalid,
    output logic [`NCH - 1:0] fir0_reload_tready,
    input logic [`NCH - 1:0] fir0_reload_tlast,

    input logic [COEFF_WIDTH * `NCH - 1:0] fir1_reload_tdata,
    input logic [`NCH - 1:0] fir1_reload_tvalid,
    output logic [`NCH - 1:0] fir1_reload_tready,
    input logic [`NCH - 1:0] fir1_reload_tlast,

    output logic [1:0] operation_mode,

    // no backpressure on the data ports.
    // adc0 to adc7
    input logic [DW_DATA * `N_ANT - 1:0] s_tdata,
    input logic s_tvalid,
    output logic s_tready,

    // dac0 to dac7
    output logic [DW_DATA * `N_ANT - 1:0] m_tdata,
    output logic m_tvalid
);

    localparam int W_FIR0_OUT = 16;
    localparam int I_FIR0_OUT = 1;
    localparam int F_FIR0_OUT = W_FIR0_OUT - I_FIR0_OUT;

    localparam int W_FIR0_FULL_PRECISION = 40;
    localparam int I_FIR0_FULL_PRECISION = 8;
    localparam int F_FIR0_FULL_PRECISION = 30; // note that the ip sign extends the data from 38 to 40 bits

    localparam int W_FIR1_OUT = 16;
    localparam int I_FIR1_OUT = 1;
    localparam int F_FIR1_OUT = W_FIR1_OUT - I_FIR1_OUT;

    localparam int W_FIR1_FULL_PRECISION = 40;
    localparam int I_FIR1_FULL_PRECISION = 10;
    localparam int F_FIR1_FULL_PRECISION = 30; // note that the ip sign extends the data from 38 to 40 bits

    localparam int DW_FFT_OUT = 16;
    localparam int DW_REAL = DW / 2;

    // internal params
    fir_t param_fir0_tdata;
    logic param_fir0_tvalid;
    logic [`NCH - 1:0] param_fir0_tready;

    fir_t param_fir1_tdata;
    logic param_fir1_tvalid;
    logic [`NCH - 1:0] param_fir1_tready;

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
    logic [`NCH - 1:0] s_tready_rx;

    // fir0 input
    logic [DW_DATA * `NCH - 1:0] fir0_in_tdata_i;
    logic [`NCH - 1:0] fir0_in_tvalid_i;
    logic [`NCH - 1:0] fir0_in_tready_i;

    logic [2 * W_FIR0_FULL_PRECISION * SAMPLES_PER_CLOCK * `NCH - 1:0] fir0_full_tdata;
    logic signed [W_FIR0_OUT - 1:0] fir0_tdata_i[`NCH * SAMPLES_PER_CLOCK];
    logic signed [W_FIR0_OUT - 1:0] fir0_tdata_q[`NCH * SAMPLES_PER_CLOCK];

    logic [`NCH - 1:0] fir0_tvalid;

    logic [2 * W_FIR1_FULL_PRECISION * SAMPLES_PER_CLOCK * `NCH - 1:0] fir1_full_tdata;
    logic signed [W_FIR1_OUT - 1:0] fir1_tdata_i[`NCH * SAMPLES_PER_CLOCK];
    logic signed [W_FIR1_OUT - 1:0] fir1_tdata_q[`NCH * SAMPLES_PER_CLOCK];
    logic [`NCH - 1:0] fir1_tvalid;

    logic [2 * `NCH * SAMPLES_PER_CLOCK * W_FIR1_OUT - 1:0] summation_in;

    logic [2 * W_FIR0_OUT * (`NCH) * SAMPLES_PER_CLOCK - 1:0] phaserot_tdata;
    logic phaserot_tvalid;

    logic tx_rx;
    logic [32 * `NCH - 1:0] phase;

    logic tx_rx_axil;
    logic [1:0] operation_mode_axil;
    logic [32 * `NCH - 1:0] phase_axil;

    axil_io axil_io_inst (
        .clk(axil_clk),
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

        .phase(phase_axil),
        .operation_mode(operation_mode_axil),
        .tx_rx(tx_rx_axil),

        .fir0_tdata (param_fir0_tdata_axil),
        .fir0_tvalid(param_fir0_tvalid_axil),
        .fir0_tready(param_fir0_tready_axil),

        .fir1_tdata (param_fir1_tdata_axil),
        .fir1_tvalid(param_fir1_tvalid_axil),
        .fir1_tready(param_fir1_tready_axil)
    );

    xpm_cdc_single #(
        .DEST_SYNC_FF(4),  // DECIMAL; range: 2-10
        .INIT_SYNC_FF(1),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
        .SIM_ASSERT_CHK(1),  // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .SRC_INPUT_REG(1)  // DECIMAL; 0=do not register input, 1=register input
    ) xpm_cdc_tx_rx (
        .dest_out(tx_rx),
        .dest_clk(clk),
        .src_clk (axil_clk),
        .src_in  (tx_rx_axil)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),  // DECIMAL; range: 2-10
        .INIT_SYNC_FF(1),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
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
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(32 * `NCH)
    ) xpm_cdc_array_phase (
        .dest_out(phase),
        .dest_clk(clk),
        .src_clk (axil_clk),
        .src_in  (phase_axil)
    );

    xpm_fifo_axis #(
        .CDC_SYNC_STAGES(2),
        .CLOCKING_MODE("independent_clock"),
        .FIFO_DEPTH(16),
        .TDATA_WIDTH(8)
    ) xpm_fifo_cdc_fir0 (
        .s_aclk(axil_clk),
        .s_aresetn(axil_reset_n),

        .s_axis_tready(param_fir0_tready_axil),
        .s_axis_tdata (param_fir0_tdata_axil),
        .s_axis_tvalid(param_fir0_tvalid_axil),

        .m_aclk(clk),

        .m_axis_tdata (param_fir0_tdata),
        .m_axis_tvalid(param_fir0_tvalid),
        .m_axis_tready(param_fir0_tready[0])
    );

    xpm_fifo_axis #(
        .CDC_SYNC_STAGES(2),
        .CLOCKING_MODE("independent_clock"),
        .FIFO_DEPTH(16),
        .TDATA_WIDTH(8)
    ) xpm_fifo_cdc_fir1 (
        .s_aclk(axil_clk),
        .s_aresetn(axil_reset_n),

        .s_axis_tready(param_fir1_tready_axil),
        .s_axis_tdata (param_fir1_tdata_axil),
        .s_axis_tvalid(param_fir1_tvalid_axil),

        .m_aclk(clk),

        .m_axis_tdata (param_fir1_tdata),
        .m_axis_tvalid(param_fir1_tvalid),
        .m_axis_tready(param_fir1_tready[0])
    );

    always_comb begin
        if (tx_rx) begin
            s_tready = s_tready_rx[0];
        end else begin
            s_tready = s_tready_tx;
        end
    end

    // broadcast for tx
    axis_broadcast #(
        .DW(DW_DATA),
        .NUM(`NCH),
        .EN_IN_BUFFER(1),
        .EN_OUT_BUFFER(0)
    ) broadcast (
        .clk(clk),
        .reset_n(reset_n),

        .s_tdata (s_tdata[0+:DW_DATA]),  // take adc0
        .s_tvalid(s_tvalid & (!tx_rx)),
        .s_tready(s_tready_tx),

        .m_tdata (s_tdata_i),   // create 7 copies
        .m_tvalid(s_tvalid_i),
        .m_tready(s_tready_i)
    );

    genvar gi, gj;
    generate
        // Q formats:
        // input data = Q1.15, coeffs = Q1.15. output data = Q8.30 full precision
        // after truncation, output data = Q3.13
        // adc 1 to adc 7 are used for rx beamforming
        for (gi = 0; gi < `NCH; gi++) begin
            axis_mux #(
                .DW(DW_DATA)
            ) axis_mux_inst (
                .clk(clk),
                .reset_n(reset_n),

                .sel({1'b0,tx_rx}),  // 0 for tx bf

                // select b/w 7 copies of adc0
                .s0_tdata(s_tdata_i[gi*DW_DATA+:DW_DATA]),
                .s0_tvalid(s_tvalid_i[gi]),
                .s0_tready(s_tready_i[gi]),
                // rx adc1 to adc7
                .s1_tdata (s_tdata[DW_DATA+gi*DW_DATA+:DW_DATA]),
                .s1_tvalid(s_tvalid),
                .s1_tready(s_tready_rx[gi]),

                .s2_tdata('h0),
                .s2_tvalid('h0),
                .s2_tready(),

                .m_tdata(fir0_in_tdata_i[gi*DW_DATA+:DW_DATA]),
                .m_tvalid(fir0_in_tvalid_i[gi]),
                .m_tready(1'b1)  // non blocking
            );

            fracDelayFIR fir0 (
                .aclk   (clk),
                .aresetn(reset_n),

                .s_axis_data_tvalid(fir0_in_tvalid_i[gi]),
                .s_axis_data_tready(fir0_in_tready_i[gi]),  // dangling
                .s_axis_data_tdata(fir0_in_tdata_i[gi*DW_DATA+:DW_DATA]),

                .s_axis_config_tvalid(param_fir0_tvalid),
                .s_axis_config_tready(param_fir0_tready[gi]),
                .s_axis_config_tdata (param_fir0_tdata),

                .s_axis_reload_tvalid(fir0_reload_tvalid[gi]),
                .s_axis_reload_tready(fir0_reload_tready[gi]),
                .s_axis_reload_tlast (fir0_reload_tlast[gi]),
                .s_axis_reload_tdata (fir0_reload_tdata[gi*COEFF_WIDTH+:COEFF_WIDTH]),

                .m_axis_data_tvalid(fir0_tvalid[gi]),
                .m_axis_data_tdata (fir0_full_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_FULL_PRECISION)+:(2*W_FIR0_FULL_PRECISION) * SAMPLES_PER_CLOCK])
            );

            // TODO: make this 2x?
            for (gj = 0; gj < SAMPLES_PER_CLOCK; gj++) begin
                xcmult #(
                    .W_A(W_FIR0_OUT),
                    .I_A(I_FIR0_OUT),
                    .W_B(16),
                    .I_B(1),
                    .W_P(W_FIR0_OUT),
                    .I_P(I_FIR0_OUT)
                ) xcmult_inst (
                    .clk(clk),
                    .en(1'b1),
                    .a({
                        fir0_tdata_q[gi*SAMPLES_PER_CLOCK+gj], fir0_tdata_i[gi*SAMPLES_PER_CLOCK+gj]
                    }),
                    .b(phase[gi*32+:32]),
                    .p(phaserot_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_OUT)+gj*(2*W_FIR0_OUT)+:(2*W_FIR0_OUT)])
                );
            end
            // Q formats:
            // input data = Q3.13, coeffs = Q1.15. output data = Q9.28 full precision
            // after truncation, output data = Q5.11

            GainCrrtFir fir1 (
                .aclk   (clk),
                .aresetn(reset_n),

                .s_axis_data_tvalid(phaserot_tvalid), // make this 3 cycles delayed version of fir0_tvalid
                .s_axis_data_tready(),  // unconnected
                .s_axis_data_tdata(phaserot_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_OUT)+:(2*W_FIR0_OUT) * SAMPLES_PER_CLOCK]),
                // .s_axis_data_tlast (phaserot_tlast),

                .s_axis_config_tvalid(param_fir1_tvalid),
                .s_axis_config_tready(param_fir1_tready[gi]),
                .s_axis_config_tdata (param_fir1_tdata),

                .s_axis_reload_tvalid(fir1_reload_tvalid[gi]),
                .s_axis_reload_tready(fir1_reload_tready[gi]),
                .s_axis_reload_tlast (fir1_reload_tlast[gi]),
                .s_axis_reload_tdata (fir1_reload_tdata[gi*COEFF_WIDTH+:COEFF_WIDTH]),

                .m_axis_data_tvalid(fir1_tvalid[gi]),
                .m_axis_data_tdata (fir1_full_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR1_FULL_PRECISION)+:(2*W_FIR1_FULL_PRECISION) * SAMPLES_PER_CLOCK])
            );
        end
    endgenerate

    // truncating fir outputs to 16 bits for next stage processing
    always_comb begin
        for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
            int addr_real = 2 * i * W_FIR0_FULL_PRECISION;
            int addr_imag = addr_real + W_FIR0_FULL_PRECISION;
            logic signed [W_FIR0_FULL_PRECISION - 1:0] temp_i, temp_q;

            temp_i = fir0_full_tdata[addr_real +: W_FIR0_FULL_PRECISION];
            temp_q = fir0_full_tdata[addr_imag +: W_FIR0_FULL_PRECISION];

            fir0_tdata_i[i] = temp_i >>> (F_FIR0_FULL_PRECISION - F_FIR0_OUT);
            fir0_tdata_q[i] =  temp_q >>> (F_FIR0_FULL_PRECISION - F_FIR0_OUT);
        end
    end

    always_comb begin
        for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
            int addr_real = 2 * i * W_FIR1_FULL_PRECISION;
            int addr_imag = addr_real + W_FIR1_FULL_PRECISION;
            logic signed [W_FIR1_FULL_PRECISION - 1:0] temp_i, temp_q;

            temp_i = fir1_full_tdata[addr_real +: W_FIR1_FULL_PRECISION];
            temp_q = fir1_full_tdata[addr_imag +: W_FIR1_FULL_PRECISION];

            // first 7 are real parts, next 7 are imag parts
            fir1_tdata_i[i] = temp_i >>> (F_FIR1_FULL_PRECISION - F_FIR1_OUT);
            fir1_tdata_q[i] = temp_q >>> (F_FIR1_FULL_PRECISION - F_FIR1_OUT);
        end

        for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
            int addr_real = 2*i*W_FIR1_OUT;
            int addr_imag = addr_real + W_FIR1_OUT;

            summation_in[addr_real +:W_FIR1_OUT] = fir1_tdata_i[i];
            summation_in[addr_imag +:W_FIR1_OUT] = fir1_tdata_q[i];
        end
    end

    reg [5:0] valid_d = 0;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            valid_d <= 0;
        end else begin
            valid_d <= {valid_d[4:0], fir0_tvalid[0]};
        end
    end
    assign phaserot_tvalid = valid_d[5];

    rt_summation #(
        .DW_FIR(W_FIR1_OUT),
        .DW_OUT(DW / 2),
        .SAMPLES_PER_CLOCK(SAMPLES_PER_CLOCK)
    ) rt_summation_inst (
        .clk(clk),
        .reset_n(reset_n),

        .sel_tx_rx(tx_rx),

        .s_tdata (summation_in),
        .s_tvalid(fir1_tvalid[0]),

        .m_tdata (m_tdata),
        .m_tvalid(m_tvalid)
    );
endmodule
