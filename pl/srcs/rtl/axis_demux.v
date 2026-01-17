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

    wire [DW - 1:0] s_tdata_i;
    wire            s_tvalid_i;
    reg             s_tready_i;

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

        case (sel)
            0: begin  // calib mode
                s_tready_i = m0_tready;
                m0_tdata   = s_tdata_i;
                m0_tvalid  = s_tvalid_i;
            end
            1: begin  // correction mode
                s_tready_i = m1_tready;
                m1_tdata   = s_tdata_i;
                m1_tvalid  = s_tvalid_i;
            end
            2: begin  // bypass mode
                s_tready_i = m2_tready;
                // m2_tdata   = s_tdata_i;
                // route adc0 data to all dacs
                for (i = 0; i < 8; i = i + 1) begin
                    m2_tdata[64*i+0+:16]  = s_tdata_i[0+:16];  // i0  -> i0
                    m2_tdata[64*i+16+:16] = s_tdata_i[16+:16];  // i1  -> q0
                    m2_tdata[64*i+32+:16] = s_tdata_i[32+:16];  // q0  -> i1
                    m2_tdata[64*i+48+:16] = s_tdata_i[48+:16];  // q1  -> q1
                end
                m2_tvalid = s_tvalid_i;
            end
            3: begin  // bypass mode - different mapping
                s_tready_i = m2_tready;
                m2_tvalid  = s_tvalid_i;
                for (i = 0; i < 8; i = i + 1) begin
                    m2_tdata[64*i+0+:16]  = s_tdata_i[0+:16];  // i0  -> i0
                    m2_tdata[64*i+16+:16] = s_tdata_i[32+:16];  // i1  -> q0
                    m2_tdata[64*i+32+:16] = s_tdata_i[16+:16];  // q0  -> i1
                    m2_tdata[64*i+48+:16] = s_tdata_i[48+:16];  // q1  -> q1
                end
            end
        endcase
    end

endmodule
