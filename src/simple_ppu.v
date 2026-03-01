/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module simple_ppu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  // states
  localparam WAIT_IN1 = 2'b00;
  localparam WAIT_IN2_INST = 2'b01;
  localparam COMPUTING = 2'b10;
  localparam COMPLETE = 2'b11;

  reg [1:0] ppu_state_d, ppu_state_q;
  wire input1_valid, input2_valid, instruction_valid, ready_in, ready_out;
  
  assign instruction_valid = ui_in[2];
  assign input1_valid = ui_in[0];
  assign input2_valid = ui_in[1];
  assign ready_in = ui_in[5];

  reg [7:0] input1_reg_d, input2_reg_d, input1_reg_q, input2_reg_q, output_reg_d, output_reg_q, opcode_reg_d, opcode_reg_q;

  //FSM transition logic
  always @(*) begin
    ppu_state_d = ppu_state_q;

    case(ppu_state_q)
        WAIT_IN1: begin
            if(input1_valid & ~input2_valid) ppu_state_d = WAIT_IN2_INST;
        end
        WAIT_IN2_INST: begin
            if(input2_valid & instruction_valid & ~input1_valid) ppu_state_d = COMPUTING;
        end
        COMPUTING: begin
            if(done) ppu_state_d = COMPLETE;
        end
        COMPLETE: begin
            if(ready_in) ppu_state_d = WAIT_IN1;
        end
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ppu_state_q <= WAIT_IN1;
    end else if (ena) begin
        ppu_state_q <= ppu_state_d;
    end
  end
  
  //INPUT/OUTPUT LOGIC
  always @(*) begin
    uio_oe = 1;
    opcode_reg_d = 2'b0;
    case(ppu_state_q)
        WAIT_IN1: begin
            uio_oe = 0;
            opcode_reg_d = 2'b0;
        end
        WAIT_IN2_INST: begin
            uio_oe = 0;
            opcode_reg_d = opcode;
        end
    endcase
  end

  wire [7:0] posit_add_o, posit_mult_o;
  wire start;
  assign start = (ppu_state_q == COMPUTING);
  wire done;
  wire zero, inf;
  // All output pins must be assigned. If not used, assign to 0.

  assign posit_add_o = posit_add #(.N(8),.es(3))(ui_in, uio_in, start, uo_out, inf, zero, done);
  assign posit_mult_o = posit_mult #(.N(8),.es(3))(ui_in, uio_in, start, uo_out, inf, zero, done);

  //OUTPUT LOGIC
  always @(*) begin
    output_reg_d = 8'b0;
    case(opcode_reg_q)
        ADD: begin
           output_reg_d = posit_add_o;
        end
        MULT: begin
           output_reg_d = posit_mult_o;
        end
    endcase
  end
  
  //INPUT/OUTPUT REGS
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input1_reg_q <= 8'b0;
        input2_reg_q <= 8'b0;
        opcode_reg_q <= 8'b0;
        output_reg_q <= 8'b0;
    end else begin
        case(ppu_state_q)
            WAIT_IN1: begin
                if(input1_valid) input1_reg_q <= uio_in;
            end
            WAIT_IN2_INST: begin
                if(input2_valid) input2_reg_q <= uio_in;
                if(instruction_valid) opcode_reg_q <= ui_in[4:3]
            end
            COMPLETE: begin
                if(compute_done) output_reg_q <= output_reg_d;
            end
        endcase
    end
  end
  
  assign uio_out = output_reg_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uo_out <= {4'b0, 1'b1, 3'b0};
    end else if (ppu_state_q == COMPUTING) begin
        uo_out <= 8'b0;
    end else if (ppu_state_q == COMPLETE) begin
        uo_out <= {4'b0, 1'b1, inf, zero, 1'b1};
    end else begin
        uo_out <= {4'b0, 1'b1, 3'b0};
    end
  end

endmodule
