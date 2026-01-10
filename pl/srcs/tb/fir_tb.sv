//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description: test bench for xilinx fir filters
// verify data alignment, reload sequence, config interface etc
//
// Last update on Nov 19, 2025
//
// Copyright @ 2025
//

`timescale 1ns / 1ps

module fir_tb;

    // Parameters
    localparam int DW = 32;  // data width for both input and output
    localparam int COEFF_WIDTH = 16;
    localparam int SAMPLES_PER_CYCLE = 2;

    //Ports
    reg clk = 0;
    reg reset_n = 0;

    reg [7:0] config_tdata = 0;
    reg config_tvalid = 0;
    wire config_tready;

    reg [COEFF_WIDTH - 1:0] reload_tdata = 0;
    reg reload_tvalid = 0;
    wire reload_tready;
    reg reload_tlast = 0;

    reg [DW * SAMPLES_PER_CYCLE - 1:0] s_tdata = 0;
    reg s_tvalid = 0;
    reg s_tlast = 0;
    wire s_tready;

    wire [40 * 2 * SAMPLES_PER_CYCLE - 1:0] m_tdata;
    wire m_tvalid;
    reg m_tready = 0;

    parameter CLOCK_PERIOD = 4;

    fracDelayFIR dut (
        .aclk(clk),
        .aresetn(reset_n),

        .s_axis_reload_tdata (reload_tdata),
        .s_axis_reload_tvalid(reload_tvalid),
        .s_axis_reload_tready(reload_tready),
        .s_axis_reload_tlast (reload_tlast),

        .s_axis_config_tvalid(config_tvalid),
        .s_axis_config_tready(config_tready),
        .s_axis_config_tdata (config_tdata),

        .s_axis_data_tdata (s_tdata),
        .s_axis_data_tvalid(s_tvalid),
        .s_axis_data_tready(s_tready),

        .m_axis_data_tdata (m_tdata),
        .m_axis_data_tvalid(m_tvalid)
    );


    logic [15:0] a, b;
    initial begin
        $timeformat(-9, 2, " ns", 20);
        m_tready = 0;
        reset_task();

        @(posedge clk);
        for (int i = 0; i < 51; i++) begin
            while (!reload_tready) @(posedge clk);
            reload_tdata  <= i + 1;// 51 - i
            reload_tvalid <= 1;
            if (i == 50) begin
                reload_tlast <= 1;
            end else begin
                reload_tlast <= 0;
            end
            @(posedge clk);
            reload_tlast  <= 0;
            reload_tvalid <= 0;
            reload_tdata  <= 0;
        end

        repeat(8) @(posedge clk);

        config_tvalid <= 1;
        config_tdata  <= 8'h0;
        while (!config_tready) @(posedge clk);
        @(posedge clk);
        config_tvalid <= 0;
        config_tdata  <= 0;

        for (int i = 0; i < 1000; i++) begin
            s_tvalid <= 1;
            a = 2 * i + 1;
            b = 2 * (i + 1);
            s_tdata  <= {b, b, a, a};
            @(posedge clk);
            while (!s_tready) @(posedge clk);
            s_tvalid <= 0;
            s_tdata  <= 0;
        end
        $finish;
    end

    always #(CLOCK_PERIOD / 2) clk = !clk;

    // reset task
    task automatic reset_task;
        begin
            repeat (3) @(posedge clk);
            reset_n <= ~reset_n;
        end
    endtask

    task automatic axis_write;
        input int throttle;
        input string filename;
        begin
            int wait_n;  // for throttling
            logic [DW * SAMPLES_PER_CYCLE - 1:0] data;
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
            logic [DW * SAMPLES_PER_CYCLE - 1:0] ref_tdata;
            logic ref_tlast;
            logic [DW * SAMPLES_PER_CYCLE - 1:0] rxed;
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
