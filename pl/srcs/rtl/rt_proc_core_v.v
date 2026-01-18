//
// Company: Pi-Radio
//
// Engineer: Nikhil Reddy
//
// Description:
//
// Last update on Sep 24, 2025
//
// Copyright @ 2025
//

`timescale 1ns / 1ps

module rt_proc_core_v #(
    parameter integer DW                = 32,
    parameter integer SAMPLES_PER_CLOCK = 2,
    parameter integer N_ANT             = 8,
    parameter integer NCH               = 14,
    parameter integer COEFF_WIDTH       = 16,

    // axil parameters
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 8,
    parameter integer STRB_WIDTH = (DATA_WIDTH / 8)
) (
    input wire clk,
    input wire reset_n,

    input wire axil_clk,
    input wire axil_reset_n,

    // axi4-lite interface
    input  wire [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire [           2:0] s_axil_awprot,   // unused
    input  wire                  s_axil_awvalid,
    output wire                  s_axil_awready,
    input  wire [DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [STRB_WIDTH-1:0] s_axil_wstrb,
    input  wire                  s_axil_wvalid,
    output wire                  s_axil_wready,
    output wire [           1:0] s_axil_bresp,
    output wire                  s_axil_bvalid,
    input  wire                  s_axil_bready,
    input  wire [ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire [           2:0] s_axil_arprot,   // unused
    input  wire                  s_axil_arvalid,
    output wire                  s_axil_arready,
    output wire [DATA_WIDTH-1:0] s_axil_rdata,
    output wire [           1:0] s_axil_rresp,
    output wire                  s_axil_rvalid,
    input  wire                  s_axil_rready,

    // combined both ports so that it can be connected to switch easily
    input  wire [32 * NCH - 1:0] tx_fir_reload_tdata,
    input  wire [     NCH - 1:0] tx_fir_reload_tvalid,
    output wire [     NCH - 1:0] tx_fir_reload_tready,
    input  wire [     NCH - 1:0] tx_fir_reload_tlast,

    input  wire [32 * NCH - 1:0] rx_fir_reload_tdata,
    input  wire [     NCH - 1:0] rx_fir_reload_tvalid,
    output wire [     NCH - 1:0] rx_fir_reload_tready,
    input  wire [     NCH - 1:0] rx_fir_reload_tlast,

    output wire [1:0] operation_mode,

    // from adc0 to adc7
    input  wire [DW * SAMPLES_PER_CLOCK * N_ANT - 1:0] s_tdata,
    input  wire                                        s_tvalid,
    output wire                                        s_tready,
    // output wire s_tready, // no backpressure in real time processing

    // to dac0 to dac7
    output wire [DW * SAMPLES_PER_CLOCK * N_ANT - 1:0] m_tdata,
    output wire                                        m_tvalid
    // input wire m_tready  // no backpressure in real time processing
);

    reg     [           COEFF_WIDTH * NCH/2 - 1:0] tx_fir0_reload_tdata_i;
    reg     [           COEFF_WIDTH * NCH/2 - 1:0] tx_fir1_reload_tdata_i;

    reg     [                         NCH/2 - 1:0] tx_fir0_reload_tvalid_i;
    reg     [                         NCH/2 - 1:0] tx_fir1_reload_tvalid_i;

    reg     [           COEFF_WIDTH * NCH/2 - 1:0] rx_fir0_reload_tdata_i;
    reg     [           COEFF_WIDTH * NCH/2 - 1:0] rx_fir1_reload_tdata_i;

    reg     [                         NCH/2 - 1:0] rx_fir0_reload_tvalid_i;
    reg     [                         NCH/2 - 1:0] rx_fir1_reload_tvalid_i;

    reg     [DW * SAMPLES_PER_CLOCK * N_ANT - 1:0] s_tdata_i;
    reg     [DW * SAMPLES_PER_CLOCK * N_ANT - 1:0] m_tdata_i;

    // pikcing 16 bits out of incoming 32-bit data from DMA
    integer                                        i;
    always @(*) begin
        // tx
        for (i = 0; i < NCH / 2; i = i + 1) begin
            tx_fir0_reload_tdata_i[COEFF_WIDTH*i+:COEFF_WIDTH] =
                tx_fir_reload_tdata[32*i+:COEFF_WIDTH];
            tx_fir1_reload_tdata_i[COEFF_WIDTH*i+:COEFF_WIDTH] =
                tx_fir_reload_tdata[32*NCH/2+32*i+:COEFF_WIDTH];

            tx_fir0_reload_tvalid_i[i] = tx_fir_reload_tvalid[i];
            tx_fir1_reload_tvalid_i[i] = tx_fir_reload_tvalid[7+i];
        end
        // rx
        for (i = 0; i < NCH / 2; i = i + 1) begin
            rx_fir0_reload_tdata_i[COEFF_WIDTH*i+:COEFF_WIDTH] =
                rx_fir_reload_tdata[32*i+:COEFF_WIDTH];
            rx_fir1_reload_tdata_i[COEFF_WIDTH*i+:COEFF_WIDTH] =
                rx_fir_reload_tdata[32*NCH/2+32*i+:COEFF_WIDTH];

            rx_fir0_reload_tvalid_i[i] = rx_fir_reload_tvalid[i];
            rx_fir1_reload_tvalid_i[i] = rx_fir_reload_tvalid[7+i];
        end
    end

    // changing the interface ordering. 
    always @(*) begin
        for (i = 0; i < N_ANT; i = i + 1) begin  // adc -> core
            s_tdata_i[64*i+0+:16]  = s_tdata[64*i+0+:16];  // i0  -> i0
            s_tdata_i[64*i+16+:16] = s_tdata[64*i+32+:16];  // i1  -> q0
            s_tdata_i[64*i+32+:16] = s_tdata[64*i+16+:16];  // q0  -> i1
            s_tdata_i[64*i+48+:16] = s_tdata[64*i+48+:16];  // q1  -> q1
        end
    end

    rt_proc_core #(
        .DW         (DW),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) rt_proc_core_inst (
        .clk    (clk),
        .reset_n(reset_n),

        .axil_clk    (axil_clk),
        .axil_reset_n(axil_reset_n),

        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_awprot (s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid),
        .s_axil_wready (s_axil_wready),
        .s_axil_bresp  (s_axil_bresp),
        .s_axil_bvalid (s_axil_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_arprot (s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata  (s_axil_rdata),
        .s_axil_rresp  (s_axil_rresp),
        .s_axil_rvalid (s_axil_rvalid),
        .s_axil_rready (s_axil_rready),

        .operation_mode(operation_mode),

        .tx_fir0_reload_tdata (tx_fir0_reload_tdata_i),
        .tx_fir0_reload_tvalid(tx_fir0_reload_tvalid_i),
        .tx_fir0_reload_tready(tx_fir_reload_tready[6:0]),
        .tx_fir0_reload_tlast (tx_fir_reload_tlast[6:0]),

        .tx_fir1_reload_tdata (tx_fir1_reload_tdata_i),
        .tx_fir1_reload_tvalid(tx_fir1_reload_tvalid_i),
        .tx_fir1_reload_tready(tx_fir_reload_tready[13:7]),
        .tx_fir1_reload_tlast (tx_fir_reload_tlast[13:7]),

        .rx_fir0_reload_tdata (rx_fir0_reload_tdata_i),
        .rx_fir0_reload_tvalid(rx_fir0_reload_tvalid_i),
        .rx_fir0_reload_tready(rx_fir_reload_tready[6:0]),
        .rx_fir0_reload_tlast (rx_fir_reload_tlast[6:0]),

        .rx_fir1_reload_tdata (rx_fir1_reload_tdata_i),
        .rx_fir1_reload_tvalid(rx_fir1_reload_tvalid_i),
        .rx_fir1_reload_tready(rx_fir_reload_tready[13:7]),
        .rx_fir1_reload_tlast (rx_fir_reload_tlast[13:7]),

        .s_tdata (s_tdata),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),

        .m_tdata (m_tdata),
        .m_tvalid(m_tvalid)
    );

endmodule
