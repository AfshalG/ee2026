`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// EE2026 FDP - Merge Sort OLED Display Engine
// Student: Afshal Gulam (A0307936W)
//
// Description: OLED rendering engine for merge sort visualization
// ...
//////////////////////////////////////////////////////////////////////////////////

module merge_sort_display(
    input clk_6p25MHz,
    input reset,

    // OLED interface signals
    input [12:0] pixel_index,    // From Oled_Display.v (0-6143)
    output reg [15:0] pixel_data, // To Oled_Display.v (RGB565)


    // Data from merge sort controller (flattened inputs)
    input [17:0] array_data_flat,        // Number values (0-7): 6 elements × 3 bits
    input [17:0] answer_data_flat,       // User's answer array (0-7): 6 elements × 3 bits
    input [35:0] array_positions_y_flat, // Y positions for animation: 6 elements × 6 bits
    input [41:0] array_positions_x_flat, // X positions for animation: 6 elements × 7 bits
    input [17:0] array_colors_flat,      // Color codes for each element: 6 elements × 3 bits
    input [17:0] answer_colors_flat,     // Color codes for answer boxes: 6 elements × 3 bits
    input [4:0] separator_visible,       // Separator visibility flags: 5 separators × 1 bit
    input [14:0] separator_colors_flat,  // Color codes for each separator: 5 separators × 3 bits
    input [2:0] cursor_pos,              // Current cursor position (0-5) for tutorial mode
    input practice_mode_active,          // Show 2 rows of boxes (tutorial practice mode)
    input [2:0] current_state,           // Controller state
    input [2:0] divide_step,             // Current divide step (0-5)
    input [2:0] merge_step,              // Current merge step (0-2)
    input sorting_active,                // Animation active flag
    input demo_active,                   // Enable signal from team controller

    // Tutorial mode pulsing and hints (new inputs)
    input pulse_state,                   // Pulsing state for merge regions (toggles every 0.5s)
    input [5:0] merge_region_active,     // Which boxes are in active merge regions
    input [5:0] hint_timer,              // Hint timer countdown (45 to 0)
    input [4:0] hint_separators          // Which separator positions to hint
);

// OLED display parameters
localparam OLED_WIDTH = 96;
localparam OLED_HEIGHT = 64;

// Internal arrays (converted from flattened inputs)
wire [2:0] array_data [0:5];        // Number values (0-7) - bottom row
wire [2:0] answer_data [0:5];       // Answer values (0-7) - answer row
wire [5:0] array_positions_y [0:5]; // Y positions for animation
wire [6:0] array_positions_x [0:5]; // X positions for animation
wire [2:0] array_colors [0:5];      // Color codes for each element
wire [2:0] answer_colors [0:5];     // Color codes for answer boxes
wire [2:0] separator_colors [0:4];  // Color codes for separators

// Convert flattened inputs to internal arrays
assign {array_data[5], array_data[4], array_data[3], array_data[2], array_data[1], array_data[0]} = array_data_flat;
assign {answer_data[5], answer_data[4], answer_data[3], answer_data[2], answer_data[1], answer_data[0]} = answer_data_flat;
assign {array_positions_y[5], array_positions_y[4], array_positions_y[3], array_positions_y[2], array_positions_y[1], array_positions_y[0]} = array_positions_y_flat;
assign {array_positions_x[5], array_positions_x[4], array_positions_x[3], array_positions_x[2], array_positions_x[1], array_positions_x[0]} = array_positions_x_flat;
assign {array_colors[5], array_colors[4], array_colors[3], array_colors[2], array_colors[1], array_colors[0]} = array_colors_flat;
assign {answer_colors[5], answer_colors[4], answer_colors[3], answer_colors[2], answer_colors[1], answer_colors[0]} = answer_colors_flat;
assign {separator_colors[4], separator_colors[3], separator_colors[2], separator_colors[1], separator_colors[0]} = separator_colors_flat;

// Coordinate calculation from pixel_index
wire [6:0] x_coord;
wire [5:0] y_coord;
assign x_coord = pixel_index % OLED_WIDTH;
assign y_coord = pixel_index / OLED_WIDTH;

// Color definitions (RGB565 format)
localparam COLOR_BLACK = 16'h0000;
localparam COLOR_WHITE = 16'hFFFF;
localparam COLOR_RED = 16'hF800;
localparam COLOR_GREEN = 16'h07E0;
localparam COLOR_BLUE = 16'h001F;
localparam COLOR_YELLOW = 16'hFFE0;
localparam COLOR_CYAN = 16'h07FF;
localparam COLOR_MAGENTA = 16'hF81F;
localparam COLOR_ORANGE = 16'hFC00;
localparam COLOR_FAINT_WHITE = 16'h4208;  // Dim white for ghost separators (R:8, G:16, B:8)

// Box rendering signals for bottom row (6 boxes) and answer boxes (6 boxes above)
wire [15:0] box_pixel_colors [0:5];       // Bottom row boxes (work array)
wire box_is_active [0:5];                  // Bottom row box active flags
wire [15:0] answer_box_pixel_colors [0:5]; // Answer boxes (one level up in merge tree)
wire answer_box_is_active [0:5];           // Answer box active flags

// Position definitions (same as controller)
localparam POS_TOP = 6'd8;       // Top of screen (y=8)
localparam POS_MID = 6'd32;      // Middle of screen (y=32)
localparam POS_BOTTOM = 6'd48;   // Bottom of screen (y=48)

// Calculate answer box Y position based on current bottom position
// If bottom is at BOTTOM (48), answer should be at 2/3 position (going up)
// If bottom is at 2/3, answer should be at 1/3 position
// If bottom is at 1/3, answer should be at TOP
wire [5:0] answer_box_y_pos;
assign answer_box_y_pos = (array_positions_y[0] == POS_BOTTOM) ? (POS_TOP + 2 * (POS_BOTTOM - POS_TOP) / 3) :  // 2/3 from top
                          (array_positions_y[0] >= (POS_TOP + 2 * (POS_BOTTOM - POS_TOP) / 3)) ? (POS_TOP + (POS_BOTTOM - POS_TOP) / 3) :  // 1/3 from top
                          POS_TOP;  // At top

// Generate 6 box renderers for bottom row (main array)
genvar i;
generate
    for (i = 0; i < 6; i = i + 1) begin : box_gen
        number_box_renderer box_renderer (
            .x_coord(x_coord),
            .y_coord(y_coord),
            .box_number(i[2:0]),
            .number_value(array_data[i]),
            .box_x_pos(array_positions_x[i]),
            .box_y_pos(array_positions_y[i]),
            .color_code(array_colors[i]),
            .is_cursor((current_state == 3'b110) && (i[2:0] == cursor_pos)),  // Tutorial edit mode with cursor match
            .pixel_color(box_pixel_colors[i]),
            .is_box_pixel(box_is_active[i])
        );
    end
endgenerate

// Generate 6 box renderers for answer boxes - only active in practice mode
// Positioned one level up in the merge tree (previous Y position)
genvar j;
generate
    for (j = 0; j < 6; j = j + 1) begin : answer_box_gen
        number_box_renderer answer_box_renderer (
            .x_coord(x_coord),
            .y_coord(y_coord),
            .box_number(j[2:0]),
            .number_value(answer_data[j]),
            .box_x_pos(array_positions_x[j]),  // Same X position as bottom boxes
            .box_y_pos(answer_box_y_pos),      // One level up (previous merge step Y)
            .color_code(answer_colors[j]),      // Use answer_colors (white/cyan for cursor)
            .is_cursor(1'b0),                   // Cursor handled by color_code
            .pixel_color(answer_box_pixel_colors[j]),
            .is_box_pixel(answer_box_is_active[j])
        );
    end
endgenerate

// Pulsing border detection for answer boxes (1px yellow border - super thin)
wire pulsing_border_active [0:5];
wire any_pulsing_border;
genvar p;
generate
    for (p = 0; p < 6; p = p + 1) begin : pulsing_border_gen
        // Box dimensions: 14×10 pixels
        // Border is 1px thick on all sides (super thin)
        wire in_box_x_range = (x_coord >= array_positions_x[p]) && (x_coord <= array_positions_x[p] + 13);
        wire in_box_y_range = (y_coord >= answer_box_y_pos) && (y_coord <= answer_box_y_pos + 9);
        wire on_left_border = (x_coord == array_positions_x[p]);
        wire on_right_border = (x_coord == array_positions_x[p] + 13);
        wire on_top_border = (y_coord == answer_box_y_pos);
        wire on_bottom_border = (y_coord == answer_box_y_pos + 9);

        // Check if pixel is on the border (1px thick)
        wire on_border = in_box_x_range && in_box_y_range &&
                        ((on_left_border || on_right_border) || (on_top_border || on_bottom_border));

        // Pulsing border active when: in practice mode, box in merge region, pulse state high, on border
        assign pulsing_border_active[p] = practice_mode_active && merge_region_active[p] && pulse_state && on_border;
    end
endgenerate

assign any_pulsing_border = pulsing_border_active[0] | pulsing_border_active[1] | pulsing_border_active[2] |
                            pulsing_border_active[3] | pulsing_border_active[4] | pulsing_border_active[5];

// Priority encoding for overlapping boxes
wire [2:0] active_box_index;
wire [2:0] active_answer_box_index;
wire any_box_active;
wire any_answer_box_active;

// Find which bottom row box (if any) should be rendered at current pixel
assign any_box_active = box_is_active[0] | box_is_active[1] | box_is_active[2] |
                        box_is_active[3] | box_is_active[4] | box_is_active[5];

// Priority encoder - box 0 has highest priority
assign active_box_index = box_is_active[0] ? 3'd0 :
                         box_is_active[1] ? 3'd1 :
                         box_is_active[2] ? 3'd2 :
                         box_is_active[3] ? 3'd3 :
                         box_is_active[4] ? 3'd4 :
                         box_is_active[5] ? 3'd5 : 3'd0;

// Find which top row answer box (if any) should be rendered at current pixel
assign any_answer_box_active = practice_mode_active && (
                                answer_box_is_active[0] | answer_box_is_active[1] | answer_box_is_active[2] |
                                answer_box_is_active[3] | answer_box_is_active[4] | answer_box_is_active[5]);

// Priority encoder for answer boxes
assign active_answer_box_index = answer_box_is_active[0] ? 3'd0 :
                                 answer_box_is_active[1] ? 3'd1 :
                                 answer_box_is_active[2] ? 3'd2 :
                                 answer_box_is_active[3] ? 3'd3 :
                                 answer_box_is_active[4] ? 3'd4 :
                                 answer_box_is_active[5] ? 3'd5 : 3'd0;

// Background pattern for demo mode
wire [15:0] background_pixel;
wire is_background_feature;
// Simple grid pattern for background
assign is_background_feature = ((x_coord[2:0] == 3'd0) && (y_coord[2:0] == 3'd0)) && demo_active;
assign background_pixel = is_background_feature ? COLOR_BLUE : COLOR_BLACK;

// REMOVED: Title, step indicator, status indicator, and progress bar
// All UI elements removed for cleaner visualization

// Animation effects during transitions
wire [15:0] animation_pixel;
wire has_animation_effect;

// Sparkle effect during merge phase
assign has_animation_effect = (current_state == 3'd3) &&
                             ((x_coord[3:0] == 4'd0) && (y_coord[3:0] == 4'd0)) &&
                             demo_active;
assign animation_pixel = has_animation_effect ? COLOR_YELLOW : COLOR_BLACK;

// Separator lines between segments
wire is_separator_pixel;
wire [2:0] separator_index;

// Separator positions (X coordinates between boxes)
// Box positions: 1, 17, 33, 49, 65, 81
// Separator X positions: 15-16 (between 0&1), 31-32 (between 1&2), 47-48 (between 2&3), 63-64 (between 3&4), 79-80 (between 4&5)
wire in_separator_0, in_separator_1, in_separator_2, in_separator_3, in_separator_4;
assign in_separator_0 = (x_coord >= 7'd15 && x_coord <= 7'd16); // Between box 0 and 1
assign in_separator_1 = (x_coord >= 7'd31 && x_coord <= 7'd32); // Between box 1 and 2
assign in_separator_2 = (x_coord >= 7'd47 && x_coord <= 7'd48); // Between box 2 and 3
assign in_separator_3 = (x_coord >= 7'd63 && x_coord <= 7'd64); // Between box 3 and 4
assign in_separator_4 = (x_coord >= 7'd79 && x_coord <= 7'd80); // Between box 4 and 5

// Check if current pixel is on any visible separator
assign is_separator_pixel = (in_separator_0 && separator_visible[0]) ||
                           (in_separator_1 && separator_visible[1]) ||
                           (in_separator_2 && separator_visible[2]) ||
                           (in_separator_3 && separator_visible[3]) ||
                           (in_separator_4 && separator_visible[4]);

// Determine which separator is active (for color lookup)
assign separator_index = (in_separator_0 && separator_visible[0]) ? 3'd0 :
                        (in_separator_1 && separator_visible[1]) ? 3'd1 :
                        (in_separator_2 && separator_visible[2]) ? 3'd2 :
                        (in_separator_3 && separator_visible[3]) ? 3'd3 :
                        (in_separator_4 && separator_visible[4]) ? 3'd4 : 3'd0;

// Hint separator rendering (lower priority than user separators)
wire is_hint_separator_pixel;
assign is_hint_separator_pixel = (hint_timer > 0) && (
                                  (in_separator_0 && hint_separators[0] && !separator_visible[0]) ||
                                  (in_separator_1 && hint_separators[1] && !separator_visible[1]) ||
                                  (in_separator_2 && hint_separators[2] && !separator_visible[2]) ||
                                  (in_separator_3 && hint_separators[3] && !separator_visible[3]) ||
                                  (in_separator_4 && hint_separators[4] && !separator_visible[4]));

// Main pixel data selection with priority
always @(*) begin
    if (!demo_active) begin
        pixel_data = COLOR_BLACK; // Off when demo not active
    end else if (any_pulsing_border) begin
        // Pulsing yellow borders overlay on answer boxes (highest priority)
        pixel_data = COLOR_YELLOW;
    end else if (any_answer_box_active) begin
        // Display answer boxes (top row) with highest priority in practice mode
        pixel_data = answer_box_pixel_colors[active_answer_box_index];
    end else if (any_box_active) begin
        // Display the active bottom row box
        pixel_data = box_pixel_colors[active_box_index];
    end else if (is_separator_pixel) begin
        // Separator lines between segments - use dynamic color
        case (separator_colors[separator_index])
            3'b000: pixel_data = COLOR_WHITE;   // Normal
            3'b001: pixel_data = COLOR_RED;     // Wrong (flash)
            3'b010: pixel_data = COLOR_GREEN;   // Correct (flash)
            3'b011: pixel_data = COLOR_YELLOW;
            3'b100: pixel_data = COLOR_MAGENTA;
            3'b101: pixel_data = COLOR_CYAN;
            3'b110: pixel_data = COLOR_ORANGE;
            3'b111: pixel_data = COLOR_BLUE;
            default: pixel_data = COLOR_WHITE;
        endcase
    end else if (is_hint_separator_pixel) begin
        // Hint separators - ghost separators (faint white), lower priority than user separators
        pixel_data = COLOR_FAINT_WHITE;
    end else if (has_animation_effect) begin
        pixel_data = animation_pixel;
    end else begin
        pixel_data = background_pixel;
    end
end

endmodule