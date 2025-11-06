`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
//  EE2026 FDP - Sorting Visualizer Demo System
//  ...
//
//////////////////////////////////////////////////////////////////////////////////

module Top_Student (
    input clk,                    // 100MHz system clock
    input [15:0] sw,              // Switches for control
    input btnC, btnU, btnL, btnR, btnD, // Pushbuttons
    output [15:0] led,           // Status LEDs
    output [6:0] seg,            // Seven-segment display
    output [3:0] an,             // Seven-segment anodes
    output dp,                   // Decimal point
    output [7:0] JC              // OLED interface (Pmod connector JC)
);

//==============================================================================
// Clock Generation
//==============================================================================
reg [15:0] clk_counter_6p25MHz = 0;
reg [20:0] clk_counter_movement = 0;
reg clk_6p25MHz = 0;
reg clk_movement = 0;

always @(posedge clk) begin
    clk_counter_6p25MHz <= clk_counter_6p25MHz + 1;
    if (clk_counter_6p25MHz >= 16'd7) begin // 100MHz / 8 = 12.5MHz, toggle = 6.25MHz
        clk_counter_6p25MHz <= 0;
        clk_6p25MHz <= ~clk_6p25MHz;
    end
end

always @(posedge clk) begin
    clk_counter_movement <= clk_counter_movement + 1;
    if (clk_counter_movement >= 21'd1111111) begin // ~45Hz
        clk_counter_movement <= 0;
        clk_movement <= ~clk_movement;
    end
end

//==============================================================================
// Control Interface
//==============================================================================
// Mode selection signals
wire educational_mode;
wire tutorial_mode;
assign educational_mode = sw[15] && !sw[10];  // sw15=ON, sw10=OFF
assign tutorial_mode = sw[15] && sw[10];      // sw15=ON, sw10=ON

wire merge_sort_demo_active;
assign merge_sort_demo_active = sw[15];

// Button synchronizers for debouncing (3-stage shift registers)
reg [2:0] btnU_sync = 3'b000;
reg [2:0] btnD_sync = 3'b000;
reg [2:0] btnC_sync = 3'b000;
reg [2:0] btnL_sync = 3'b000;
reg [2:0] btnR_sync = 3'b000;

always @(posedge clk) begin
    btnU_sync <= {btnU_sync[1:0], btnU};
    btnD_sync <= {btnD_sync[1:0], btnD};
    btnC_sync <= {btnC_sync[1:0], btnC};
    btnL_sync <= {btnL_sync[1:0], btnL};
    btnR_sync <= {btnR_sync[1:0], btnR};
end

// Edge detection for button presses
wire btn_start, btn_pause, btn_reset, btn_center, btn_left, btn_right;
assign btn_start = btnU_sync[2] && !btnU_sync[1]; // Rising edge of UP button
assign btn_pause = btnD_sync[2] && !btnD_sync[1]; // Rising edge of DOWN button
assign btn_center = btnC_sync[2] && !btnC_sync[1]; // Rising edge of CENTER button
// Reset only when NOT in tutorial mode (to allow btnC for confirmation in tutorial)
assign btn_reset = btn_center && !tutorial_mode;
assign btn_left  = btnL_sync[2] && !btnL_sync[1]; // Rising edge of LEFT button
assign btn_right = btnR_sync[2] && !btnR_sync[1]; // Rising edge of RIGHT button

//==============================================================================
// OLED Display Interface
//==============================================================================
wire frame_begin, sending_pixels, sample_pixel;
wire [12:0] pixel_index;
wire [15:0] pixel_data;

Oled_Display oled_display (
    .clk(clk_6p25MHz),
    .reset(btn_reset),
    .frame_begin(frame_begin),
    .sending_pixels(sending_pixels),
    .sample_pixel(sample_pixel),
    .pixel_index(pixel_index),
    .pixel_data(pixel_data),
    .cs(JC[0]),
    .sdin(JC[1]),
    .sclk(JC[3]),
    .d_cn(JC[4]),
    .resn(JC[5]),
    .vccen(JC[6]),
    .pmoden(JC[7])
);
assign JC[2] = 0; // Unused pin

//==============================================================================
// Merge Sort Visualization System
//==============================================================================
// Signals between controller and display (flattened buses)
wire [17:0] array_data_flat;
wire [17:0] answer_data_flat;  // User's answer array (tutorial practice mode)
wire [35:0] array_positions_y_flat;
wire [41:0] array_positions_x_flat;
wire [17:0] array_colors_flat;
wire [17:0] answer_colors_flat;  // Colors for answer boxes
wire [4:0] separator_visible;
wire [14:0] separator_colors_flat;  // Colors for separator lines (tutorial feedback)
wire [2:0] cursor_pos;
wire practice_mode_active;  // Flag for 2-row display
wire [2:0] sort_current_state;
wire [2:0] divide_step_status;
wire [2:0] merge_step_status;
wire sorting_active, animation_busy, sort_complete;
wire all_positions_reached;  // Handshake signal from controller

// Tutorial mode pulsing and hints (new signals)
wire pulse_state_signal;
wire [5:0] merge_region_active_signal;
wire [5:0] hint_timer_signal;
wire [4:0] hint_separators_signal;

// Merge Sort Controller
merge_sort_controller merge_controller (
    .clk(clk),
    .clk_6p25MHz(clk_6p25MHz),
    .clk_movement(clk_movement),
    .reset(btn_reset),
    .btn_start(btn_start),
    .btn_pause(btn_pause),
    .btn_left(btn_left),
    .btn_right(btn_right),
    .btn_center(btn_center),  // Center button for tutorial mode confirmation
    .demo_active(merge_sort_demo_active),
    .educational_mode(educational_mode),
    .tutorial_mode(tutorial_mode),
    .line_switches(sw[4:0]),  // sw0-4 for separator line placement in tutorial mode

    // Array data outputs
    .array_data_flat(array_data_flat),
    .answer_data_flat(answer_data_flat),
    .array_positions_y_flat(array_positions_y_flat),
    .array_positions_x_flat(array_positions_x_flat),
    .array_colors_flat(array_colors_flat),
    .answer_colors_flat(answer_colors_flat),
    .separator_visible(separator_visible),
    .separator_colors_flat(separator_colors_flat),
    .cursor_pos_out(cursor_pos),
    .practice_mode_active(practice_mode_active),

    // Status outputs
    .current_state(sort_current_state),
    .divide_step_out(divide_step_status),
    .merge_step_out(merge_step_status),
    .sorting_active(sorting_active),
    .animation_busy(animation_busy),
    .sort_complete(sort_complete),

    .all_positions_reached(all_positions_reached),  // Handshake output

    // Tutorial mode pulsing and hints
    .pulse_state_out(pulse_state_signal),
    .merge_region_active_flat(merge_region_active_signal),
    .hint_timer_out(hint_timer_signal),
    .hint_separators_flat(hint_separators_signal)
);

// Merge Sort Display Engine
merge_sort_display display_engine (
    .clk_6p25MHz(clk_6p25MHz),
    .reset(btn_reset),

    // OLED interface
    .pixel_index(pixel_index),
    .pixel_data(pixel_data),

    // Data from controller
    .array_data_flat(array_data_flat),
    .answer_data_flat(answer_data_flat),
    .array_positions_y_flat(array_positions_y_flat),
    .array_positions_x_flat(array_positions_x_flat),
    .array_colors_flat(array_colors_flat),
    .answer_colors_flat(answer_colors_flat),
    .separator_visible(separator_visible),
    .separator_colors_flat(separator_colors_flat),
    .cursor_pos(cursor_pos),
    .practice_mode_active(practice_mode_active),
    .current_state(sort_current_state),
    .divide_step(divide_step_status),
    .merge_step(merge_step_status),
    .sorting_active(sorting_active),
    .demo_active(merge_sort_demo_active),

    // Tutorial mode pulsing and hints
    .pulse_state(pulse_state_signal),
    .merge_region_active(merge_region_active_signal),
    .hint_timer(hint_timer_signal),
    .hint_separators(hint_separators_signal)
);

//==============================================================================
// Seven-Segment Display
//==============================================================================
reg [15:0] display_counter = 0;
reg [1:0] digit_select = 0;
always @(posedge clk) begin
    display_counter <= display_counter + 1;
    if (display_counter == 0) begin
        digit_select <= digit_select + 1;
    end
end
localparam SEG_M = 7'b1101010; // "M" for Merge
localparam SEG_E = 7'b0000110;  // "E"
localparam SEG_R = 7'b0101111;  // "r"
localparam SEG_G = 7'b0010000; // "G"
reg [6:0] seg_pattern;
reg [3:0] anode_pattern;
always @(*) begin
    case (digit_select)
        2'b00: begin  anode_pattern = 4'b1110; seg_pattern = SEG_G; end
        2'b01: begin  anode_pattern = 4'b1101; seg_pattern = SEG_R; end
        2'b10: begin  anode_pattern = 4'b1011; seg_pattern = SEG_E; end
        2'b11: begin  anode_pattern = 4'b0111; seg_pattern = SEG_M; end
    endcase
end
assign seg = seg_pattern;
assign an = anode_pattern;
assign dp = 1'b1;

//==============================================================================
// LED Status Display
//==============================================================================
assign led[15] = merge_sort_demo_active;
assign led[14] = sorting_active;
assign led[13] = animation_busy;
assign led[12] = sort_complete;
assign led[11:8] = {1'b0, sort_current_state};

// Show top 2 bits of position for 4 elements (0-63 range)
// array_positions_y_flat = {pos[5], pos[4], pos[3], pos[2], pos[1], pos[0]}
// Each pos is 6 bits
assign led[7:6] = array_positions_y_flat[5:4];   // Element 0 position [bits 5:0]
assign led[5:4] = array_positions_y_flat[11:10]; // Element 1 position [bits 11:6]
assign led[3:2] = array_positions_y_flat[17:16]; // Element 2 position [bits 17:12]
assign led[1:0] = array_positions_y_flat[23:22]; // Element 3 position [bits 23:18]

endmodule