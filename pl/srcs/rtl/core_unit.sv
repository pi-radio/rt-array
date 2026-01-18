//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description:
//
// Last update on Jan 18, 2026
//
// Copyright @ 2026
//

`timescale 1ns / 1ps

`include "rt_proc_core.svh"

module core_unit #(
    parameter int DW = 32,
    parameter integer SAMPLES_PER_CLOCK = 2,
    parameter int DW_DATA = DW * SAMPLES_PER_CLOCK,  // bit width of all data buses
    parameter int COEFF_WIDTH = 16,
    // axil parameters
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 8,
    parameter integer STRB_WIDTH = (DATA_WIDTH / 8),
    parameter integer IS_TX = 0,
    localparam int W_M_TDATA = (IS_TX) ? DW_DATA * `NCH : DW_DATA
) (
    input clk,
    input reset_n,

    input  logic [COEFF_WIDTH * `NCH - 1:0] fir0_reload_tdata,
    input  logic [              `NCH - 1:0] fir0_reload_tvalid,
    output logic [              `NCH - 1:0] fir0_reload_tready,
    input  logic [              `NCH - 1:0] fir0_reload_tlast,

    input  logic [7:0] param_fir0_tdata,
    input  logic       param_fir0_tvalid,
    output logic       param_fir0_tready,

    input  logic [COEFF_WIDTH * `NCH - 1:0] fir1_reload_tdata,
    input  logic [              `NCH - 1:0] fir1_reload_tvalid,
    output logic [              `NCH - 1:0] fir1_reload_tready,
    input  logic [              `NCH - 1:0] fir1_reload_tlast,

    input  logic [7:0] param_fir1_tdata,
    input  logic       param_fir1_tvalid,
    output logic       param_fir1_tready,

    input logic [32 * `NCH - 1:0] phase,

    // no backpressure on the data ports.
    // 7 streams - 7 copies of adc0 for tx or adc1 to adc7 for rx
    input  logic [DW_DATA * `NCH - 1:0] s_tdata,
    input  logic                        s_tvalid,
    output logic                        s_tready,

    output logic [W_M_TDATA - 1:0] m_tdata,
    output logic                   m_tvalid
);
    localparam int W_FIR0_OUT = 16;
    localparam int I_FIR0_OUT = 1;
    localparam int F_FIR0_OUT = W_FIR0_OUT - I_FIR0_OUT;

    localparam int W_FIR0_FULL_PRECISION = 40;
    localparam int I_FIR0_FULL_PRECISION = 8;
    // note that the ip sign extends the data from 38 to 40 bits
    localparam int F_FIR0_FULL_PRECISION = 30;

    localparam int W_FIR1_OUT = 16;
    localparam int I_FIR1_OUT = 1;
    localparam int F_FIR1_OUT = W_FIR1_OUT - I_FIR1_OUT;

    localparam int W_FIR1_FULL_PRECISION = 40;
    localparam int I_FIR1_FULL_PRECISION = 10;
    // note that the ip sign extends the data from 38 to 40 bits
    localparam int F_FIR1_FULL_PRECISION = 30; 

    // internal signals to avoid warnings
    logic [`NCH - 1:0] s_tready_i;
    logic [`NCH - 1:0] param_fir0_tready_i;
    logic [`NCH - 1:0] param_fir1_tready_i;

    logic [`NCH - 1:0] fir0_tvalid;
    logic [`NCH - 1:0] fir1_tvalid;

    logic [2 * W_FIR0_FULL_PRECISION * SAMPLES_PER_CLOCK * `NCH - 1:0] fir0_full_tdata;
    logic signed [W_FIR0_OUT - 1:0] fir0_tdata_i[`NCH * SAMPLES_PER_CLOCK];
    logic signed [W_FIR0_OUT - 1:0] fir0_tdata_q[`NCH * SAMPLES_PER_CLOCK];

    logic [2 * W_FIR1_FULL_PRECISION * SAMPLES_PER_CLOCK * `NCH - 1:0] fir1_full_tdata;
    logic signed [W_FIR1_OUT - 1:0] fir1_tdata_i[`NCH * SAMPLES_PER_CLOCK];
    logic signed [W_FIR1_OUT - 1:0] fir1_tdata_q[`NCH * SAMPLES_PER_CLOCK];

    logic [2 * W_FIR0_OUT * (`NCH) * SAMPLES_PER_CLOCK - 1:0] phaserot_tdata;
    logic phaserot_tvalid;

    logic [2 * `NCH * SAMPLES_PER_CLOCK * W_FIR1_OUT - 1:0] summation_in;

    
    logic [W_M_TDATA - 1:0] axis_reg_in_tdata_i;
    logic [W_M_TDATA - 1:0] m_tdata_i;
    logic m_tvalid_i;

    assign s_tready          = s_tready_i[0];
    assign param_fir0_tready = param_fir0_tready_i[0];
    assign param_fir1_tready = param_fir1_tready_i[0];

    genvar gi, gj;
    generate
        // Q formats:
        // input data = Q1.15, coeffs = Q1.15. output data = Q8.30 full precision
        // after truncation, output data = Q3.13
        // adc 1 to adc 7 are used for rx beamforming
        for (gi = 0; gi < `NCH; gi++) begin
            fracDelayFIR fir0 (
                .aclk   (clk),
                .aresetn(reset_n),

                .s_axis_data_tvalid(s_tvalid),
                .s_axis_data_tready(s_tready_i[gi]),               // dangling
                .s_axis_data_tdata (s_tdata[gi*DW_DATA+:DW_DATA]),

                .s_axis_config_tvalid(param_fir0_tvalid),
                .s_axis_config_tready(param_fir0_tready_i[gi]),
                .s_axis_config_tdata (param_fir0_tdata),

                .s_axis_reload_tvalid(fir0_reload_tvalid[gi]),
                .s_axis_reload_tready(fir0_reload_tready[gi]),
                .s_axis_reload_tlast (fir0_reload_tlast[gi]),
                .s_axis_reload_tdata (fir0_reload_tdata[gi*COEFF_WIDTH+:COEFF_WIDTH]),

                .m_axis_data_tvalid(fir0_tvalid[gi]),
                .m_axis_data_tdata(fir0_full_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_FULL_PRECISION)+:
                                                   (2*W_FIR0_FULL_PRECISION)*SAMPLES_PER_CLOCK])
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
                    .p(phaserot_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_OUT)+
                                      gj*(2*W_FIR0_OUT)+:(2*W_FIR0_OUT)])
                );
            end
            // Q formats:
            // input data = Q3.13, coeffs = Q1.15. output data = Q9.28 full precision
            // after truncation, output data = Q5.11

            GainCrrtFir fir1 (
                .aclk   (clk),
                .aresetn(reset_n),

                .s_axis_data_tvalid(
                    phaserot_tvalid),  // make this 3 cycles delayed version of fir0_tvalid
                .s_axis_data_tready(),  // unconnected
                .s_axis_data_tdata(phaserot_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR0_OUT)+:
                                                  (2*W_FIR0_OUT)*SAMPLES_PER_CLOCK]),
                // .s_axis_data_tlast (phaserot_tlast),

                .s_axis_config_tvalid(param_fir1_tvalid),
                .s_axis_config_tready(param_fir1_tready_i[gi]),
                .s_axis_config_tdata (param_fir1_tdata),

                .s_axis_reload_tvalid(fir1_reload_tvalid[gi]),
                .s_axis_reload_tready(fir1_reload_tready[gi]),
                .s_axis_reload_tlast (fir1_reload_tlast[gi]),
                .s_axis_reload_tdata (fir1_reload_tdata[gi*COEFF_WIDTH+:COEFF_WIDTH]),

                .m_axis_data_tvalid(fir1_tvalid[gi]),
                .m_axis_data_tdata(fir1_full_tdata[gi*SAMPLES_PER_CLOCK*(2*W_FIR1_FULL_PRECISION)+:
                                                   (2*W_FIR1_FULL_PRECISION)*SAMPLES_PER_CLOCK])
            );
        end

        if (IS_TX == 0) begin  // enabled only for rx bf
            rt_summation #(
                .DW_FIR           (W_FIR1_OUT),
                .DW_OUT           (DW / 2),
                .SAMPLES_PER_CLOCK(SAMPLES_PER_CLOCK)
            ) rt_summation_inst (
                .clk    (clk),
                .reset_n(reset_n),

                .s_tdata (summation_in),
                .s_tvalid(fir1_tvalid[0]),

                .m_tdata (m_tdata_i),
                .m_tvalid(m_tvalid_i)
            );
        end else begin
            // delay the data by 2 cycles so that both tx and rx are aligned. 
            // might not be strictly necessary, but helps in testing if latency is same.
            axis_reg # (
                .DW(W_M_TDATA),
                .DEPTH(2)
            )
            axis_reg_inst (
                .clk(clk),
                .reset_n(reset_n),

                .s_tdata(axis_reg_in_tdata_i),
                .s_tvalid(fir1_tvalid[0]),
                .s_tready(),

                .m_tdata(m_tdata_i),
                .m_tvalid(m_tvalid_i),
                .m_tready()
            );
        end 
    endgenerate

    always_comb begin
        for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
            int addr_real = 2 * i * W_FIR0_FULL_PRECISION;
            int addr_imag = addr_real + W_FIR0_FULL_PRECISION;
            logic signed [W_FIR0_FULL_PRECISION - 1:0] temp_i, temp_q;

            temp_i          = fir0_full_tdata[addr_real+:W_FIR0_FULL_PRECISION];
            temp_q          = fir0_full_tdata[addr_imag+:W_FIR0_FULL_PRECISION];

            fir0_tdata_i[i] = temp_i >>> (F_FIR0_FULL_PRECISION - F_FIR0_OUT);
            fir0_tdata_q[i] = temp_q >>> (F_FIR0_FULL_PRECISION - F_FIR0_OUT);
        end
    end

    always_comb begin
        for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
            int addr_real = 2 * i * W_FIR1_FULL_PRECISION;
            int addr_imag = addr_real + W_FIR1_FULL_PRECISION;
            logic signed [W_FIR1_FULL_PRECISION - 1:0] temp_i, temp_q;

            temp_i          = fir1_full_tdata[addr_real+:W_FIR1_FULL_PRECISION];
            temp_q          = fir1_full_tdata[addr_imag+:W_FIR1_FULL_PRECISION];

            // first 7 are real parts, next 7 are imag parts
            fir1_tdata_i[i] = temp_i >>> (F_FIR1_FULL_PRECISION - F_FIR1_OUT);
            fir1_tdata_q[i] = temp_q >>> (F_FIR1_FULL_PRECISION - F_FIR1_OUT);
        end

        if (IS_TX) begin
            // send output directly. Summation block is bypassed
            for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
                int addr_real = 2 * i * W_FIR1_OUT;
                int addr_imag = addr_real + W_FIR1_OUT;

                axis_reg_in_tdata_i[addr_real+:W_FIR1_OUT] = fir1_tdata_i[i];
                axis_reg_in_tdata_i[addr_imag+:W_FIR1_OUT] = fir1_tdata_q[i];
            end
            m_tdata  = m_tdata_i;
            m_tvalid = m_tvalid_i;
        end else begin
            // send fir output to summation block
            for (int i = 0; i < SAMPLES_PER_CLOCK * `NCH; i++) begin
                int addr_real = 2 * i * W_FIR1_OUT;
                int addr_imag = addr_real + W_FIR1_OUT;

                summation_in[addr_real+:W_FIR1_OUT] = fir1_tdata_i[i];
                summation_in[addr_imag+:W_FIR1_OUT] = fir1_tdata_q[i];
            end

            m_tdata  = m_tdata_i;
            m_tvalid = m_tvalid_i;
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

    // checkers
    always_ff @(posedge clk) begin
        assert (!$isunknown(s_tvalid));
        assert (!$isunknown(m_tvalid));
        assert (!$isunknown(fir1_tvalid));
        assert (!$isunknown(fir0_tvalid));

        if (s_tvalid) begin
            assert (!$isunknown(s_tdata));
        end

        if (m_tvalid) begin
            assert (!$isunknown(m_tdata));
        end
    end
endmodule
