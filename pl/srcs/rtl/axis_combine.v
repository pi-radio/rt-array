//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_combine.v
// Description: basic combine block for vivado block design.
// Combines 14 AXIS slave interfaces into a single AXIS master interface. Added
// clocks and reset signals to be compliant. Ready signals are not registered.
// Author: @nikhred (Nikhil Reddy)
// Date: 29-10-2025
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_combine #(
    parameter integer DW = 32
) (

    input clk,
    input reset_n,

    input wire [DW - 1:0] s0_tdata,
    input wire s0_tvalid,
    input wire s0_tlast,
    output reg s0_tready,

    input wire [DW - 1:0] s1_tdata,
    input wire s1_tvalid,
    input wire s1_tlast,
    output reg s1_tready,

    input wire [DW - 1:0] s2_tdata,
    input wire s2_tvalid,
    input wire s2_tlast,
    output reg s2_tready,

    input wire [DW - 1:0] s3_tdata,
    input wire s3_tvalid,
    input wire s3_tlast,
    output reg s3_tready,

    input wire [DW - 1:0] s4_tdata,
    input wire s4_tvalid,
    input wire s4_tlast,
    output reg s4_tready,

    input wire [DW - 1:0] s5_tdata,
    input wire s5_tvalid,
    input wire s5_tlast,
    output reg s5_tready,

    input wire [DW - 1:0] s6_tdata,
    input wire s6_tvalid,
    input wire s6_tlast,
    output reg s6_tready,

    input wire [DW - 1:0] s7_tdata,
    input wire s7_tvalid,
    input wire s7_tlast,
    output reg s7_tready,

    input wire [DW - 1:0] s8_tdata,
    input wire s8_tvalid,
    input wire s8_tlast,
    output reg s8_tready,

    input wire [DW - 1:0] s9_tdata,
    input wire s9_tvalid,
    input wire s9_tlast,
    output reg s9_tready,

    input wire [DW - 1:0] s10_tdata,
    input wire s10_tvalid,
    input wire s10_tlast,
    output reg s10_tready,

    input wire [DW - 1:0] s11_tdata,
    input wire s11_tvalid,
    input wire s11_tlast,
    output reg s11_tready,

    input wire [DW - 1:0] s12_tdata,
    input wire s12_tvalid,
    input wire s12_tlast,
    output reg s12_tready,

    input wire [DW - 1:0] s13_tdata,
    input wire s13_tvalid,
    input wire s13_tlast,
    output reg s13_tready,

    output reg [DW * 14 - 1:0] m_tdata,
    output reg [14 - 1:0] m_tvalid,
    output reg [14 - 1:0] m_tlast,
    input wire [14 - 1:0] m_tready
);

    always @(posedge clk) begin
        if (!reset_n) begin
            m_tvalid <= 14'b0;
        end else begin
            // valid signals
            m_tvalid <= {
                s13_tvalid,
                s12_tvalid,
                s11_tvalid,
                s10_tvalid,
                s9_tvalid,
                s8_tvalid,
                s7_tvalid,
                s6_tvalid,
                s5_tvalid,
                s4_tvalid,
                s3_tvalid,
                s2_tvalid,
                s1_tvalid,
                s0_tvalid
            };
        end
    end

    always @(posedge clk) begin
        // combine all signals
        m_tdata <= {
            s13_tdata,
            s12_tdata,
            s11_tdata,
            s10_tdata,
            s9_tdata,
            s8_tdata,
            s7_tdata,
            s6_tdata,
            s5_tdata,
            s4_tdata,
            s3_tdata,
            s2_tdata,
            s1_tdata,
            s0_tdata
        };
        m_tlast <= {
            s13_tlast,
            s12_tlast,
            s11_tlast,
            s10_tlast,
            s9_tlast,
            s8_tlast,
            s7_tlast,
            s6_tlast,
            s5_tlast,
            s4_tlast,
            s3_tlast,
            s2_tlast,
            s1_tlast,
            s0_tlast
        };
    end

    // ready signals are not registered
    always @(*) begin
        // ready signals
        s0_tready  = m_tready[0];
        s1_tready  = m_tready[1];
        s2_tready  = m_tready[2];
        s3_tready  = m_tready[3];
        s4_tready  = m_tready[4];
        s5_tready  = m_tready[5];
        s6_tready  = m_tready[6];
        s7_tready  = m_tready[7];
        s8_tready  = m_tready[8];
        s9_tready  = m_tready[9];
        s10_tready = m_tready[10];
        s11_tready = m_tready[11];
        s12_tready = m_tready[12];
        s13_tready = m_tready[13];
    end
endmodule
