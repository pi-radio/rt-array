//------------------------------------------------------------------------------
// Module: xcmult.sv
// Description: Complex Multiply block from Xilinx for US+ arch
//
// Repo: https://github.com/nikhred/sv-foundry
// Author: @nikhred (Nikhil Reddy)
// Date: 31-10-2025
//
// (pr+i.pi) = (ar+i.ai)*(br+i.bi)
// This can be packed into 3 DSP blocks (Ultrascale architecture)
// Make sure the widths are less than what is supported by the architecture
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module xcmult #(
    parameter int W_A = 16,
    parameter int I_A = 15,
    parameter int W_B = 16,
    parameter int I_B = 15,
    parameter int W_P = 16,
    parameter int I_P = 14
) (
    input              clk,
    input              en,
    input  [2*W_A-1:0] a,
    input  [2*W_B-1:0] b,
    output [2*W_P-1:0] p
);
    localparam int F_A = W_A - I_A;
    localparam int F_B = W_B - I_B;
    localparam int F_P = W_P - I_P;
    localparam int F_P_INT = F_A + F_B;
    localparam int SHIFT = (F_P_INT - F_P);

    logic signed [W_A-1:0] ai_d, ai_dd, ai_ddd, ai_dddd;
    logic signed [W_A-1:0] ar_d, ar_dd, ar_ddd, ar_dddd;
    logic signed [W_B-1:0] bi_d, bi_dd, bi_ddd, br_d, br_dd, br_ddd;
    logic signed [W_A:0] addcommon;
    logic signed [W_B:0] addr, addi;
    logic signed [W_A+W_B:0] mult0, multr, multi;
    logic signed [W_A+W_B+1:0] pr_int, pi_int;
    logic signed [W_A+W_B:0] common, commonr1, commonr2;

    logic signed [W_A - 1:0] ar, ai;
    logic signed [W_B - 1:0] br, bi;
    logic signed [W_P - 1:0] pr, pi;

    assign ar = a[0+:W_A];
    assign ai = a[W_A+:W_A];
    assign br = b[0+:W_B];
    assign bi = b[W_B+:W_B];
    assign p  = {pi, pr};

    always_comb begin
        if (SHIFT > 0) begin
            pr = pr_int >>> SHIFT;
            pi = pi_int >>> SHIFT;
        end else begin
            pr = pr_int <<< (-SHIFT);
            pi = pi_int <<< (-SHIFT);
        end
    end

    always @(posedge clk) begin
        if (en) begin
            ar_d   <= ar;
            ar_dd  <= ar_d;
            ai_d   <= ai;
            ai_dd  <= ai_d;
            br_d   <= br;
            br_dd  <= br_d;
            br_ddd <= br_dd;
            bi_d   <= bi;
            bi_dd  <= bi_d;
            bi_ddd <= bi_dd;
        end
    end

    // Common factor (ar ai) x bi, shared for the calculations of the real and imaginary final products
    always @(posedge clk) begin
        if (en) begin
            addcommon <= ar_d - ai_d;
            mult0     <= addcommon * bi_dd;
            common    <= mult0;
        end
    end

    // Real product
    always @(posedge clk) begin
        if (en) begin
            ar_ddd   <= ar_dd;
            ar_dddd  <= ar_ddd;
            addr     <= br_ddd - bi_ddd;
            multr    <= addr * ar_dddd;
            commonr1 <= common;
            pr_int   <= multr + commonr1;
        end
    end

    // Imaginary product
    always @(posedge clk) begin
        if (en) begin
            ai_ddd   <= ai_dd;
            ai_dddd  <= ai_ddd;
            addi     <= br_ddd + bi_ddd;
            multi    <= addi * ai_dddd;
            commonr2 <= common;
            pi_int   <= multi + commonr2;
        end
    end

endmodule  // xcmult
