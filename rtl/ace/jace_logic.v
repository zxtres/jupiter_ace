`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    00:32:05 11/08/2015 
// Design Name: 
// Module Name:    jace_logic 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module jace_logic (
    input wire clk,
    // CPU interface
    input wire reset_n,
    input wire [15:0] cpu_addr,
    input wire mreq_n,
    input wire iorq_n,
    input wire rd_n,
    input wire wr_n,
    input wire [7:0] data_from_cpu,
    output reg [7:0] data_to_cpu,
    output reg data_to_cpu_oe,
    output reg wait_n,
    output wire int_n,
    // CPU-RAM interface
    output reg rom_enable,
    output reg sram_enable,
    output reg cram_enable,
    output reg uram_enable,
    output reg xram_enable,
    output reg eram_enable,
    // Screen RAM and Char RAM interface
    output wire [9:0] screen_addr,
    input wire [7:0] screen_data,
    output wire [9:0] char_addr,
    input wire [7:0] char_data,
    input wire [7:0] attr_data,
    // Devices
    input wire [4:0] kbdcols,
    input wire ear,
    output reg spk,
    output reg mic,
    output reg r,
    output reg g,
    output reg b,
    output wire hsync_pal,
	 output wire vsync_pal
    );
    
    initial begin
      wait_n = 1'b1;
      spk = 1'b0;
      mic = 1'b0;
    end
    
    reg [2:0] borde = 3'b000;
    
    reg [8:0] cntpix = 9'd0;
    reg [8:0] cntscn = 9'd0;
    wire [17:0] cnt = {cntscn, cntpix};
	 
    always @(posedge clk) begin
        if (cntpix != 9'd415)
            cntpix <= cntpix + 9'd1;
        else begin
            cntpix <= 9'd0;
            if (cntscn != 9'd311)
                cntscn <= cntscn + 9'd1;
            else
                cntscn <= 9'd0;
        end
    end
    
    reg vsync; // FIELD signal in schematic
    always @* begin
        if (cntscn >= 9'd248 && cntscn <= 9'd255)        
            vsync = 1'b0;
        else
            vsync = 1'b1;
    end
    assign int_n = vsync;
    
    reg hsync; // LINE signal in schematic
    always @* begin
        //if (cntpix >= 9'd320 && cntpix <= 9'd351)
        if (cntpix >= 9'd310 && cntpix <= 9'd342)  // cambiada respecto al esquemático para poder centrar la pantalla mejor
            hsync = 1'b0;
        else
            hsync = 1'b1;
    end
    
    //assign csync = hsync & vsync;
	 assign hsync_pal = hsync;
	 assign vsync_pal = vsync;
    
    reg viden; // VIDEN signal in schematic
    always @* begin
        if (cntpix >= 9'd0 && cntpix <= 9'd255 && 
            cntscn >= 9'd0 && cntscn <= 9'd191)
            viden = 1'b1;
        else
            viden = 1'b0;
    end
    
    reg blankarea;  // no existe en el esquemático. Indica cuándo estamos en intervalo de blanking
    always @* begin
      if ((cntpix >= (256+40) && cntpix < (416-40)) || (cntscn >= (192+48) && cntscn < (312-48)))
        blankarea = 1'b1;
      else
        blankarea = 1'b0;
    end
    
    // SHIFT/LOAD signal to 74LS166
    reg shiftload;
    always @* begin
        if (cnt[2:0] == 3'b000 && viden == 1'b1)
            shiftload = 1'b1;
        else
            shiftload = 1'b0;
    end
    
    assign screen_addr = {cnt[16:12], cnt[7:3]};
    assign char_addr = {screen_data[6:0], cnt[11:9]};
        
    // 74LS166
    reg [7:0] shiftreg = 8'h00;
    always @(posedge clk) begin
        if (shiftload == 1'b1)
            shiftreg <= char_data;
        else
            shiftreg <= {shiftreg[6:0], 1'b0};
    end
    
    // Pixel inverter reg and video output stage
    reg pixinverter = 1'b0;
    always @(posedge clk) begin
        if (cnt[2:0] == 3'b000)
            pixinverter <= viden & screen_data[7];
    end
    
    always @* begin
      case ({blankarea, viden})
        2'b00: {g,r,b} = borde;
        2'b01: {g,r,b} = ((shiftreg[7] ^ pixinverter) == 1'b0)? attr_data[5:3] : attr_data[2:0];
        default: {g,r,b} = 3'b000;
      endcase
    end
    
    // Address decoder
    reg fast_access;
    always @* begin
      rom_enable = 1'b0;
      sram_enable = 1'b0;
      cram_enable = 1'b0;
      uram_enable = 1'b0;
      xram_enable = 1'b0;
      eram_enable = 1'b0;
      fast_access = 1'b1;
      if (mreq_n == 1'b0) begin
        if (cpu_addr >= 16'h0000 && cpu_addr <= 16'h1FFF)
          rom_enable = 1'b1;
        else if (cpu_addr >= 16'h2000 && cpu_addr <= 16'h27FF) begin
          sram_enable = 1'b1;
          if (cpu_addr >= 16'h2400 && cpu_addr <= 16'h27FF)
            fast_access = 1'b0;
        end
        else if (cpu_addr >= 16'h2800 && cpu_addr <= 16'h2FFF) begin
          cram_enable = 1'b1;
          if (cpu_addr >= 16'h2C00 && cpu_addr <= 16'h2FFF)
            fast_access = 1'b0;
        end
        else if (cpu_addr >= 16'h3000 && cpu_addr <= 16'h3FFF)
          uram_enable = 1'b1;
        else if (cpu_addr >= 16'h4000 && cpu_addr <= 16'h7FFF)
          xram_enable = 1'b1;
        else
          eram_enable = 1'b1;
      end
    end
    
    // CPU arbitration to share memory with video generator
    always @(posedge clk) begin
        if ((sram_enable == 1'b1 || cram_enable == 1'b1) && viden == 1'b1 && fast_access == 1'b0)
            wait_n <= 1'b0;
        else if (viden == 1'b0)
            wait_n <= 1'b1;
    end
    
    // IO devices
    always @* begin
        data_to_cpu_oe = 1'b0;
        data_to_cpu = {2'b11, ear, kbdcols};
        if (iorq_n == 1'b0 && cpu_addr[0] == 1'b0 && rd_n == 1'b0) begin
            data_to_cpu_oe = 1'b1;
        end
    end    
    always @(posedge clk) begin
      if (reset_n == 1'b0) begin
        borde <= 3'b000;
        mic <= 1'b0;
        spk <= 1'b0;
      end
      else if (iorq_n == 1'b0 && cpu_addr[7:0] == 8'd0 && wr_n == 1'b0)
        borde <= data_from_cpu[2:0];
      else if (iorq_n == 1'b0 && cpu_addr[0] == 1'b0) begin
        if (rd_n == 1'b0 && wr_n == 1'b1)
          spk <= 1'b0;
        else if (rd_n == 1'b1 && wr_n == 1'b0)
          spk <= 1'b1;
        if (wr_n == 1'b0) begin
          mic <= data_from_cpu[3];
        end
      end
    end
endmodule
