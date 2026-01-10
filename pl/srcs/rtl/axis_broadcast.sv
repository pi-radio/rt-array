//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_broadcast.sv
// Description: module to broadcast one stream to multiple modules
// Repo: https://github.com/nikhred/sv-foundry
// Author: @nikhred (Nikhil Reddy)
// Date: 04-02-2024
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_broadcast #(
    parameter int DW = 8,
    parameter int NUM = 2,
    parameter int EN_IN_BUFFER = 1,
    parameter int EN_OUT_BUFFER = 1
) (
    input clk,
    input reset_n,

    input logic [DW - 1:0] s_tdata,
    input logic s_tvalid,
    output logic s_tready,

    output logic [DW*NUM - 1:0] m_tdata,
    output logic [NUM - 1:0] m_tvalid,
    input logic [NUM - 1:0] m_tready
);

    logic [DW - 1:0] s_tdata_i;
    logic s_tvalid_i;
    logic s_tready_i;

    logic [DW*NUM-1:0] m_tdata_i;
    logic [NUM - 1:0] m_tvalid_i;
    logic [NUM - 1:0] m_tready_i;

    genvar gi;
    generate
        if (EN_IN_BUFFER) begin
            axis_skidbuffer #(
                .DW(DW)
            ) skid_in (
                .clk(clk),
                .reset_n(reset_n),

                .s_tdata (s_tdata),
                .s_tvalid(s_tvalid),
                .s_tready(s_tready),

                .m_tdata (s_tdata_i),
                .m_tvalid(s_tvalid_i),
                .m_tready(s_tready_i)
            );
        end else begin
            assign s_tdata_i  = s_tdata;
            assign s_tvalid_i = s_tvalid;
            assign s_tready   = s_tready_i;
        end
    endgenerate

    generate
        if (EN_OUT_BUFFER) begin
            for (gi = 0; gi < NUM; gi = gi + 1) begin
                axis_skidbuffer #(
                    .DW(DW)
                ) skid_out (
                    .clk(clk),
                    .reset_n(reset_n),

                    .s_tdata (m_tdata_i[DW*gi +: DW]),
                    .s_tvalid(m_tvalid_i[gi]),
                    .s_tready(m_tready_i[gi]),

                    .m_tdata (m_tdata[DW*gi +: DW]),
                    .m_tvalid(m_tvalid[gi]),
                    .m_tready(m_tready[gi])
                );
            end
        end else begin
            assign m_tdata = m_tdata_i;
            assign m_tvalid = m_tvalid_i;
            assign m_tready_i = m_tready;
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < NUM; i = i + 1) begin
            m_tdata_i[DW*i+:DW] = s_tdata_i;
        end
        // wait until all inputs are valid before asserting all treadys
        m_tvalid_i = (m_tready_i == {NUM{1'b1}}) ? {NUM{s_tvalid_i}} : 0;
        s_tready_i = (m_tready_i == {NUM{1'b1}}) ? 1 : 0;
    end
endmodule
