
`timescale 1ns / 1ps

module axil_io #(
    parameter integer N_REGS = 64,
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 8,
    parameter integer STRB_WIDTH = (DATA_WIDTH / 8)
) (
    input                        clk,
    input                        reset_n,
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
    output reg                   s_axil_bvalid,
    input  wire                  s_axil_bready,
    input  wire [ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire [           2:0] s_axil_arprot,   // unused
    input  wire                  s_axil_arvalid,
    output wire                  s_axil_arready,
    output reg  [DATA_WIDTH-1:0] s_axil_rdata,
    output wire [           1:0] s_axil_rresp,
    output reg                   s_axil_rvalid,
    input  wire                  s_axil_rready

    // user ports here
    , output reg [224 - 1:0] phase,
    output reg [1:0] operation_mode,
    output reg tx_rx,

    output reg [7:0] fir0_tdata,
    output reg fir0_tvalid,
    input reg fir0_tready,

    output reg [7:0] fir1_tdata,
    output reg fir1_tvalid,
    input reg fir1_tready
);

    reg [DATA_WIDTH-1:0] reg_space[0:N_REGS-1];
    wire [ADDR_WIDTH - 2 - 1:0] idx_r, idx_w;

    wire [DATA_WIDTH-1:0] s_axil_wdata_i;
    wire [STRB_WIDTH-1:0] s_axil_wstrb_i;
    wire                  s_axil_wvalid_i;

    wire [ADDR_WIDTH-1:0] s_axil_awaddr_i;
    wire                  s_axil_awvalid_i;

    wire [ADDR_WIDTH-1:0] s_axil_araddr_i;
    wire                  s_axil_arvalid_i;

    wire                  wready;
    wire                  rready;

    // write addr channel
    axis_skidbuffer #(
        .DW(ADDR_WIDTH)
    ) inst_awaddr (
        .clk    (clk),
        .reset_n(reset_n),

        .s_tvalid(s_axil_awvalid),
        .s_tready(s_axil_awready),
        .s_tdata (s_axil_awaddr),

        .m_tvalid(s_axil_awvalid_i),
        .m_tready(wready),
        .m_tdata (s_axil_awaddr_i)
    );

    // write data channel
    axis_skidbuffer #(
        .DW(DATA_WIDTH + STRB_WIDTH)
    ) inst_wdata (
        .clk(clk),
        .reset_n(reset_n),

        .s_tvalid(s_axil_wvalid),
        .s_tready(s_axil_wready),
        .s_tdata ({s_axil_wdata, s_axil_wstrb}),

        .m_tvalid(s_axil_wvalid_i),
        .m_tready(wready),
        .m_tdata ({s_axil_wdata_i, s_axil_wstrb_i})
    );

    // read addr channel
    axis_skidbuffer #(
        .DW(ADDR_WIDTH)
    ) inst_araddr (
        .clk(clk),
        .reset_n(reset_n),

        .s_tvalid(s_axil_arvalid),
        .s_tready(s_axil_arready),
        .s_tdata (s_axil_araddr),

        .m_tvalid(s_axil_arvalid_i),
        .m_tready(rready),
        .m_tdata (s_axil_araddr_i)
    );


    assign s_axil_rresp = 0;
    assign s_axil_bresp = 0;

    // write response valid
    initial s_axil_bvalid = 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            s_axil_bvalid <= 0;
        end else begin
            if (wready) begin
                s_axil_bvalid <= 1;
            end else if (s_axil_bready) begin
                s_axil_bvalid <= 0;
            end
        end
    end

    // read data valid
    initial s_axil_rvalid = 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            s_axil_rvalid <= 0;
        end else begin
            if (rready) begin
                s_axil_rvalid <= 1;
            end else if (s_axil_rready) begin
                s_axil_rvalid <= 0;
            end
        end
    end

    // rdata block
    assign idx_r = s_axil_araddr_i[ADDR_WIDTH-1:2];  // 4 bytes per register fixed for axi lite
    always @(posedge clk) begin
        if (s_axil_rready || !s_axil_rvalid) begin
            s_axil_rdata <= reg_space[idx_r];
        end
    end

    // wdata block
    assign idx_w = s_axil_awaddr_i[ADDR_WIDTH-1:2];
    always @(posedge clk) begin
        if (!reset_n) begin
            for (int i = 0; i < N_REGS; i++) begin
                reg_space[i] <= 0;
            end
        end else begin
            if (wready && (state == RD_PARAM)) begin
                for (int i = 0; i < 4; i++) begin
                    if (s_axil_wstrb_i[i]) begin
                        reg_space[idx_w][8*i+:8] <= s_axil_wdata_i[8*i+:8];
                    end
                end
            end else if (state == CLEAR) begin
                reg_space[0] <= reg_space[0] & 32'h00FF_FFFF;
            end
        end
    end

    // TODO: disable wready when not in RD_PARAM state?
    assign wready = s_axil_wvalid_i && s_axil_awvalid_i && (!s_axil_bvalid || s_axil_bready) && (state == RD_PARAM);
    // assert rready after arvalid and clear after transfer is done
    assign rready = s_axil_arvalid_i && (!s_axil_rvalid || s_axil_rready);
    logic fir_reload;

    always_comb begin
        // reg_space[0]:
        // 0 for calibration, correction(real time) otherwise
        operation_mode = reg_space[0][0 +: 2];
        tx_rx = (reg_space[0][8 +: 8] != 0); // 0 for tx, 1 for rx
        // phase_reload = (reg_space[0][16 +: 8] == 0); // self clearing
        fir_reload = (reg_space[0][24 +: 8] != 0); // self clearing

        for (int i = 0; i < 7; i++) begin
            phase[32*i+:32] = reg_space[i + 1];
        end
    end

    // axis state machine handling
    enum logic [1:0] {
        RD_PARAM,
        WR_FIR0,
        WR_FIR1,
        CLEAR
    }
        state, next;

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
                if (fir_reload) begin
                    next = WR_FIR0;
                end
            end
            WR_FIR0: begin
                if (fir0_tvalid & fir0_tready) begin
                    next = WR_FIR1;
                end
            end
            WR_FIR1: begin
                if (fir1_tvalid & fir1_tready) begin
                    next = CLEAR;
                end
            end
            CLEAR: begin
                next = RD_PARAM;
            end
        endcase
    end

    always_comb begin
        // defaults
        fir0_tvalid = 1'b0;
        fir1_tvalid = 1'b0;

        fir0_tdata = 8'd0;
        fir1_tdata = 8'd0;

        case (state)
            WR_FIR0: begin
                fir0_tvalid = 1'b1;
            end
            WR_FIR1: begin
                fir1_tvalid = 1'b1;
            end
            default: begin
                fir0_tvalid = 0;
                fir1_tvalid = 0;
            end
        endcase
    end
endmodule
