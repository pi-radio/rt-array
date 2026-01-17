//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_mux.v
// Description: select line based axis mux. Uses combinational logic
// hardcoded to 2 ports for easy integration for pi-radio use case
// Repo: https://github.com/nikhred/sv-foundry
// Author: @nikhred (Nikhil Reddy)
// Date: 08-10-2025
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_mux #(
    parameter integer DW = 8
) (
    input wire clk,
    input wire reset_n,

    input wire [1:0] sel,

    input  wire [DW - 1:0] s0_tdata,
    input  wire            s0_tvalid,
    output reg             s0_tready,

    input  wire [DW - 1:0] s1_tdata,
    input  wire            s1_tvalid,
    output reg             s1_tready,

    input  wire [DW - 1:0] s2_tdata,
    input  wire            s2_tvalid,
    output reg             s2_tready,

    output wire [DW - 1:0] m_tdata,
    output wire            m_tvalid,
    input  wire            m_tready
);

    reg  [DW - 1:0] m_tdata_i;
    reg             m_tvalid_i;
    wire            m_tready_i;

    axis_skidbuffer #(
        .DW(DW)
    ) axis_skidbuffer_inst (
        .clk    (clk),
        .reset_n(reset_n),

        .s_tdata (m_tdata_i),
        .s_tvalid(m_tvalid_i),
        .s_tready(m_tready_i),

        .m_tdata (m_tdata),
        .m_tvalid(m_tvalid),
        .m_tready(m_tready)
    );

    always @(*) begin
        s0_tready = 0;
        s1_tready = 0;
        s2_tready = 0;

        m_tdata_i = 0;
        m_tvalid_i = 0;

        case (sel)
            0: begin
                s0_tready  = m_tready_i;
                m_tdata_i  = s0_tdata;
                m_tvalid_i = s0_tvalid;
            end
            1: begin
                s1_tready  = m_tready_i;
                m_tdata_i  = s1_tdata;
                m_tvalid_i = s1_tvalid;
            end
            2: begin // bypass mode
                s2_tready  = m_tready_i;
                m_tdata_i  = s2_tdata;
                m_tvalid_i = s2_tvalid;
            end
            3: begin // bypass mode
                s2_tready  = m_tready_i;
                m_tdata_i  = s2_tdata;
                m_tvalid_i = s2_tvalid;
            end            
        endcase
    end

endmodule
