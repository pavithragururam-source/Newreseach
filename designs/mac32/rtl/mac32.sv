`timescale 1ns/1ps
// 3-stage pipelined signed 32x32 MAC with 64-bit accumulator
// Latency: 3 cycles
module mac32 #(
    parameter DW = 32,
    parameter AW = 64
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 en,
    input  logic                 clr,
    input  logic signed [DW-1:0] a,
    input  logic signed [DW-1:0] b,
    output logic signed [AW-1:0] acc_out,
    output logic                 overflow
);

    logic signed [DW-1:0] a_r, b_r;
    always_ff @(posedge clk) begin
        if (!rst_n)   { a_r, b_r } <= '0;
        else if (en)  { a_r, b_r } <= { a, b };
    end

    logic signed [2*DW-1:0] mul_r;
    always_ff @(posedge clk) begin
        if (!rst_n)  mul_r <= '0;
        else         mul_r <= a_r * b_r;
    end

    logic signed [AW-1:0] acc_r;
    logic                  ov_r;
    always_ff @(posedge clk) begin
        if (!rst_n || clr) begin
            acc_r <= '0;
            ov_r  <= 1'b0;
        end else begin
            { ov_r, acc_r } <= acc_r + {{(AW-2*DW){mul_r[2*DW-1]}}, mul_r};
        end
    end

    assign acc_out  = acc_r;
    assign overflow = ov_r;

endmodule
