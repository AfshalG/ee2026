`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// EE2026 FDP - Number Font Patterns for Merge Sort Visualization
// Student: Afshal Gulam (A0307936W)
//
// Description: ROM-based number font patterns (1-6) for OLED display
//////////////////////////////////////////////////////////////////////////////////

module merge_sort_numbers(
    input  wire [2:0] number,          // Number to display (1-6)
    input  wire [2:0] row,             // Row within the 8-pixel height (0-7)
    input  wire [2:0] col,             // Column within the 6-pixel width (0-5)
    output reg        pixel_on         // 1 if pixel should be ON, 0 if OFF
);

    // 6x8 font ROM for numbers 0..7
    reg [5:0] font_rom [0:63];

    initial begin
        // Number 0 (addresses 0-7)
        font_rom[0] = 6'b011110; // Row 0
        font_rom[1] = 6'b110011; // Row 1
        font_rom[2] = 6'b110011; // Row 2
        font_rom[3] = 6'b110011; // Row 3
        font_rom[4] = 6'b110011; // Row 4
        font_rom[5] = 6'b110011; // Row 5
        font_rom[6] = 6'b110011; // Row 6
        font_rom[7] = 6'b011110; // Row 7

        // Number 1 (addresses 8-15)
        font_rom[8] = 6'b001100; // Row 0
        font_rom[9] = 6'b011100; // Row 1
        font_rom[10] = 6'b001100; // Row 2
        font_rom[11] = 6'b001100; // Row 3
        font_rom[12] = 6'b001100; // Row 4
        font_rom[13] = 6'b001100; // Row 5
        font_rom[14] = 6'b001100; // Row 6
        font_rom[15] = 6'b111111; // Row 7

        // Number 2 (addresses 16-23)
        font_rom[16] = 6'b111110; // Row 0
        font_rom[17] = 6'b100001; // Row 1
        font_rom[18] = 6'b000001; // Row 2
        font_rom[19] = 6'b000110; // Row 3
        font_rom[20] = 6'b001100; // Row 4
        font_rom[21] = 6'b011000; // Row 5
        font_rom[22] = 6'b110000; // Row 6
        font_rom[23] = 6'b111111; // Row 7

        // Number 3 (addresses 24-31)
        font_rom[24] = 6'b111110; // Row 0
        font_rom[25] = 6'b100001; // Row 1
        font_rom[26] = 6'b000001; // Row 2
        font_rom[27] = 6'b001110; // Row 3
        font_rom[28] = 6'b000001; // Row 4
        font_rom[29] = 6'b000001; // Row 5
        font_rom[30] = 6'b100001; // Row 6
        font_rom[31] = 6'b111110; // Row 7

        // Number 4 (addresses 32-39)
        font_rom[32] = 6'b000110; // Row 0
        font_rom[33] = 6'b001110; // Row 1
        font_rom[34] = 6'b011010; // Row 2
        font_rom[35] = 6'b110010; // Row 3
        font_rom[36] = 6'b111111; // Row 4
        font_rom[37] = 6'b000010; // Row 5
        font_rom[38] = 6'b000010; // Row 6
        font_rom[39] = 6'b000010; // Row 7

        // Number 5 (addresses 40-47)
        font_rom[40] = 6'b111111; // Row 0
        font_rom[41] = 6'b110000; // Row 1
        font_rom[42] = 6'b110000; // Row 2
        font_rom[43] = 6'b111110; // Row 3
        font_rom[44] = 6'b000001; // Row 4
        font_rom[45] = 6'b000001; // Row 5
        font_rom[46] = 6'b100001; // Row 6
        font_rom[47] = 6'b111110; // Row 7

        // Number 6 (addresses 48-55)
        font_rom[48] = 6'b011110; // Row 0
        font_rom[49] = 6'b110000; // Row 1
        font_rom[50] = 6'b110000; // Row 2
        font_rom[51] = 6'b111110; // Row 3
        font_rom[52] = 6'b110001; // Row 4
        font_rom[53] = 6'b110001; // Row 5
        font_rom[54] = 6'b110001; // Row 6
        font_rom[55] = 6'b011110; // Row 7

        // Number 7 (addresses 56-63)
        font_rom[56] = 6'b111111; // Row 0
        font_rom[57] = 6'b000011; // Row 1
        font_rom[58] = 6'b000110; // Row 2
        font_rom[59] = 6'b001100; // Row 3
        font_rom[60] = 6'b001100; // Row 4
        font_rom[61] = 6'b011000; // Row 5
        font_rom[62] = 6'b011000; // Row 6
        font_rom[63] = 6'b011000; // Row 7
    end

    // address calculation: number * 8 + row (since we now include 0)
    wire [5:0] rom_address;
    assign rom_address = (number << 3) + row;

    // row data
    wire [5:0] row_data = font_rom[rom_address];

    always @(*) begin
        if (number <= 3'd7 && row < 4'd8 && col < 4'd6) begin
            // MSB is leftmost pixel
            pixel_on = row_data[5 - col];
        end else begin
            pixel_on = 1'b0;
        end
    end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Number Box Renderer
// Combines number font with box border rendering
//////////////////////////////////////////////////////////////////////////////////

module number_box_renderer(
    input  wire [6:0]  x_coord,         // Pixel X coordinate (0-95)
    input  wire [5:0]  y_coord,         // Pixel Y coordinate (0-63)
    input  wire [2:0]  box_number,      // Which box (0-5) - now only used for debugging
    input  wire [2:0]  number_value,    // Number to display (0-7)
    input  wire [6:0]  box_x_pos,       // X position of box (actual pixel coordinate)
    input  wire [5:0]  box_y_pos,       // Y position of box (actual pixel coordinate)
    input  wire [2:0]  color_code,      // Color coding for the box
    input  wire        is_cursor,       // 1 if this box is the cursor position (tutorial mode)
    output reg  [15:0] pixel_color,     // RGB565 output color
    output wire        is_box_pixel     // 1 if this pixel is part of a box
);

    // --- PARAMETERS ---
    localparam COLOR_WHITE  = 16'hFFFF;
    localparam COLOR_RED    = 16'hF800;
    localparam COLOR_GREEN  = 16'h07E0;
    localparam COLOR_YELLOW = 16'hFFE0;
    localparam COLOR_BLACK  = 16'h0000;
    localparam COLOR_MAGENTA= 16'hF81F;
    localparam COLOR_CYAN   = 16'h07FF;
    localparam COLOR_ORANGE = 16'hFD20;
    localparam COLOR_BLUE   = 16'h001F;

    localparam integer BOX_WIDTH = 14;
    localparam integer BOX_HEIGHT = 10;
    localparam integer NUMBER_WIDTH = 6;
    localparam integer NUMBER_HEIGHT = 8;

    // --- WIRES / INTERMEDIATES ---
    wire [6:0] box_x_start;
    wire [5:0] box_y_start;
    wire in_box_x, in_box_y;
    wire [3:0] rel_x;
    wire [3:0] rel_y;
    wire is_border;
    wire in_number_area;
    wire [2:0] number_rel_x;
    wire [2:0] number_rel_y;
    wire number_pixel_on;
    wire [15:0] box_color;

    // --- Number font lookup ---
    // number_rel_y and number_rel_x are valid only when in_number_area is true.
    merge_sort_numbers font_lookup (
        .number(number_value),
        .row(number_rel_y),
        .col(number_rel_x),
        .pixel_on(number_pixel_on)
    );

    // --- COMPUTE BOX START ---
    // Use the dynamic X position passed from controller
    assign box_x_start = box_x_pos;
    assign box_y_start = box_y_pos;

    // Check if current pixel is within this box
    assign in_box_x = (x_coord >= box_x_start) && (x_coord < (box_x_start + BOX_WIDTH));
    assign in_box_y = (y_coord >= box_y_start) && (y_coord < (box_y_start + BOX_HEIGHT));
    assign is_box_pixel = in_box_x && in_box_y;

    // Relative coordinates inside the box (valid when is_box_pixel)
    // Use small widths: BOX_WIDTH <= 14 fits into 4 bits
    assign rel_x = x_coord - box_x_start; // 0 .. 13
    assign rel_y = y_coord - box_y_start; // 0 .. 9

    // Border thickness: 3 pixels for cursor, 1 pixel for normal boxes
    wire [3:0] border_thickness;
    assign border_thickness = is_cursor ? 4'd3 : 4'd1;

    // Border detection (variable thickness based on cursor state)
    assign is_border = (rel_x < border_thickness) || (rel_x >= (BOX_WIDTH - border_thickness)) ||
                       (rel_y < border_thickness) || (rel_y >= (BOX_HEIGHT - border_thickness));

    // Number area detection (centered)
    assign in_number_area = (rel_x >= 4) && (rel_x < (4 + NUMBER_WIDTH)) &&
                            (rel_y >= 1) && (rel_y < (1 + NUMBER_HEIGHT));

    // compute number relative coords only when in_number_area is true
    // tmp wires to avoid width/negative issues
    wire [3:0] tmp_x_sub = rel_x - 4; // 0..5
    wire [3:0] tmp_y_sub = rel_y - 1; // 0..7
    assign number_rel_x = in_number_area ? tmp_x_sub[2:0] : 3'd0;
    assign number_rel_y = in_number_area ? tmp_y_sub[2:0] : 3'd0;

    // Color selection
    assign box_color = (color_code == 3'b000) ? COLOR_WHITE  :
                       (color_code == 3'b001) ? COLOR_RED    :
                       (color_code == 3'b010) ? COLOR_GREEN  :
                       (color_code == 3'b011) ? COLOR_YELLOW :
                       (color_code == 3'b100) ? COLOR_MAGENTA:
                       (color_code == 3'b101) ? COLOR_CYAN   :
                       (color_code == 3'b110) ? COLOR_ORANGE :
                       (color_code == 3'b111) ? COLOR_BLUE   :
                       COLOR_WHITE;

    // --- PIXEL COLOR OUTPUT ---
    always @(*) begin
        if (is_box_pixel) begin
            if (in_number_area && number_pixel_on) begin
                pixel_color = COLOR_BLACK;
            end else begin
                pixel_color = box_color;
            end
        end else begin
            pixel_color = COLOR_BLACK; // background
        end
    end

endmodule