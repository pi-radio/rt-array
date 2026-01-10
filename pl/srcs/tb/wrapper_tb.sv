//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description: test bench for rt proc core test block design. 
// This tests the entire flow including the DMA, switch and AXI Lite control interface.
//
// Last update on Nov 19, 2025
//
// Copyright @ 2025
//

`include "../rtl/rt_proc_core.svh"

import axi_vip_pkg::*;
import design_1_axi_vip_0_0_pkg::*;  // master
import design_1_axi_vip_1_0_pkg::*;  // slave

`timescale 1ns / 1ps

module wrapper_tb;

    design_1_axi_vip_0_0_mst_t mst_agent;
    design_1_axi_vip_1_0_slv_mem_t slv_agent;

    localparam int AXIL_IO_BASE_ADDR = 'h0000_0000;
    localparam int AXIL_IO_CTRL_OFFSET = AXIL_IO_BASE_ADDR + 'h0000_0000;
    localparam int AXIL_IO_PHASE_OFFSET = AXIL_IO_BASE_ADDR + 'h0000_0004;

    localparam int DMA_BASE_ADDR = 'h41E0_0000;
    localparam int DMA_DMACR_OFFSET = DMA_BASE_ADDR + 'h0000_0000;  // control register
    localparam int DMA_DMASR_OFFSET = DMA_BASE_ADDR + 'h0000_0004;  // status register
    localparam int DMA_DMASA_OFFSET = DMA_BASE_ADDR + 'h0000_0018;  // MM2S source address
    localparam int DMA_DMASA_MSB_OFFSET = DMA_BASE_ADDR + 'h0000_001C;  // MM2S source address MSB
    localparam int DMA_DMATL_OFFSET = DMA_BASE_ADDR + 'h0000_0028;  // MM2S transfer length

    localparam int SWITCH_BASE_ADDR = 'h44A1_0000;
    localparam int SWITCH_CTRL_OFFSET = SWITCH_BASE_ADDR + 'h0000_0000;
    localparam int SWITCH_MUX_OFFSET = SWITCH_BASE_ADDR + 'h0000_0040;
    // Parameters
    localparam int DW = 32;  // data width for both input and output
    localparam int SAMPLES_PER_CLOCK = 2;
    localparam int COEFF_WIDTH = 16;
    localparam int DW_DATA = DW * SAMPLES_PER_CLOCK;

    //Ports
    reg clk = 0;
    reg reset_n = 0;

    reg clk_300 = 0;
    reg reset_n_300 = 0;

    reg axil_clk = 0;
    reg axil_reset_n = 0;

    reg [DW_DATA * `N_ANT - 1:0] s_tdata = 0;
    reg s_tvalid = 0;
    reg s_tlast = 0;
    wire s_tready;

    wire [DW_DATA * `N_ANT - 1:0] m_tdata;
    wire m_tvalid;
    reg m_tready = 0;

    parameter CLOCK_PERIOD = 4;  // 250 MHz
    parameter AXIL_CLK_PERIOD = 10;  // 100 MHz
    parameter CLK_300_PERIOD = 3.333;  // 300 MHz

    xil_axi_prot_t prot;
    xil_axi_uint   addr;
    xil_axi_uint wdata, rdata;
    xil_axi_resp_t bresp, rresp;

    class Tests;
        randc bit [1:0] index;
    endclass

    design_1_wrapper dut (
        .clk(clk),
        .reset_n(reset_n),

        .axil_clk(axil_clk),
        .axil_reset_n(axil_reset_n),

        .clk_300(clk_300),
        .reset_n_300(reset_n_300),

        .s_tdata (s_tdata),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),

        .m_tdata (m_tdata),
        .m_tvalid(m_tvalid),
        .m_tready(m_tready)
    );

    xpm_cdc_async_rst #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(1),
        .RST_ACTIVE_HIGH(0)
    ) xpm_cdc_reset_300 (
        .dest_arst(reset_n_300),
        .dest_clk (clk_300),
        .src_arst (axil_reset_n)
    );

    xpm_cdc_async_rst #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(1),
        .RST_ACTIVE_HIGH(0)
    ) xpm_cdc_reset (
        .dest_arst(reset_n),
        .dest_clk (clk),
        .src_arst (axil_reset_n)
    );

    // test flow
    // test init values
    // test tx bf with reloaded coefficients
    // test rx bf with reloaded coefficients
    // test tx bf with new coefficients
    initial begin
        Tests test = new();

        mst_agent = new("master vip agent", dut.design_1_i.axi_vip_0.inst.IF);
        mst_agent.set_agent_tag("Master VIP");
        mst_agent.vif_proxy.set_dummy_drive_type(XIL_AXI_VIF_DRIVE_NONE);
        mst_agent.set_verbosity(0);  // or XIL_AXI_VERBOSITY_DEBUG, etc.

        mst_agent.start_master();

        slv_agent = new("slave vip agent", dut.design_1_i.axi_vip_1.inst.IF);
        slv_agent.set_agent_tag("AXI DDR Model");
        slv_agent.set_verbosity(0);
        slv_agent.start_slave();

        prot = XIL_AXI_PROT_NORMAL_ACCESS_MASK;

        @(posedge axil_reset_n);
        @(posedge axil_clk);

        // read check
        $display("Reading initial AXIL IO registers:");
        for (int i = 0; i < `NCH + 1; i++) begin
            addr = AXIL_IO_BASE_ADDR + i * 4;
            mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);
            $display("AXIL IO Reg %0d: %h", i, rdata);
        end
        $display("Reading initial DMA registers:");
        // dma status check
        addr = DMA_BASE_ADDR + 'h00000000;  // DMACR
        mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);
        $display("DMA Control Reg: %h", rdata);
        addr = DMA_BASE_ADDR + 'h00000004;  // DMASR
        mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);
        $display("DMA Status Reg: %h", rdata);

        // write phase factors
        for (int i = 0; i < `NCH; i++) begin
            addr  = AXIL_IO_PHASE_OFFSET + i * 4;
            wdata = 32'h00007FFF;  // 1.0 in Q1.15
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
        end

        repeat (16) begin
            test.randomize();
            case (test.index)
                0: test_0();
                1: test_1();
                2: test_2();
                3: test_3();
                default: ;
            endcase
        end
        $finish;
    end

    initial begin
        $timeformat(-9, 2, " ns", 20);
        m_tready = 0;
        reset_task();
    end

    always #(CLOCK_PERIOD / 2) clk = !clk;
    always #(AXIL_CLK_PERIOD / 2) axil_clk = !axil_clk;
    always #(CLK_300_PERIOD / 2) clk_300 = !clk_300;

    // tests:
    // 0 - calibration mode
    // 1 - real time mode, tx bf, new coeffs
    // 2 - real time mode, rx bf, new coeffs
    // 3 - real time mode, tx bf, new phase factors
    // tests will run in random order
    task automatic test_0();
        begin
            $display("test 0: calibration mode: data passthru from demux to mux in the test");
            // set ctrl. format = 0xFIRRELOAD_00_TXRXMODE_OPMODE
            wdata = 32'h00_00_00_00;  // set to calibration mode
            addr  = AXIL_IO_CTRL_OFFSET;
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

            // write and expect the same data back
            fork
                axis_write(1, "input_tx.hex");
                axis_read(1, "input_tx.hex");
            join
            $display("test 0: done at %t", $time);
        end
    endtask

    task automatic test_1();
        begin
            $display("test 1: realtime correction mode, tx beamforming");
            // $display("test 1: data passthru from demux to mux in the test");
            // set ctrl. format = 0xFIRRELOAD_00_TXRXMODE_OPMODE
            wdata = 32'h00_00_00_01;  // set to correction mode, tx bf
            addr  = AXIL_IO_CTRL_OFFSET;
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

            reload_coeffs("memory_init_tx.hex");

            // write and expect the same data back
            fork
                axis_write(1, "input_tx.hex");
                axis_read(1, "output_tx.hex");
            join
            $display("test 1: done at %t", $time);
        end
    endtask

    task automatic test_2();
        begin
            $display("test 2: realtime correction mode, rx beamforming");
            // set ctrl. format = 0xFIRRELOAD_00_TXRXMODE_OPMODE
            wdata = 32'h00_00_01_01;  // set to correction mode, rx bf
            addr  = AXIL_IO_CTRL_OFFSET;
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

            reload_coeffs("memory_init_rx.hex");

            fork
                axis_write(1, "input_rx.hex");
                axis_read(1, "output_rx.hex");
            join
            $display("test 2: done at %t", $time);
        end
    endtask

    task automatic test_3();
        begin
            int fp;
            $display("test 3: realtime correction mode, tx beamforming, new phase factors");
            // set ctrl. format = 0xFIRRELOAD_00_TXRXMODE_OPMODE

            addr = AXIL_IO_CTRL_OFFSET;
            mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);

            // if the previous test was rx bf, reload tx coeffs
            if (rdata[0+:16] != 16'h00_01) begin
                reload_coeffs("memory_init_tx.hex");
            end
            // TODO: change phase factors here
            wdata = 32'h00_00_00_01;  // set to correction mode, tx bf
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

            fp = $fopen("phases.hex", "r");
            assert(fp != 0);
            // write phase factors
            for (int i = 0; i < `NCH; i++) begin
                $fscanf(fp, "%h", wdata);
                assert(!$isunknown(wdata));
                addr  = AXIL_IO_PHASE_OFFSET + i * 4;
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
            end
            $fclose(fp);

            fork
                axis_write(1, "input_phase.hex");
                axis_read(1, "output_phase.hex");
            join
            // setting phases to 0 for other tests
            for (int i = 0; i < `NCH; i++) begin
                wdata = 32'h0000_7FFF;
                addr  = AXIL_IO_PHASE_OFFSET + i * 4;
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
            end
            $display("test 3: done at %t", $time);
        end
    endtask

    task automatic ddr_read_check();
        begin
            bit [31:0] rd_data;
            xil_axi_ulong addr;
            for (int i = 0; i < 16; i++) begin
                addr = i * 4;
                rd_data = slv_agent.mem_model.backdoor_memory_read(addr);
                $display("%d: DDR Mem Addr %0d: %h", i, addr, rd_data);
            end
        end
    endtask

    task automatic ddr_load_mem(input string mem_file = "memory_init_tx.hex");
        begin
            bit [31:0] rd_data;
            xil_axi_ulong addr;
            int fp;
            fp = $fopen(mem_file, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end
            @(posedge clk);
            addr = 0;
            while ($fscanf(
                fp, "%h", rd_data
            ) == 1) begin
                slv_agent.mem_model.backdoor_memory_write(addr, rd_data);
                addr = addr + 4;
            end
            $fclose(fp);
        end
    endtask

    task automatic reload_coeffs(input string mem_file = "memory_init_tx.hex");
        begin
            $display("Reloading filter coefficients @ %t", $time);
            $display("Using memory file: %s", mem_file);
            ddr_load_mem(mem_file);
            for (int i = 0; i < 14; i++) begin
                addr  = SWITCH_BASE_ADDR + 'h00000040 + i * 4;  // MUX Selector registers
                wdata = 'h8000_0000;  // disable all master interfaces
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
            end

            // reload all fir filter coeffs
            for (int i = 0; i < 14; i++) begin
                addr  = SWITCH_MUX_OFFSET + 4 * i;  // MUX Selector registers
                wdata = 'h0000_0000;  // route slave 0 to master i
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

                // disable previous route
                if (i > 0) begin
                    addr  = SWITCH_MUX_OFFSET + 4 * (i - 1);  // MUX Selector registers
                    wdata = 'h8000_0000;  // disable all master interfaces
                    mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
                end

                addr  = SWITCH_CTRL_OFFSET;  // Switch control register
                wdata = 'h0000_0002;  // load config (self clearing)
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

                repeat (16)
                @(posedge axil_clk);  // wait for internal reset after issuing load command

                // trigger dma
                addr  = DMA_DMACR_OFFSET;  // AXI DMA MM2S control register (DMACR)
                wdata = 32'h00000001;  // start dma
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

                // write DMA descriptors
                addr = DMA_DMASA_OFFSET;  // AXI DMA MM2S Source addr. Lower 32 bits of addr
                if (i > 6)  // fir1
                    wdata = 32'h00000000 + 204 * 7 + 44 * (i - 7);  // source address
                else  // fir0
                    wdata = 32'h00000000 + 204 * i;  // source address
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

                addr = DMA_DMATL_OFFSET;  // AXI DMA MM2S Transfer Length in bytes
                if (i > 6)  // fir1
                    wdata = 32'h0000002C; // transfer length = 'h2C = 44 bytes = 11 coeffs * 4 bytes
                else  // fir0
                    wdata = 32'h000000CC; // transfer length = 'hCC = 204 bytes = 51 coeffs * 4 bytes
                mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);

                repeat (128) @(posedge axil_clk);
                // TODO: check dma status
                addr = DMA_DMASR_OFFSET;  // AXI DMA MM2S status register (DMASR)
                mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);

                // // check if dma is idle
                // while ((rdata & 32'h00000002) == 0) begin
                //     mst_agent.AXI4LITE_READ_BURST (addr, prot, rdata,  rresp);
                //     $display("DMA status: %h", rdata);
                // end
                $display("Reloaded filter bank %d @ %t", i, $time);
            end

            $display("Configuring FIR reload @ %t", $time);
            // set ctrl. format = 0xFIRRELOAD_00_TXRXMODE_OPMODE
            addr  = AXIL_IO_CTRL_OFFSET;
            mst_agent.AXI4LITE_READ_BURST(addr, prot, rdata, rresp);
            wdata = rdata | 32'h01_00_00_00; // trigger fir reload
            mst_agent.AXI4LITE_WRITE_BURST(addr, prot, wdata, bresp);
            $display("Reload done @ %t", $time);
        end
    endtask

    // reset task
    task automatic reset_task;
        begin
            repeat (64) @(posedge axil_clk);
            axil_reset_n = ~axil_reset_n;
        end
    endtask

    task automatic axis_write;
        input int throttle;
        input string filename;
        begin
            int wait_n;  // for throttling
            logic [DW_DATA * `N_ANT - 1:0] data;
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
            logic [DW_DATA * `N_ANT - 1:0] ref_tdata;
            logic ref_tlast;
            logic signed [16 - 1:0] rxed, gold;
            logic signed [16:0] diff;
            int fp;
            int count;
            int error_count;

            fp = $fopen(filename, "r");
            if (fp == 0) begin
                $fatal(1, "ERROR: could not open config file");
            end
            count = 0;
            error_count = 0;  
            @(posedge clk);
            while ($fscanf(
                fp, "%h,%d", ref_tdata, ref_tlast
            ) == 2) begin
                m_tready <= 1;
                @(posedge clk);
                while (!m_tvalid) @(posedge clk);
                m_tready <= 0;

                for (int i = 0; i < 2 * `N_ANT * SAMPLES_PER_CLOCK; i++) begin
                    if (i == 0) begin
                        count = count + 1;
                    end
                    rxed = m_tdata[i*16+:16];
                    gold = ref_tdata[i*16+:16];
                    diff = rxed - gold;
                    if ((abs(diff) > 7) & (count > 72)) begin
                        $display("%t: %d, ant %x: gold: %d, rxed: %d. diff = %d", $time, count,
                                 i / 4, gold, rxed, abs(diff));
                                 
//                        $stop;
                    end
                end

                wait_n = $urandom % backpr;
                repeat (wait_n) begin
                    @(posedge clk);
                end
            end
        end
    endtask

    function [16:0] abs(input signed [16:0] a);
        abs = (a < $signed(16'd0)) ? -a : a;
    endfunction

    // for printing internal values into files
    int fd;
    int count;
    initial begin
        fd = $fopen("fir_1.txt", "w");
        count = 0;
        @(posedge clk);
        while (count < 256) begin
            @(posedge clk);
            if (dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tvalid[0]) begin
                $fdisplay(fd, "%d %d %d %d %d %d %d",
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[0],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[2],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[4],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[6],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[8],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[10],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[12]);
                $fdisplay(fd, "%d %d %d %d %d %d %d",
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[1],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[3],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[5],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[7],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[9],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[11],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir1_tdata_i[13]);
                count = count + 1;
            end
        end
        $fclose(fd);
    end

    int fd_1;
    int count_1;
    initial begin
        fd_1 = $fopen("fir_0.txt", "w");
        count_1 = 0;
        @(posedge clk);
        while (count_1 < 256) begin
            @(posedge clk);
            if (dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tvalid[0]) begin
                $fdisplay(fd_1, "%d %d %d %d %d %d %d",
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[0],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[2],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[4],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[6],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[8],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[10],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[12]);
                $fdisplay(fd_1, "%d %d %d %d %d %d %d",
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[1],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[3],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[5],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[7],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[9],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[11],
                          dut.design_1_i.rt_proc_core_v_0.inst.rt_proc_core_inst.fir0_tdata_i[13]);
                count_1 = count_1 + 1;
            end
        end
        $fclose(fd_1);
    end
endmodule
