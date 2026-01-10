//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
//
// Copyright © 2025 Allola Nikhil Reddy
//
// Module: axis_skidbuffer.sv
// Description: AXIS register slice with both forward & reverse paths registered
// Repo: https://github.com/nikhred/sv-foundry
// Author: Nikhil Reddy
// Date: 03-02-2024
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axis_skidbuffer #(
    parameter int DW = 8
) (
    input clk,
    input reset_n,

    input logic [DW - 1:0] s_tdata,
    input logic s_tvalid,
    output logic s_tready,

    output logic [DW - 1:0] m_tdata,
    output logic m_tvalid,
    input logic m_tready
);

    reg tvalid = 0;
    assign m_tvalid = tvalid;

    logic [DW - 1:0] skid_tdata;
    // initially empty
    reg skid_full = 0;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            m_tdata <= 0;
        end else begin
            if (m_tready || !tvalid) begin
                // read from skid if its full, directly read from input otherwise
                if (skid_full) begin
                    m_tdata <= skid_tdata;
                end else begin
                    m_tdata <= s_tdata;
                end
            end
        end
    end

    // note: output registers are always enabled by m_tready & !tvalid
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            tvalid <= 0;
        end else begin
            // if there is input data or if there is data in the buffer, send it out
            if (m_tready || !tvalid) begin
                tvalid <= skid_full || s_tvalid;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            skid_tdata <= 0;
        end else begin
            // store every data in the skid, can add additional conditions to avoid doing this but is it required?
            if (s_tready && s_tvalid) begin
                skid_tdata <= s_tdata;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            skid_full <= 0;
        end else begin
            // buffer will be full once output is stalled but input is still flowing
            if ((tvalid && !m_tready) && (s_tready && s_tvalid)) begin
                skid_full <= 1;
            end else if (m_tready) begin  // and emptied once m_tready goes high
                skid_full <= 0;
            end
        end
    end

    // set high until skid is full
    assign s_tready = !skid_full;

`ifdef FORMAL
    // assume tvalid goes high at least one cycle after reset release
    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    always_comb
        if (!f_past_valid)
            assume(!reset_n);

    always @(posedge clk) begin
        if(!f_past_valid || $past(!reset_n)) begin
            assume(!s_tvalid);
            assert(!m_tvalid);
        end else begin
            if($past(m_tvalid & !m_tready)) begin
                assert(m_tvalid);
                assert($stable(m_tdata));
            end
        end
    end
`endif
endmodule