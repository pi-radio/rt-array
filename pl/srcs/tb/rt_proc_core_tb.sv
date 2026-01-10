//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description: test bench for rt proc core module
//
// Last update on Nov 19, 2025
//
// Copyright @ 2025
//
`include "../rtl/rt_proc_core.svh"

`timescale 1ns / 1ps

module rt_proc_core_tb;

    // Parameters
    localparam int DW = 32;  // data width for both input and output
    localparam int COEFF_WIDTH = 16;

    //Ports
    reg clk = 0;
    reg reset_n = 0;

    rt_proc_ctrl_t ctrl;

    reg [COEFF_WIDTH * `NCH - 1:0] fir0_reload_tdata = 0;
    reg [`NCH - 1:0] fir0_reload_tvalid = 0;
    wire [`NCH - 1:0] fir0_reload_tready;
    reg [`NCH - 1:0] fir0_reload_tlast = 0;

    reg [COEFF_WIDTH * `NCH - 1:0] fir1_reload_tdata = 0;
    reg [`NCH - 1:0] fir1_reload_tvalid = 0;
    wire [`NCH - 1:0] fir1_reload_tready;
    reg [`NCH - 1:0] fir1_reload_tlast = 0;

    reg [DW * `N_ANT - 1:0] s_tdata = 0;
    reg s_tvalid = 0;
    reg s_tlast = 0;
    wire s_tready;

    wire [DW * `N_ANT - 1:0] m_tdata;
    wire m_tvalid;
    reg m_tready = 0;

    parameter CLOCK_PERIOD = 4;

    rt_proc_core #(
        .DW(DW),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) rt_proc_core_inst (
        .clk(clk),
        .reset_n(reset_n),

        .ctrl(ctrl),

        .fir0_reload_tdata (fir0_reload_tdata),
        .fir0_reload_tvalid(fir0_reload_tvalid),
        .fir0_reload_tready(fir0_reload_tready),
        .fir0_reload_tlast (fir0_reload_tlast),

        .fir1_reload_tdata (fir1_reload_tdata),
        .fir1_reload_tvalid(fir1_reload_tvalid),
        .fir1_reload_tready(fir1_reload_tready),
        .fir1_reload_tlast (fir1_reload_tlast),

        .s_tdata (s_tdata),
        .s_tvalid(s_tvalid),
        // .s_tlast (s_tlast),
        .s_tready(s_tready),

        .m_tdata (m_tdata),
        .m_tvalid(m_tvalid)
        // .m_tready(m_tready)
    );


    initial begin
        $timeformat(-9, 2, " ns", 20);
        m_tready = 0;
        ctrl = 0;
        reset_task();

        // ctrl.tx_phase = 32'h0000_4000; // 90 degrees
        ctrl.mode = 1'b0;  // operation mode - set to real time mode
        ctrl.phase_reload = 1'b0;
        ctrl.fir0_reload = 1'b0;
        ctrl.fir1_reload = 1'b0;

        for (int i = 0; i < `NCH; i++) begin
            // q1.15 format
            ctrl.phase[i] = 32'h0000_7FFF;  // 0 degrees
        end

        // load tx correction factors
        coeff_0_reload(1, "coeffs_0_tx.hex");
        coeff_1_reload(1, "coeffs_1_tx.hex");

        @(posedge clk);
        ctrl.phase_reload = 1'b1;
        @(posedge clk);
        ctrl.phase_reload = 1'b0;
        @(posedge clk);
        ctrl.fir0_reload = 1'b1;
        @(posedge clk);
        ctrl.fir0_reload = 1'b0;
        @(posedge clk);
        ctrl.fir1_reload = 1'b1;
        @(posedge clk);
        ctrl.fir1_reload = 1'b0;
        @(posedge clk);
        fork
            axis_write(1, "input_tx.hex");
            axis_read(1, "output_tx.hex");
        join
        // load rx correction factors
        coeff_0_reload(1, "coeffs_0_rx.hex");
        coeff_1_reload(1, "coeffs_1_rx.hex");
        @(posedge clk);
        ctrl.fir0_reload = 1'b1;
        @(posedge clk);
        ctrl.fir0_reload = 1'b0;
        @(posedge clk);
        ctrl.fir1_reload = 1'b1;
        @(posedge clk);
        ctrl.fir1_reload = 1'b0;
        @(posedge clk);
        fork
            axis_write(1, "input_rx.hex");
            axis_read(1, "output_rx.hex");
        join
        $finish;
    end

    always #(CLOCK_PERIOD / 2) clk = !clk;

    // reset task
    task automatic reset_task;
        begin
            repeat (3) @(posedge clk);
            reset_n = ~reset_n;
        end
    endtask

    task automatic coeff_0_reload;
        input int throttle;
        input string filename;
        begin
            int wait_n;  // for throttling
            logic [COEFF_WIDTH * `NCH - 1:0] data;
            logic last;
            int status;
            int fp;

            fp = $fopen(filename, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end

            wait (reset_n);
            @(posedge clk);
            while ($fscanf(
                fp, "%h,%d", data, last
            ) == 2) begin
                fir0_reload_tvalid <= 'h7f;
                fir0_reload_tdata  <= data;
                fir0_reload_tlast  <= {`NCH{last}};
                @(posedge clk);
                // all ips are expected to generate same tready
                while (!fir0_reload_tready[0]) @(posedge clk);
                fir0_reload_tvalid <= 0;
                fir0_reload_tlast <= 0;

                wait_n = $urandom % throttle;
                repeat (wait_n) begin
                    @(posedge clk);
                end
            end
        end
    endtask

    task automatic coeff_1_reload;
        input int throttle;
        input string filename;
        begin
            int wait_n;  // for throttling
            logic [COEFF_WIDTH * `NCH - 1:0] data;
            logic last;
            int status;
            int fp;

            fp = $fopen(filename, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end

            wait (reset_n);
            @(posedge clk);
            while ($fscanf(
                fp, "%h,%d", data, last
            ) == 2) begin
                fir1_reload_tvalid <= 'h7f;
                fir1_reload_tdata  <= data;
                fir1_reload_tlast  <= {`NCH{last}};
                @(posedge clk);
                while (!fir1_reload_tready[0]) @(posedge clk);
                fir1_reload_tvalid <= 0;
                fir1_reload_tlast  <= 0;

                wait_n = $urandom % throttle;
                repeat (wait_n) begin
                    @(posedge clk);
                end
            end
        end
    endtask

    task automatic axis_write;
        input int throttle;
        input string filename;
        begin
            int wait_n;  // for throttling
            logic [DW * `N_ANT - 1:0] data;
            logic last;
            int status;
            int fp;

            fp = $fopen(filename, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end

            wait (reset_n);
            @(posedge clk);
            while ($fscanf(
                fp, "%h,%d", data, last
            ) == 2) begin
                s_tvalid <= 1;
                s_tdata  <= data;
                s_tlast  <= last;
                @(posedge clk);
                while (!s_tready) @(posedge clk);
                s_tvalid <= 0;

                wait_n = $urandom % throttle;
                repeat (wait_n) begin
                    @(posedge clk);
                end
            end
        end
    endtask

    task automatic axis_read;
        input int backpr;
        input string filename;
        begin
            int wait_n;
            logic [DW * `N_ANT - 1:0] ref_tdata;
            logic ref_tlast;
            logic [DW * `N_ANT- 1:0] rxed;
            int fp;

            fp = $fopen(filename, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end
            @(posedge clk);
            while ($fscanf(
                fp, "%h,%d", ref_tdata, ref_tlast
            ) == 2) begin
                m_tready <= 1;
                @(posedge clk);
                while (!m_tvalid) @(posedge clk);
                m_tready <= 0;

                // rxed = m_tdata[DW/2-1:0];
                // if (((rxed - ref_tdata) > 0) || ((ref_tdata - rxed) > 0)) begin
                //     $display("expected %t %d, value %d. diff %d %d", $time, ref_tdata, rxed,
                //              (rxed - ref_tdata), (ref_tdata - rxed));
                //     //                    $stop;
                // end
                wait_n = $urandom % backpr;
                repeat (wait_n) begin
                    @(posedge clk);
                end
            end
        end
    endtask
endmodule
