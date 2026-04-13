//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_demux.v
// Description: select line based axis demux. Uses combinational logic
// Repo: https://github.com/nikhred/sv-foundry
// Author: @nikhred (Nikhil Reddy)
// Date: 08-10-2025
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_demux #(
    parameter integer DW = 512
) (
    input clk,
    input reset_n,

    input wire [1:0] sel,

    input  wire [DW - 1:0] s_tdata,
    input  wire            s_tvalid,
    output wire            s_tready,

    output reg  [DW - 1:0] m0_tdata,
    output reg             m0_tvalid,
    input  wire            m0_tready,

    output reg  [DW - 1:0] m1_tdata,
    output reg             m1_tvalid,
    input  wire            m1_tready,

    output reg  [DW - 1:0] m2_tdata,
    output reg             m2_tvalid,
    input  wire            m2_tready
);

    wire       [DW - 1:0] s_tdata_i;
    wire                  s_tvalid_i;
    reg                   s_tready_i;

    // signals for rx bypass
    reg signed [    15:0] in_i       [0:6] [0:1];
    reg signed [    15:0] in_q       [0:6] [0:1];

    reg signed [    15:0] out_i      [0:1];
    reg signed [    15:0] out_q      [0:1];

    reg signed [    16:0] sum0_i     [0:3] [0:1];
    reg signed [    17:0] sum1_i     [0:1] [0:1];
    reg signed [    18:0] sum_i      [0:1];

    reg signed [    16:0] sum0_q     [0:3] [0:1];
    reg signed [    17:0] sum1_q     [0:1] [0:1];
    reg signed [    18:0] sum_q      [0:1];

    axis_skidbuffer #(
        .DW(DW)
    ) axis_skidbuffer_inst (
        .clk    (clk),
        .reset_n(reset_n),

        .s_tdata (s_tdata),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),

        .m_tdata (s_tdata_i),
        .m_tvalid(s_tvalid_i),
        .m_tready(s_tready_i)
    );

    integer i;
    always @(*) begin
        m2_tdata   = 0;
        m2_tvalid  = 0;
        m1_tdata   = 0;
        m1_tvalid  = 0;
        m0_tdata   = 0;
        m0_tvalid  = 0;
        s_tready_i = 0;

        // only modes 0 and 1 are used for operations
        // modes 2 and 3 are only for debugging
        case (sel)
            0: begin  // calib mode
                s_tready_i = m0_tready;
                m0_tdata   = s_tdata_i;
                m0_tvalid  = s_tvalid_i;
            end
            1: begin  
                // correction mode: data is sent to both real time flow for correction 
                // and the non-real-time flow for monitoring. 
                m1_tdata   = s_tdata_i;
                m0_tdata   = s_tdata_i;
                if({m1_tready, m0_tready} == 2'b11) begin
                    m1_tvalid  = s_tvalid_i;
                    m0_tvalid = s_tvalid_i;    
                    s_tready_i = m1_tready;
                end else begin
                    m0_tvalid = 0;
                    m1_tvalid = 0;
                    s_tready_i = 0;
                end 
            end
            2: begin  // bypass mode - tx + rx 
                s_tready_i = m2_tready;
                // tx bypass: adc0 to dac1 to dac7
                // mapping from ADC: q1 q0 i1 i0
                // mapping to DAC: i1 q1 i0 q0                
                for (i = 1; i < 8; i = i + 1) begin
                    m2_tdata[64*i+16+:16]  = s_tdata_i[0+:16];  // i0  -> i0
                    m2_tdata[64*i+48+:16] = s_tdata_i[16+:16];  // i1  -> q0
                    m2_tdata[64*i+0+:16] = s_tdata_i[32+:16];  // q0  -> i1
                    m2_tdata[64*i+32+:16] = s_tdata_i[48+:16];  // q1  -> q1
                end
                // rx bypass: sum(adc1:adc7) -> dac0
                m2_tdata[0 +: 64]   = {
                    out_i[1],                     
                    out_q[1], 
                    out_i[0],
                    out_q[0]
                };
                m2_tvalid = s_tvalid_i;
            end
            3: begin  // bypass mode - tx bypass
                s_tready_i = m2_tready;
                m2_tvalid  = s_tvalid_i;
                // mapping from ADC: q1 q0 i1 i0
                // mapping to DAC: i1 q1 i0 q0
                for (i = 0; i < 8; i = i + 1) begin
                    m2_tdata[64*i+16+:16]  = s_tdata_i[0+:16];  // i0  -> i0
                    m2_tdata[64*i+48+:16] = s_tdata_i[16+:16];  // i1  -> q0
                    m2_tdata[64*i+0+:16] = s_tdata_i[32+:16];  // q0  -> i1
                    m2_tdata[64*i+32+:16] = s_tdata_i[48+:16];  // q1  -> q1
                end
            end
        endcase
    end

    // pipelined in clog2() stages
    always @(posedge clk) begin
        for (i = 0; i < 2; i=i+1) begin
            // real part summation
            sum0_i[0][i] <= in_i[0][i] + in_i[1][i];
            sum0_i[1][i] <= in_i[2][i] + in_i[3][i];
            sum0_i[2][i] <= in_i[4][i] + in_i[5][i];
            sum0_i[3][i] <= in_i[6][i];  // ignore linter warning

            sum1_i[0][i] <= sum0_i[0][i] + sum0_i[1][i];
            sum1_i[1][i] <= sum0_i[2][i] + sum0_i[3][i];

            sum_i[i]     <= sum1_i[0][i] + sum1_i[1][i];

            // imag part summation
            sum0_q[0][i] <= in_q[0][i] + in_q[1][i];
            sum0_q[1][i] <= in_q[2][i] + in_q[3][i];
            sum0_q[2][i] <= in_q[4][i] + in_q[5][i];
            sum0_q[3][i] <= in_q[6][i];  // ignore linter warning

            sum1_q[0][i] <= sum0_q[0][i] + sum0_q[1][i];
            sum1_q[1][i] <= sum0_q[2][i] + sum0_q[3][i];

            sum_q[i]     <= sum1_q[0][i] + sum1_q[1][i];
        end
    end

    always @(*) begin
        for (i = 0; i < 7; i=i+1) begin
            // mapping starts from adc1 (64 + )
            in_i[i][0] = s_tdata_i[64+64*i+:16];
            in_q[i][0] = s_tdata_i[64+64*i+32+:16];

            in_i[i][1] = s_tdata_i[64+64*i+16+:16];
            in_q[i][1] = s_tdata_i[64+64*i+48+:16];
        end
        for (i = 0; i < 2; i=i+1) begin
            out_i[i] = sum_i[i];  // >>> 3;
            out_q[i] = sum_q[i];  // >>> 3;
        end
    end
endmodule
