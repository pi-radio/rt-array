//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_reg.sv
// Description: AXIS register slice with only forward path registered
// not suitable for high clock rates
// gives fixed latency
// Author: Nikhil Reddy (@nikhred)
// Date: 18-01-2026
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_reg #(
    parameter integer DW = 8,
    parameter integer DEPTH = 2
) (
    input clk,
    input reset_n,

    input wire [DW - 1:0] s_tdata,
    input wire s_tvalid,
    output reg s_tready,

    output wire [DW - 1:0] m_tdata,
    output wire m_tvalid,
    input reg m_tready
);

reg [DW - 1:0] m_tdata_i[DEPTH];
reg [DEPTH - 1:0] m_tvalid_i;
integer i;

always @(posedge clk) begin
    if(!reset_n) begin
        m_tvalid_i <= 0;
    end else begin
        if(m_tready) begin
            for(i = 0; i < DEPTH - 1; i=i+1) begin
                m_tvalid_i[i + 1] <= m_tvalid_i[i];
            end
            m_tvalid_i[0] <= s_tvalid;
        end
    end
end

always @(posedge clk) begin
    if(m_tready) begin
        for(i = 0; i < DEPTH - 1; i=i+1) begin
            m_tdata_i[i + 1] <= m_tdata_i[i];
        end
        m_tdata_i[0] <= s_tdata;
    end
end
assign m_tvalid = m_tvalid_i[DEPTH - 1];
assign m_tdata = m_tdata_i[DEPTH - 1];
assign s_tready = m_tready;

endmodule
