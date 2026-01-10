//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description: module to control the calibration flow. It talks to the host, gathers results
// and controls the flow based on expType
//
// Last update on Sep 24, 2025
//
// Copyright @ 2025
//

`timescale 1ns / 1ps

`include "rt_proc_core.svh"

module rt_proc_ctrl (
    input clk,
    input reset_n,

    // gpio control from PS
    input rt_proc_ctrl_t ctrl,

    output fir_t fir0_tdata,
    output logic fir0_tvalid,
    input logic fir0_tready,

    output fir_t fir1_tdata,
    output logic fir1_tvalid,
    input logic fir1_tready
);

    fir_t wr_fir;

    enum logic [1:0] {RD_PARAM, WR_FIR0, WR_FIR1} state, next;

    always_ff @(posedge clk) begin
        if (~reset_n) begin
            state <= RD_PARAM;
        end else begin
            state <= next;
        end
    end

    always_comb begin
        next = state;
        case (state)
            RD_PARAM: begin
                if(ctrl.fir0_reload) begin
                    next = WR_FIR0;
                end else if (ctrl.fir1_reload) begin
                    next = WR_FIR1;
                end
            end
            WR_FIR0: begin
                if (fir0_tvalid & fir0_tready) begin
                    next = RD_PARAM;
                end
            end
            WR_FIR1: begin
                if (fir1_tvalid & fir1_tready) begin
                    next = RD_PARAM;
                end
            end
        endcase
    end

    always_comb begin
        // defaults
        fir0_tvalid = 1'b0;
        fir1_tvalid = 1'b0;

        wr_fir = 0;

        fir0_tdata = wr_fir;
        fir1_tdata = wr_fir;

        case (state)
            WR_FIR0: begin
                fir0_tvalid = 1'b1;
            end
            WR_FIR1: begin
                fir1_tvalid = 1'b1;
            end
        endcase
    end
endmodule
