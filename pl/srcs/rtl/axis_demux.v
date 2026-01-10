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
    parameter integer DW = 8
) (
    input clk,
    input reset_n,

    input wire sel,

    input wire [DW - 1:0] s_tdata,
    input wire s_tvalid,
    output wire s_tready,

    output reg [DW - 1:0] m0_tdata,
    output reg m0_tvalid,
    input wire m0_tready,

    output reg [DW - 1:0] m1_tdata,
    output reg m1_tvalid,
    input wire m1_tready
);

    wire [DW - 1:0] s_tdata_i;
    wire s_tvalid_i;
    reg s_tready_i;

    axis_skidbuffer #(
        .DW(DW)
    ) axis_skidbuffer_inst (
        .clk(clk),
        .reset_n(reset_n),

        .s_tdata(s_tdata),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),

        .m_tdata(s_tdata_i),
        .m_tvalid(s_tvalid_i),
        .m_tready(s_tready_i)
    );

    always @(*) begin
        m1_tdata  = 0;
        m1_tvalid = 0;
        m0_tdata  = 0;
        m0_tvalid = 0;
        s_tready_i = 0;

        if (sel) begin
            s_tready_i  = m1_tready;
            m1_tdata  = s_tdata_i;
            m1_tvalid = s_tvalid_i;
        end else begin
            s_tready_i  = m0_tready;
            m0_tdata  = s_tdata_i;
            m0_tvalid = s_tvalid_i;
        end
    end

endmodule
