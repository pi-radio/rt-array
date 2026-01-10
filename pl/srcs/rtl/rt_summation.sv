//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description:
// for tx beamforming, pass the input as it is to output
// for rx beamforming, combine the input stream into a single output stream
//
// Last update on Sep 24, 2025
//
// Copyright @ 2025
//
`include "rt_proc_core.svh"

`timescale 1ns / 1ps

module rt_summation #(
    parameter int DW_FIR = 16,
    parameter int DW_OUT = 16,
    parameter int SAMPLES_PER_CLOCK = 2
) (
    input wire clk,
    input wire reset_n,

    // 0 - tx, 1 - rx beamforming
    input wire sel_tx_rx,

    // 2x for i/q
    input wire [DW_FIR * 2 * SAMPLES_PER_CLOCK * `NCH - 1:0] s_tdata,
    input wire s_tvalid,
    // 2x for i/q
    output reg [DW_OUT * 2 * SAMPLES_PER_CLOCK * `N_ANT  - 1:0] m_tdata,
    output reg m_tvalid
);

    // logic for summation across all channels
    logic signed [DW_FIR + 1 - 1:0] sum0_i[4][SAMPLES_PER_CLOCK];
    logic signed [DW_FIR + 2 - 1:0] sum1_i[2][SAMPLES_PER_CLOCK];
    logic signed [DW_FIR + 3 - 1:0] sum_i[SAMPLES_PER_CLOCK];

    logic signed [DW_FIR + 1 - 1:0] sum0_q[4][SAMPLES_PER_CLOCK];
    logic signed [DW_FIR + 2 - 1:0] sum1_q[2][SAMPLES_PER_CLOCK];
    logic signed [DW_FIR + 3 - 1:0] sum_q[SAMPLES_PER_CLOCK];

    // Q5.11 at the output of the fir1
    // Q8.11 at the output of sum
    // Q5.11 at the output
    // q format aligned to output.
    logic signed [DW_OUT - 1:0] out_i[SAMPLES_PER_CLOCK], out_q[SAMPLES_PER_CLOCK];

    logic signed [DW_OUT - 1:0] fir_data_i[`NCH][SAMPLES_PER_CLOCK];
    logic signed [DW_OUT - 1:0] fir_data_q[`NCH][SAMPLES_PER_CLOCK];
    reg [2:0] m_tvalid_i = 0;

    always_comb begin
        for (int i = 0; i < `NCH; i++) begin
            for (int j = 0; j < SAMPLES_PER_CLOCK; j++) begin
                fir_data_i[i][j] = s_tdata[(i*SAMPLES_PER_CLOCK+j)*2*DW_FIR+:DW_FIR];
                fir_data_q[i][j] = s_tdata[(i*SAMPLES_PER_CLOCK+j)*2*DW_FIR+DW_FIR+:DW_FIR];
            end
        end
    end

    // pipelined in clog2() stages
    always_ff @(posedge clk) begin
        for (int i = 0; i < SAMPLES_PER_CLOCK; i++) begin
            // real part summation
            sum0_i[0][i] <= fir_data_i[0][i] + fir_data_i[1][i];
            sum0_i[1][i] <= fir_data_i[2][i] + fir_data_i[3][i];
            sum0_i[2][i] <= fir_data_i[4][i] + fir_data_i[5][i];
            sum0_i[3][i] <= fir_data_i[6][i];  // ignore linter warning

            sum1_i[0][i] <= sum0_i[0][i] + sum0_i[1][i];
            sum1_i[1][i] <= sum0_i[2][i] + sum0_i[3][i];

            sum_i[i] <= sum1_i[0][i] + sum1_i[1][i];

            // imag part summation
            sum0_q[0][i] <= fir_data_q[0][i] + fir_data_q[1][i];
            sum0_q[1][i] <= fir_data_q[2][i] + fir_data_q[3][i];
            sum0_q[2][i] <= fir_data_q[4][i] + fir_data_q[5][i];
            sum0_q[3][i] <= fir_data_q[6][i];  // ignore linter warning

            sum1_q[0][i] <= sum0_q[0][i] + sum0_q[1][i];
            sum1_q[1][i] <= sum0_q[2][i] + sum0_q[3][i];

            sum_q[i] <= sum1_q[0][i] + sum1_q[1][i];
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            m_tvalid_i <= 0;
        end else begin
            m_tvalid_i <= {m_tvalid_i[1:0], s_tvalid};
        end
    end

    always_comb begin
        for (int i = 0; i < SAMPLES_PER_CLOCK; i++) begin
            out_i[i] = sum_i[i]; // >>> 3;
            out_q[i] = sum_q[i]; // >>> 3;
        end
    end

    always_comb begin
        if (sel_tx_rx) begin  // rx bf
            if (SAMPLES_PER_CLOCK == 1) begin
                m_tdata = {
                    {(2 * `NCH * SAMPLES_PER_CLOCK * DW_OUT) {1'b0}}, out_q[0], out_i[0]
                };  // dac1 to dac7 are set to 0
            end else begin
                m_tdata = {
                    {(2 * `NCH * SAMPLES_PER_CLOCK * DW_OUT) {1'b0}},
                    out_q[1],
                    out_i[1],
                    out_q[0],
                    out_i[0]
                };  // dac1 to dac7 are set to 0
            end

            m_tvalid = m_tvalid_i[2];
        end else begin  // tx bf
            if (SAMPLES_PER_CLOCK == 1) begin
                m_tdata = {s_tdata, {(2 * DW_OUT) {1'b0}}};  // dac0 is set to 0
            end else begin
                m_tdata = {s_tdata, {(2 * SAMPLES_PER_CLOCK * DW_OUT) {1'b0}}};  // dac0 is set to 0
            end
            m_tvalid = s_tvalid;
        end
    end
endmodule
