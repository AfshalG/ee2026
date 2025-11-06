`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EE2026 FDP - Merge Sort Visualization Controller
// Student: Afshal Gulam (A0307936W)
//
// Description: Main FSM controller for merge sort visualization on OLED display
// ...
// [FIXED VERSION]
//////////////////////////////////////////////////////////////////////////////////

module merge_sort_controller(
    input clk,                    // 100MHz system clock
    input clk_6p25MHz,           // OLED interface clock
    input clk_movement,          // ~45Hz movement clock for animations
    input reset,

    input btn_start,             // Start/restart merge sort demo
    input btn_pause,             // Pause/resume animation
    input btn_left,              // Navigate cursor left (tutorial mode)
    input btn_right,             // Navigate cursor right (tutorial mode)
    input btn_center,            // Center button for confirmation (tutorial mode)
    input demo_active,           // Enable signal from team's controller
    input educational_mode,      // Educational mode active (sw15=ON, sw10=OFF)
    input tutorial_mode,         // Tutorial mode active (sw15=ON, sw10=ON)
    input [4:0] line_switches,   // sw0-4 for separator line placement (tutorial mode)

    // Array data outputs for display (flattened for module ports)
    output reg [17:0] array_data_flat,     // Current array values (0-7): 6 elements × 3 bits
    output reg [17:0] answer_data_flat,    // User's answer array (0-7): 6 elements × 3 bits (tutorial practice)

    output reg [35:0] array_positions_y_flat, // Y positions for animation: 6 elements × 6 bits
    output reg [41:0] array_positions_x_flat, // X positions for animation: 6 elements × 7 bits
    output reg [17:0] array_colors_flat,   // Color coding for each element: 6 elements × 3 bits
    output reg [17:0] answer_colors_flat,  // Color coding for answer boxes: 6 elements × 3 bits
    output reg [4:0] separator_visible,    // Separator visibility flags: 5 separators × 1 bit each
    output reg [14:0] separator_colors_flat,  // Color coding for each separator: 5 separators × 3 bits
    output reg [2:0] cursor_pos_out,       // Current cursor position (0-5) for tutorial mode
    output reg practice_mode_active,       // Flag: show 2 rows of boxes (practice mode)
    output reg pulse_state_out,            // Pulsing state for merge regions (tutorial mode)
    output reg [5:0] merge_region_active_flat,  // Which boxes are being merged (tutorial mode)
    output reg [5:0] hint_timer_out,       // Hint timer value (tutorial mode)
    output reg [4:0] hint_separators_flat, // Separator hint positions (tutorial mode)

    // Status outputs
    output reg [2:0] current_state,
    output reg [2:0] divide_step_out,
    output reg [2:0] merge_step_out,
    output reg sorting_active,
    output reg animation_busy,
    output reg sort_complete,
    output wire all_positions_reached    // Handshake: all animations completed
);
// Color definitions for visualization
localparam COLOR_NORMAL = 3'b000;    // White
localparam COLOR_ACTIVE = 3'b001;    // Red (currently being processed)
localparam COLOR_SORTED = 3'b010;    // Green (in final sorted position)
localparam COLOR_COMPARE = 3'b011;   // Yellow (being compared)

// Group colors for divide phase visualization
localparam COLOR_GROUP1 = 3'b100;    // Group 1 color (magenta) - Box 0
localparam COLOR_GROUP2 = 3'b101;    // Group 2 color (cyan) - Box 3
localparam COLOR_GROUP3 = 3'b110;    // Group 3 color (orange) - Box 2
localparam COLOR_GROUP4 = 3'b111;    // Group 4 color (blue) - Box 5
localparam COLOR_GROUP5 = 3'b001;    // Group 5 color (red) - Box 1
localparam COLOR_GROUP6 = 3'b010;    // Group 6 color (green) - Box 4

// Position definitions (Y coordinates on OLED)
localparam POS_TOP = 6'd8;       // Top of screen (y=8)
localparam POS_MID = 6'd32;      // Middle of screen (y=32)
localparam POS_BOTTOM = 6'd48;   // Bottom of screen (y=48)

// X position definitions (box slot positions)
// BOX_WIDTH = 14, spacing = 2, margin = 1
// Slot 0: 1 + 0*(14+2) = 1
// Slot 1: 1 + 1*(14+2) = 17
// Slot 2: 1 + 2*(14+2) = 33
// Slot 3: 1 + 3*(14+2) = 49
// Slot 4: 1 + 4*(14+2) = 65
// Slot 5: 1 + 5*(14+2) = 81
localparam X_SLOT_0 = 7'd1;
localparam X_SLOT_1 = 7'd17;
localparam X_SLOT_2 = 7'd33;
localparam X_SLOT_3 = 7'd49;
localparam X_SLOT_4 = 7'd65;
localparam X_SLOT_5 = 7'd81;

// State machine definitions (3 bits, so max 8 states)
localparam STATE_IDLE = 3'b000;
localparam STATE_INIT = 3'b001;
localparam STATE_DIVIDE = 3'b010;
localparam STATE_MERGE = 3'b011;
localparam STATE_SORTED = 3'b100;
localparam STATE_TUTORIAL_INIT = 3'b101;         // Tutorial mode: Initialize array to zeros
localparam STATE_TUTORIAL_EDIT = 3'b110;         // Tutorial mode: User edits array values
localparam STATE_TUTORIAL_DIVIDE = 3'b111;       // Tutorial mode: Automatic divide animation
// We need to add another state for merge practice, but we're out of 3-bit states
// Solution: Use a separate flag 'tutorial_practice_mode' along with states

// Divide step definitions for visualization (3-step)
localparam DIVIDE_STEP_1 = 3'd0; // [426] vs [153]
localparam DIVIDE_STEP_2 = 3'd1; // [42][6] vs [15][3]
localparam DIVIDE_STEP_3 = 3'd2; // [4][2][6] vs [1][5][3]
localparam DIVIDE_COMPLETE = 3'd3; // Divide visualization complete

// Internal registers
reg [2:0] state, next_state, state_prev;
// Internal arrays (for easier manipulation)
reg [2:0] array_data [0:5];
reg [5:0] array_positions_y [0:5]; // Y positions for animation
reg [6:0] array_positions_x [0:5]; // X positions for animation
reg [2:0] array_colors [0:5];
reg [2:0] answer_colors [0:5];     // Colors for answer boxes
reg [2:0] element_ids [0:5]; // Tracks which element (0-5) is at each position

// Tutorial mode registers
reg [2:0] cursor_pos;  // Current cursor position (0-5) in tutorial mode
reg tutorial_mode_prev;  // Previous state of tutorial_mode to detect transitions (clk domain)
reg tutorial_mode_prev_movement;  // Previous state in clk_movement domain
reg tutorial_init_needed;  // Flag to trigger tutorial initialization in clk_movement domain

// Tutorial practice mode registers
reg tutorial_practice_mode;  // Flag: we're in merge practice mode (showing 2 rows)
reg [2:0] user_answer_array [0:5];  // User's answer for the merge step (top boxes)
reg [2:0] tutorial_merge_step_target;  // Which merge step we're practicing (0-2)
reg tutorial_answer_correct;  // Flag indicating if user's answer is correct
reg [4:0] user_separator_lines;  // User's separator line placement from sw0-4
reg [7:0] flash_timer;  // Timer for green flash animation
reg tutorial_animating;  // Flag: currently animating merge
reg [5:0] element_correct;  // Per-element correctness flags (6 boxes)
reg [4:0] separator_correct;  // Per-separator correctness flags (5 separators)
reg all_correct;  // Combined flag: all elements AND separators correct
reg [2:0] separator_colors [0:4];  // Color for each separator (for flash feedback)

// Pulsing effect for active merge regions
reg [5:0] pulse_timer;  // Timer for pulsing effect (~0.5s cycle at 45Hz)
reg pulse_state;  // Toggles every 0.5s for pulsing effect
reg [5:0] merge_region_active;  // Which answer boxes should pulse (1=active)

// Separator position hints
reg [5:0] hint_timer;  // Countdown timer for showing hints (1 second at 45Hz)
reg [4:0] hint_separators;  // Which separator positions to hint

// Progressive hints - wrong attempt counter
reg [2:0] wrong_attempt_count;  // Count wrong attempts per step (0-7)

// Tutorial mode request/acknowledge flags for clock domain crossing
// Request flags: set in clk domain, cleared in clk domain when ack seen
reg cursor_left_req;
reg cursor_right_req;
reg value_up_req;
reg value_down_req;
reg check_answer_req;  // Request to check answer in practice mode
// Acknowledge flags: set in clk_movement domain, cleared in clk_movement domain
reg cursor_left_ack;
reg cursor_right_ack;
reg value_up_ack;
reg value_down_ack;
reg check_answer_ack;

// CDC Synchronizers (2-stage) for req signals (clk -> clk_movement)
reg [1:0] cursor_left_req_sync;
reg [1:0] cursor_right_req_sync;
reg [1:0] value_up_req_sync;
reg [1:0] value_down_req_sync;
reg [1:0] check_answer_req_sync;

// CDC Synchronizers (2-stage) for ack signals (clk_movement -> clk)
reg [1:0] cursor_left_ack_sync;
reg [1:0] cursor_right_ack_sync;
reg [1:0] value_up_ack_sync;
reg [1:0] value_down_ack_sync;
reg [1:0] check_answer_ack_sync;

// Debounce timers to prevent double triggering (at 100MHz)
reg [19:0] debounce_left;   // ~10ms debounce
reg [19:0] debounce_right;
reg [19:0] debounce_up;
reg [19:0] debounce_down;
reg [19:0] debounce_center;

// Integer declarations for loops (moved outside always blocks)
integer i, j, k, m, n, idx;
reg [2:0] merge_step;              // Current merge step (0-2 for bottom-up)
reg [2:0] animation_counter;       // For timing animations
reg [7:0] sort_timer;
reg [7:0] step_timer;              // Timer for each merge step (1 second delays)
reg paused;
reg [2:0] divide_step;
// Current divide step (0-5)
reg [7:0] movement_timer;

// Swap tracking to ensure swaps happen only once
reg swap_done_step1_pair1;  // Track if first pair swapped in step 1
reg swap_done_step1_pair2;  // Track if second pair swapped in step 1
reg swap_done_step2;        // Track if swap done in step 2
reg [2:0] swap_count_step3; // Track number of swaps done in step 3

// Working arrays for merge sort algorithm
reg [2:0] work_array [0:5];   // Working copy for sorting (displayed values)
reg [2:0] temp_array [0:5];   // Temporary array for merging
reg [2:0] sorted_array [0:5]; // Final sorted array for merge step 3

// Animation control
reg [5:0] target_y [0:5];          // Target Y positions for animation
reg [6:0] target_x [0:5];          // Target X positions for animation
reg move_direction;
// Button Edge Detection
// Note: btn_start, btn_pause, btn_left, btn_right, btn_center are already edge-detected
// pulses from Top_Student.v, so we use them directly without additional edge detection
wire btn_start_edge, btn_pause_edge, btn_left_edge, btn_right_edge, btn_center_edge;
assign btn_start_edge = btn_start;
assign btn_pause_edge = btn_pause;
assign btn_left_edge = btn_left;
assign btn_right_edge = btn_right;
assign btn_center_edge = btn_center;

// Animation Completion Detection
integer pos_check;
reg all_positions_match;
always @(*) begin
    all_positions_match = 1'b1;
    for (pos_check = 0; pos_check < 6; pos_check = pos_check + 1) begin
        if (array_positions_y[pos_check] != target_y[pos_check]) begin
            all_positions_match = 1'b0;
        end
    end
end
assign all_positions_reached = all_positions_match;

//==============================================================================
// CDC Synchronizers for ack signals (clk_movement -> clk)
//==============================================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cursor_left_ack_sync <= 2'b00;
        cursor_right_ack_sync <= 2'b00;
        value_up_ack_sync <= 2'b00;
        value_down_ack_sync <= 2'b00;
        check_answer_ack_sync <= 2'b00;
    end else begin
        // 2-stage synchronizer for each ack signal
        cursor_left_ack_sync <= {cursor_left_ack_sync[0], cursor_left_ack};
        cursor_right_ack_sync <= {cursor_right_ack_sync[0], cursor_right_ack};
        value_up_ack_sync <= {value_up_ack_sync[0], value_up_ack};
        value_down_ack_sync <= {value_down_ack_sync[0], value_down_ack};
        check_answer_ack_sync <= {check_answer_ack_sync[0], check_answer_ack};
    end
end

//==============================================================================
// Tutorial Mode Button Handling (runs on clk domain to catch button edges)
//==============================================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // cursor_pos is now handled in clk_movement domain
        cursor_left_req <= 1'b0;
        cursor_right_req <= 1'b0;
        value_up_req <= 1'b0;
        value_down_req <= 1'b0;
        check_answer_req <= 1'b0;

        // Initialize debounce timers
        debounce_left <= 20'd0;
        debounce_right <= 20'd0;
        debounce_up <= 20'd0;
        debounce_down <= 20'd0;
        debounce_center <= 20'd0;
    end else begin
        // ALWAYS decrement debounce timers (unconditional)
        if (debounce_left > 20'd0) debounce_left <= debounce_left - 1;
        if (debounce_right > 20'd0) debounce_right <= debounce_right - 1;
        if (debounce_up > 20'd0) debounce_up <= debounce_up - 1;
        if (debounce_down > 20'd0) debounce_down <= debounce_down - 1;
        if (debounce_center > 20'd0) debounce_center <= debounce_center - 1;

        if (state == STATE_TUTORIAL_INIT) begin
            // Initialize tutorial mode in clk domain
            // cursor_pos is now handled in clk_movement domain
            cursor_left_req <= 1'b0;
            cursor_right_req <= 1'b0;
            value_up_req <= 1'b0;
            value_down_req <= 1'b0;
        end else if ((state == STATE_TUTORIAL_EDIT || (state == STATE_TUTORIAL_DIVIDE && tutorial_practice_mode && !tutorial_animating)) && tutorial_mode) begin
            // Handle cursor navigation with LEFT/RIGHT buttons
            // Active in TUTORIAL_EDIT or TUTORIAL_DIVIDE with practice mode (not animating)
            // Only respond when tutorial_mode is active (sw15=ON AND sw10=ON)

        // LEFT button - just set request flag, actual cursor update in clk_movement
        // Only accept new button press if handshake is completely idle AND debounce expired
        // Use synchronized ack signal to avoid CDC issues
        if (btn_left_edge && !cursor_left_req && !cursor_left_ack_sync[1] && debounce_left == 20'd0) begin
            cursor_left_req <= 1'b1;  // Set request flag
            debounce_left <= 20'd20000000;  // 200ms at 100MHz
        end else if (cursor_left_req && cursor_left_ack_sync[1]) begin
            cursor_left_req <= 1'b0;  // Clear when acknowledged
        end

        // RIGHT button - just set request flag, actual cursor update in clk_movement
        // Only accept new button press if handshake is completely idle AND debounce expired
        // Use synchronized ack signal to avoid CDC issues
        if (btn_right_edge && !cursor_right_req && !cursor_right_ack_sync[1] && debounce_right == 20'd0) begin
            cursor_right_req <= 1'b1;  // Set request flag
            debounce_right <= 20'd20000000;  // 200ms at 100MHz
        end else if (cursor_right_req && cursor_right_ack_sync[1]) begin
            cursor_right_req <= 1'b0;  // Clear when acknowledged
        end

        // UP button - separate if blocks to avoid conflicts
        // Only accept new button press if handshake is completely idle AND debounce expired
        // Use synchronized ack signal to avoid CDC issues
        if (btn_start_edge && !value_up_req && !value_up_ack_sync[1] && debounce_up == 20'd0) begin
            value_up_req <= 1'b1;
            debounce_up <= 20'd20000000;  // 200ms at 100MHz
        end else if (value_up_req && value_up_ack_sync[1]) begin
            value_up_req <= 1'b0;  // Clear when acknowledged
        end

        // DOWN button - separate if blocks to avoid conflicts
        // Only accept new button press if handshake is completely idle AND debounce expired
        // Use synchronized ack signal to avoid CDC issues
        if (btn_pause_edge && !value_down_req && !value_down_ack_sync[1] && debounce_down == 20'd0) begin
            value_down_req <= 1'b1;
            debounce_down <= 20'd20000000;  // 200ms at 100MHz
        end else if (value_down_req && value_down_ack_sync[1]) begin
            value_down_req <= 1'b0;  // Clear when acknowledged
        end

        // btnC in practice mode - check answer
        // Use synchronized ack signal to avoid CDC issues
        if (state == STATE_TUTORIAL_DIVIDE && tutorial_practice_mode && !tutorial_animating) begin
            if (btn_center_edge && !check_answer_req && !check_answer_ack_sync[1] && debounce_center == 20'd0) begin
                check_answer_req <= 1'b1;  // Request answer check
                debounce_center <= 20'd20000000;  // 200ms at 100MHz
            end else if (check_answer_req && check_answer_ack_sync[1]) begin
                check_answer_req <= 1'b0;  // Clear when acknowledged
            end
        end
        end  // end of tutorial button handling
    end  // end of else (not reset)
end

//==============================================================================
// Main State Machine
//==============================================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= STATE_IDLE;
        state_prev <= STATE_IDLE;
        paused <= 0;
        tutorial_mode_prev <= 0;
    end else begin
        // Detect mode transitions
        tutorial_mode_prev <= tutorial_mode;

        // CRITICAL FIX: Detect switching from tutorial to educational mode
        // When sw10 goes OFF (tutorial_mode goes low), reset to IDLE
        if (tutorial_mode_prev && !tutorial_mode && demo_active) begin
            // Switched from tutorial to educational mode - force reset to IDLE
            state <= STATE_IDLE;
            state_prev <= STATE_IDLE;
            paused <= 0;
        end
        // CRITICAL FIX: Detect switching from educational to tutorial mode
        // When sw10 goes ON (tutorial_mode goes high), reset to IDLE then enter tutorial
        else if (!tutorial_mode_prev && tutorial_mode && demo_active) begin
            // Switched from educational to tutorial mode - force reset to IDLE
            // This ensures we enter tutorial from a clean slate
            state <= STATE_IDLE;
            state_prev <= STATE_IDLE;
            paused <= 0;
            // Note: clk_movement domain will handle clearing separators and resetting arrays
        end
        // Reset to IDLE when demo_active goes low
        else if (!demo_active) begin
            state <= STATE_IDLE;
            paused <= 0;
        end else begin
            // Pause/resume control (only for educational mode)
            if (btn_pause_edge && !tutorial_mode) begin
                paused <= ~paused;
            end

            // State transitions
            // Tutorial mode ignores pause, educational mode respects it
            if (tutorial_mode || !paused) begin
                state_prev <= state;  // Track previous state
                state <= next_state;
            end
        end
    end
end

// State transition logic
always @(*) begin
    next_state = state;
    case (state)
        STATE_IDLE: begin
            if (tutorial_mode) begin
                // Enter tutorial mode when both switches are ON
                next_state = STATE_TUTORIAL_INIT;
            end else if (educational_mode && btn_start_edge) begin
                next_state = STATE_INIT;
            end
        end
        STATE_INIT: begin
            if (!educational_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched
            end else if (sort_timer >= 8'd60) begin  // 1 second at 60Hz
                next_state = STATE_DIVIDE;
            end
        end
        STATE_DIVIDE: begin
            if (!educational_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched
            end else if (divide_step == DIVIDE_COMPLETE && step_timer >= 8'd30) begin  // 0.5 sec after divide complete
                next_state = STATE_MERGE;
            end
        end
        STATE_MERGE: begin
            if (!educational_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched
            end else if (merge_step >= 3'd3 && step_timer >= 8'd120) begin  // Wait 2s sec after final step
                next_state = STATE_SORTED;
            end
        end
        STATE_SORTED: begin
            if (!educational_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched
            end else if (btn_start_edge) begin
                next_state = STATE_INIT;
            end
        end
        STATE_TUTORIAL_INIT: begin
            // Immediately transition to edit mode (initialization happens in clk_movement)
            next_state = STATE_TUTORIAL_EDIT;
        end
        STATE_TUTORIAL_EDIT: begin
            if (!tutorial_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched off
            end else if (btn_center_edge) begin
                // User pressed center button to confirm array - start tutorial divide phase
                next_state = STATE_TUTORIAL_DIVIDE;
            end
            // Stay in edit mode until user confirms with btnC
        end
        STATE_TUTORIAL_DIVIDE: begin
            if (!tutorial_mode) begin
                next_state = STATE_IDLE;  // Exit if mode switched off
            end else if (divide_step == DIVIDE_COMPLETE && step_timer >= 8'd30) begin  // 0.5 sec after divide complete
                // Divide animation complete - stay in DIVIDE state but enter practice mode
                // We'll use tutorial_practice_mode flag to show 2 rows
                next_state = STATE_TUTORIAL_DIVIDE;  // Stay in this state
            end
        end
        default: next_state = STATE_IDLE;
    endcase
end

//==============================================================================
// CDC Synchronizers for req signals (clk -> clk_movement)
//==============================================================================
always @(posedge clk_movement or posedge reset) begin
    if (reset) begin
        cursor_left_req_sync <= 2'b00;
        cursor_right_req_sync <= 2'b00;
        value_up_req_sync <= 2'b00;
        value_down_req_sync <= 2'b00;
        check_answer_req_sync <= 2'b00;
    end else begin
        // 2-stage synchronizer for each req signal
        cursor_left_req_sync <= {cursor_left_req_sync[0], cursor_left_req};
        cursor_right_req_sync <= {cursor_right_req_sync[0], cursor_right_req};
        value_up_req_sync <= {value_up_req_sync[0], value_up_req};
        value_down_req_sync <= {value_down_req_sync[0], value_down_req};
        check_answer_req_sync <= {check_answer_req_sync[0], check_answer_req};
    end
end

//==============================================================================
// Sort Algorithm Logic (Iterative Bottom-Up Merge Sort)
//==============================================================================
always @(posedge clk_movement or posedge reset) begin
    if (reset) begin
        merge_step <= 0;
        animation_counter <= 0;
        sort_timer <= 0;
        step_timer <= 0;
        divide_step <= DIVIDE_STEP_1;
        movement_timer <= 0;

        // Initialize acknowledge flags
        cursor_left_ack <= 1'b0;
        cursor_right_ack <= 1'b0;
        value_up_ack <= 1'b0;
        value_down_ack <= 1'b0;
        check_answer_ack <= 1'b0;

        // Initialize tutorial flags
        tutorial_mode_prev_movement <= 1'b0;
        tutorial_init_needed <= 1'b0;
        tutorial_answer_correct <= 1'b0;
        flash_timer <= 8'd0;
        tutorial_animating <= 1'b0;

        // Initialize work_array with preset educational mode values
        work_array[0] <= 3'd4;
        work_array[1] <= 3'd2;
        work_array[2] <= 3'd6;
        work_array[3] <= 3'd1;
        work_array[4] <= 3'd5;
        work_array[5] <= 3'd3;

        array_colors[0] <= COLOR_NORMAL;
        array_colors[1] <= COLOR_NORMAL;
        array_colors[2] <= COLOR_NORMAL;
        array_colors[3] <= COLOR_NORMAL;
        array_colors[4] <= COLOR_NORMAL;
        array_colors[5] <= COLOR_NORMAL;

        // Reset swap tracking flags
        swap_done_step1_pair1 <= 0;
        swap_done_step1_pair2 <= 0;
        swap_done_step2 <= 0;
        swap_count_step3 <= 0;

        // Reset cursor position
        cursor_pos <= 3'd0;

        // Clear all separator lines
        separator_visible <= 5'b00000;

        // Reset tutorial practice mode
        tutorial_practice_mode <= 1'b0;
    end else if (!demo_active) begin
        // Reset everything when demo_active goes low
        merge_step <= 0;
        sort_timer <= 0;
        step_timer <= 0;
        divide_step <= DIVIDE_STEP_1;

        // Reset work_array to preset educational mode values
        work_array[0] <= 3'd4;
        work_array[1] <= 3'd2;
        work_array[2] <= 3'd6;
        work_array[3] <= 3'd1;
        work_array[4] <= 3'd5;
        work_array[5] <= 3'd3;

        array_colors[0] <= COLOR_NORMAL;
        array_colors[1] <= COLOR_NORMAL;
        array_colors[2] <= COLOR_NORMAL;
        array_colors[3] <= COLOR_NORMAL;
        array_colors[4] <= COLOR_NORMAL;
        array_colors[5] <= COLOR_NORMAL;

        // Reset swap tracking flags
        swap_done_step1_pair1 <= 0;
        swap_done_step1_pair2 <= 0;
        swap_done_step2 <= 0;
        swap_count_step3 <= 0;

        // Reset cursor position
        cursor_pos <= 3'd0;

        // Clear separators
        separator_visible <= 5'b00000;

        // Clear tutorial practice mode
        tutorial_practice_mode <= 1'b0;
        tutorial_init_needed <= 1'b0;
        tutorial_mode_prev_movement <= 1'b0;
    end else begin
        // Track tutorial_mode in clk_movement domain
        tutorial_mode_prev_movement <= tutorial_mode;

        // CRITICAL FIX: Detect mode transitions in clk_movement domain
        if (tutorial_mode_prev_movement && !tutorial_mode) begin
            // Switched from tutorial to educational - force reset
            merge_step <= 0;
            sort_timer <= 0;
            step_timer <= 0;
            divide_step <= DIVIDE_STEP_1;

            // Reset to educational mode array [4,2,6,1,5,3]
            work_array[0] <= 3'd4;
            work_array[1] <= 3'd2;
            work_array[2] <= 3'd6;
            work_array[3] <= 3'd1;
            work_array[4] <= 3'd5;
            work_array[5] <= 3'd3;

            // Reset all colors to normal
            array_colors[0] <= COLOR_NORMAL;
            array_colors[1] <= COLOR_NORMAL;
            array_colors[2] <= COLOR_NORMAL;
            array_colors[3] <= COLOR_NORMAL;
            array_colors[4] <= COLOR_NORMAL;
            array_colors[5] <= COLOR_NORMAL;

            answer_colors[0] <= COLOR_NORMAL;
            answer_colors[1] <= COLOR_NORMAL;
            answer_colors[2] <= COLOR_NORMAL;
            answer_colors[3] <= COLOR_NORMAL;
            answer_colors[4] <= COLOR_NORMAL;
            answer_colors[5] <= COLOR_NORMAL;

            separator_colors[0] <= COLOR_NORMAL;
            separator_colors[1] <= COLOR_NORMAL;
            separator_colors[2] <= COLOR_NORMAL;
            separator_colors[3] <= COLOR_NORMAL;
            separator_colors[4] <= COLOR_NORMAL;

            // Clear all separators
            separator_visible <= 5'b00000;

            // Clear tutorial mode flags
            tutorial_practice_mode <= 1'b0;
            tutorial_init_needed <= 1'b0;
            tutorial_answer_correct <= 1'b0;
            flash_timer <= 8'd0;
            tutorial_animating <= 1'b0;

            cursor_pos <= 3'd0;

            // Position reset handled in animation_control block to avoid multiple drivers
        end else if (!tutorial_mode_prev_movement && tutorial_mode) begin
            // Switched from educational to tutorial - trigger initialization
            // Clear EVERYTHING from educational mode immediately
            tutorial_init_needed <= 1'b1;
            tutorial_practice_mode <= 1'b0;
            tutorial_answer_correct <= 1'b0;
            flash_timer <= 8'd0;
            tutorial_animating <= 1'b0;

            // Clear all separators/guidelines from educational mode
            separator_visible <= 5'b00000;

            cursor_pos <= 3'd0;

            // Reset all colors to white (clear colored boxes from educational animation)
            array_colors[0] <= COLOR_NORMAL;
            array_colors[1] <= COLOR_NORMAL;
            array_colors[2] <= COLOR_NORMAL;
            array_colors[3] <= COLOR_NORMAL;
            array_colors[4] <= COLOR_NORMAL;
            array_colors[5] <= COLOR_NORMAL;

            answer_colors[0] <= COLOR_NORMAL;
            answer_colors[1] <= COLOR_NORMAL;
            answer_colors[2] <= COLOR_NORMAL;
            answer_colors[3] <= COLOR_NORMAL;
            answer_colors[4] <= COLOR_NORMAL;
            answer_colors[5] <= COLOR_NORMAL;

            separator_colors[0] <= COLOR_NORMAL;
            separator_colors[1] <= COLOR_NORMAL;
            separator_colors[2] <= COLOR_NORMAL;
            separator_colors[3] <= COLOR_NORMAL;
            separator_colors[4] <= COLOR_NORMAL;

            // Reset timers and step counters
            merge_step <= 0;
            sort_timer <= 0;
            step_timer <= 0;
            divide_step <= DIVIDE_STEP_1;

            // Reset swap tracking flags
            swap_done_step1_pair1 <= 0;
            swap_done_step1_pair2 <= 0;
            swap_done_step2 <= 0;
            swap_count_step3 <= 0;

            // Position reset handled in animation_control block to avoid multiple drivers
        end else if (demo_active && ((state == STATE_TUTORIAL_INIT || state == STATE_TUTORIAL_EDIT || state == STATE_TUTORIAL_DIVIDE) || !paused)) begin
        // Tutorial mode always runs, educational mode only when not paused
        case (state)
            STATE_IDLE: begin
                // Only restore educational mode array when NOT about to enter tutorial mode
                if (!tutorial_mode) begin
                    work_array[0] <= 3'd4;
                    work_array[1] <= 3'd2;
                    work_array[2] <= 3'd6;
                    work_array[3] <= 3'd1;
                    work_array[4] <= 3'd5;
                    work_array[5] <= 3'd3;
                end else begin
                    // Tutorial mode is active - ensure init flag is set
                    tutorial_init_needed <= 1'b1;
                end

                // Reset colors to white
                array_colors[0] <= COLOR_NORMAL;
                array_colors[1] <= COLOR_NORMAL;
                array_colors[2] <= COLOR_NORMAL;
                array_colors[3] <= COLOR_NORMAL;
                array_colors[4] <= COLOR_NORMAL;
                array_colors[5] <= COLOR_NORMAL;

                // Reset cursor position
                cursor_pos <= 3'd0;

                // Clear separators
                separator_visible <= 5'b00000;

                // Reset timers
                sort_timer <= 0;
                step_timer <= 0;
            end

            STATE_INIT: begin
                work_array[0] <= 3'd4;
                work_array[1] <= 3'd2;
                work_array[2] <= 3'd6;
                work_array[3] <= 3'd1;
                work_array[4] <= 3'd5;
                work_array[5] <= 3'd3;
                array_colors[0] <= COLOR_NORMAL;
                array_colors[1] <= COLOR_NORMAL;
                array_colors[2] <= COLOR_NORMAL;
                array_colors[3] <= COLOR_NORMAL;
                array_colors[4] <= COLOR_NORMAL;
                array_colors[5] <= COLOR_NORMAL;
                // Initialize element IDs (each element starts at its position)
                element_ids[0] <= 3'd0;
                element_ids[1] <= 3'd1;
                element_ids[2] <= 3'd2;
                element_ids[3] <= 3'd3;
                element_ids[4] <= 3'd4;
                element_ids[5] <= 3'd5;
                // Reset swap tracking flags
                swap_done_step1_pair1 <= 0;
                swap_done_step1_pair2 <= 0;
                swap_done_step2 <= 0;
                swap_count_step3 <= 0;
                // Initialize separators (all invisible)
                separator_visible <= 5'b00000;
                divide_step <= DIVIDE_STEP_1;
                merge_step <= 0;
                sort_timer <= sort_timer + 1;
                step_timer <= 0;
            end
           
            STATE_DIVIDE: begin
                // Timer logic: increment *unless* a transition is happening
                if (step_timer >= 8'd72 && all_positions_reached) begin // ~1.6s @ 45Hz
                    // Timer will be reset to 0 inside the case statement
                end else if (divide_step < DIVIDE_COMPLETE) begin
                    step_timer <= step_timer + 1;
                end else begin
                    // After last step, wait for FSM to transition
                    step_timer <= step_timer + 1;
                end
               
                case (divide_step)
                    DIVIDE_STEP_1: begin  // [426] vs [153]
                        if (step_timer == 8'd1) begin
                            set_divide_colors_step1(1'b0);
                            separator_visible <= 5'b00100; // Show separator at position 2: [426]|[153]
                        end else if (step_timer >= 8'd72 && all_positions_reached) begin
                            divide_step <= divide_step + 1;
                            step_timer <= 0;
                        end
                    end
                    DIVIDE_STEP_2: begin  // [42][6] vs [15][3]
                        if (step_timer == 8'd1) begin
                            set_divide_colors_step2(1'b0);
                            separator_visible <= 5'b10110; // Show separators at positions 1,2,4: [42]|[6]|[15]|[3]
                        end else if (step_timer >= 8'd72 && all_positions_reached) begin
                            divide_step <= divide_step + 1;
                            step_timer <= 0;
                        end
                    end
                    DIVIDE_STEP_3: begin  // [4][2][6] vs [1][5][3]
                        if (step_timer == 8'd1) begin
                            set_divide_colors_step3(1'b0);
                            separator_visible <= 5'b11111; // Show all separators: [4]|[2]|[6]|[1]|[5]|[3]
                        end else if (step_timer >= 8'd72 && all_positions_reached) begin
                            divide_step <= DIVIDE_COMPLETE; // Go to complete
                            step_timer <= 0;
                        end
                    end
                    default: begin // DIVIDE_COMPLETE
                        step_timer <= step_timer + 1; // Wait for FSM to transition
                    end
                endcase
            end
           
            STATE_MERGE: begin
                // Increased merge step timer to ~2.6s (120 ticks)
                if (step_timer >= 8'd120 && all_positions_reached) begin
                    // Timer will be reset to 0 inside the case statement
                end else if (merge_step < 3'd3) begin // Don't increment after last step
                    step_timer <= step_timer + 1;
                end else begin
                    // After last step, wait for FSM to transition
                    step_timer <= step_timer + 1;
                end
       
                case (merge_step)
                    3'd0: begin  // Step 1: Merge pairs [24][6]|[15][3]
                        // ALWAYS update separators for this step (unconditional)
                        // After pairs merge: [24][6]|[15][3]
                        // Remove separators 0 and 3 (within merged pairs)
                        separator_visible <= 5'b10110; // Separators at positions 1,2,4

                        // Reset swap flags at start of step (when timer is low)
                        if (step_timer < 8'd40) begin
                            swap_done_step1_pair1 <= 0;
                            swap_done_step1_pair2 <= 0;
                        end

                        // Call task continuously
                        merge_and_sort_step1(1'b0);

                        if (step_timer >= 8'd120 && all_positions_reached) begin
                            merge_step <= merge_step + 1;
                            step_timer <= 0;
                        end
                    end
                    3'd1: begin  // Step 2: Merge groups of 3 [246]|[135]
                        // ALWAYS update separators for this step (unconditional)
                        // After groups merge: [246]|[135]
                        // Remove separators 1 and 4 (within merged groups)
                        separator_visible <= 5'b00100; // Separator at position 2

                        // Reset swap flags at start of step
                        if (step_timer < 8'd10) begin
                            swap_done_step2 <= 0;
                        end

                        // Call task continuously
                        merge_and_sort_step2(1'b0);

                        if (step_timer >= 8'd120 && all_positions_reached) begin
                            merge_step <= merge_step + 1;
                            step_timer <= 0;
                        end
                    end
                    3'd2: begin  // Step 3: Final merge [123456]
                        // Reset swap count at start of step
                        if (step_timer < 8'd10) begin
                            swap_count_step3 <= 0;
                        end

                        // Keep separator initially, then remove once merging starts
                        if (step_timer < 8'd30) begin
                            separator_visible <= 5'b00100; // Keep separator at position 2 initially
                        end else begin
                            separator_visible <= 5'b00000; // Remove all separators: [123456]
                        end

                        // Call task continuously
                        merge_and_sort_step3(1'b0);

                        if (step_timer >= 8'd120 && all_positions_reached) begin
                            merge_step <= merge_step + 1;
                            step_timer <= 0;
                        end
                    end
                    default: begin // merge_step == 3'd3
                        // Keep counting until FSM transitions to SORTED
                        separator_visible <= 5'b00000; // No separators in sorted state
                        step_timer <= step_timer + 1;
                    end
                endcase
            end
           
            STATE_SORTED: begin
                sort_timer <= 0;
                step_timer <= 0;
            end

            STATE_TUTORIAL_INIT: begin
                // Set flag to indicate initialization is needed
                tutorial_init_needed <= 1'b1;

                // Reset timer
                sort_timer <= 0;
            end

            STATE_TUTORIAL_EDIT: begin
                // Keep timer at 0 in edit mode
                sort_timer <= 0;

                // Initialize array to zeros when first entering tutorial mode
                if (tutorial_init_needed) begin
                    work_array[0] <= 3'd0;
                    work_array[1] <= 3'd0;
                    work_array[2] <= 3'd0;
                    work_array[3] <= 3'd0;
                    work_array[4] <= 3'd0;
                    work_array[5] <= 3'd0;
                    cursor_pos <= 3'd0;
                    tutorial_init_needed <= 1'b0;  // Clear flag after initialization
                end

                // Process value modification requests from button handler (clk domain)
                // Use synchronized req signals to avoid CDC issues
                // Separate if blocks to avoid mutually exclusive conditions
                if (value_up_req_sync[1] && !value_up_ack) begin
                    if (work_array[cursor_pos] == 3'd7) begin
                        work_array[cursor_pos] <= 3'd0;  // Wrap to 0
                    end else begin
                        work_array[cursor_pos] <= work_array[cursor_pos] + 1;
                    end
                    value_up_ack <= 1'b1;  // Set acknowledge flag
                end
                if (!value_up_req_sync[1] && value_up_ack) begin
                    value_up_ack <= 1'b0;  // Clear ack when request is cleared
                end

                if (value_down_req_sync[1] && !value_down_ack) begin
                    if (work_array[cursor_pos] == 3'd0) begin
                        work_array[cursor_pos] <= 3'd7;  // Wrap to 7
                    end else begin
                        work_array[cursor_pos] <= work_array[cursor_pos] - 1;
                    end
                    value_down_ack <= 1'b1;  // Set acknowledge flag
                end
                if (!value_down_req_sync[1] && value_down_ack) begin
                    value_down_ack <= 1'b0;  // Clear ack when request is cleared
                end

                // Process cursor movement requests and update cursor_pos
                // Use synchronized req signals to avoid CDC issues
                if (cursor_left_req_sync[1] && !cursor_left_ack) begin
                    // Move cursor left with wrapping
                    if (cursor_pos == 3'd0) begin
                        cursor_pos <= 3'd5;  // Wrap to end
                    end else begin
                        cursor_pos <= cursor_pos - 1;
                    end
                    cursor_left_ack <= 1'b1;  // Acknowledge
                end
                if (!cursor_left_req_sync[1] && cursor_left_ack) begin
                    cursor_left_ack <= 1'b0;
                end

                if (cursor_right_req_sync[1] && !cursor_right_ack) begin
                    // Move cursor right with wrapping
                    if (cursor_pos == 3'd5) begin
                        cursor_pos <= 3'd0;  // Wrap to start
                    end else begin
                        cursor_pos <= cursor_pos + 1;
                    end
                    cursor_right_ack <= 1'b1;  // Acknowledge
                end
                if (!cursor_right_req_sync[1] && cursor_right_ack) begin
                    cursor_right_ack <= 1'b0;
                end

                // Update colors: cursor position gets CYAN, others get WHITE
                array_colors[0] <= (cursor_pos == 3'd0) ? COLOR_GROUP2 : COLOR_NORMAL;
                array_colors[1] <= (cursor_pos == 3'd1) ? COLOR_GROUP2 : COLOR_NORMAL;
                array_colors[2] <= (cursor_pos == 3'd2) ? COLOR_GROUP2 : COLOR_NORMAL;
                array_colors[3] <= (cursor_pos == 3'd3) ? COLOR_GROUP2 : COLOR_NORMAL;
                array_colors[4] <= (cursor_pos == 3'd4) ? COLOR_GROUP2 : COLOR_NORMAL;
                array_colors[5] <= (cursor_pos == 3'd5) ? COLOR_GROUP2 : COLOR_NORMAL;
            end

            STATE_TUTORIAL_DIVIDE: begin
                if (!tutorial_practice_mode) begin
                    // PHASE 1: Tutorial divide animation - same as educational mode divide
                    // Initialize divide_step if transitioning from TUTORIAL_EDIT
                    if (state_prev == STATE_TUTORIAL_EDIT) begin
                        divide_step <= DIVIDE_STEP_1;
                        step_timer <= 0;
                        tutorial_practice_mode <= 1'b0;
                        tutorial_animating <= 1'b0;
                    end

                    // Timer logic: increment unless a transition is happening
                    if (step_timer >= 8'd72 && all_positions_reached) begin // ~1.6s @ 45Hz
                        // Timer will be reset to 0 inside the case statement
                    end else if (divide_step < DIVIDE_COMPLETE) begin
                        step_timer <= step_timer + 1;
                    end else begin
                        // After last step, wait for FSM to transition
                        step_timer <= step_timer + 1;
                    end

                    case (divide_step)
                        DIVIDE_STEP_1: begin  // First split
                            if (step_timer == 8'd1) begin
                                set_divide_colors_step1(1'b0);
                                separator_visible <= 5'b00100; // Show separator at position 2
                            end else if (step_timer >= 8'd72 && all_positions_reached) begin
                                divide_step <= divide_step + 1;
                                step_timer <= 0;
                            end
                        end
                        DIVIDE_STEP_2: begin  // Second split
                            if (step_timer == 8'd1) begin
                                set_divide_colors_step2(1'b0);
                                separator_visible <= 5'b10110; // Show separators at positions 1,2,4
                            end else if (step_timer >= 8'd72 && all_positions_reached) begin
                                divide_step <= divide_step + 1;
                                step_timer <= 0;
                            end
                        end
                        DIVIDE_STEP_3: begin  // Final split - all individual
                            if (step_timer == 8'd1) begin
                                set_divide_colors_step3(1'b0);
                                separator_visible <= 5'b11111; // Show all separators
                            end else if (step_timer >= 8'd72 && all_positions_reached) begin
                                divide_step <= DIVIDE_COMPLETE;
                                step_timer <= 0;
                            end
                        end
                        default: begin // DIVIDE_COMPLETE
                            if (step_timer >= 8'd30) begin
                                // Transition to practice mode after 0.5s delay
                                tutorial_practice_mode <= 1'b1;
                                tutorial_merge_step_target <= 3'd0;  // Start with first merge step
                                step_timer <= 0;

                                // Copy work array to answer boxes (start with current state)
                                user_answer_array[0] <= work_array[0];
                                user_answer_array[1] <= work_array[1];
                                user_answer_array[2] <= work_array[2];
                                user_answer_array[3] <= work_array[3];
                                user_answer_array[4] <= work_array[4];
                                user_answer_array[5] <= work_array[5];

                                // Clear separator lines (user will set them with switches)
                                separator_visible <= 5'b00000;

                                // Initialize hint timer and separators for step 0
                                hint_timer <= 6'd45;  // Show hints for 1 second (~45 ticks at 45Hz)
                                hint_separators <= 5'b10110;  // Step 0: positions 1,2,4

                                // Initialize pulse timer and state
                                pulse_timer <= 0;
                                pulse_state <= 0;

                                // Initialize wrong attempt counter for progressive hints
                                wrong_attempt_count <= 0;
                            end else begin
                                step_timer <= step_timer + 1;
                            end
                        end
                    endcase
                end else begin
                    // PHASE 2: Tutorial practice mode - user fills in answer
                    // Keep timer at 0
                    step_timer <= 0;

                    // Initialize answer array to zeros when first entering
                    if (step_timer == 0 && state_prev != STATE_TUTORIAL_DIVIDE) begin
                        user_answer_array[0] <= 3'd0;
                        user_answer_array[1] <= 3'd0;
                        user_answer_array[2] <= 3'd0;
                        user_answer_array[3] <= 3'd0;
                        user_answer_array[4] <= 3'd0;
                        user_answer_array[5] <= 3'd0;
                        cursor_pos <= 3'd0;
                    end

                    // Update separator lines based on sw0-4
                    // sw0 = line after index 0 (separator_visible[0])
                    // sw1 = line after index 1 (separator_visible[1])
                    // sw2 = line after index 2 (separator_visible[2])
                    // sw3 = line after index 3 (separator_visible[3])
                    // sw4 = line after index 4 (separator_visible[4])
                    separator_visible <= {line_switches[4], line_switches[3], line_switches[2], line_switches[1], line_switches[0]};

                    // Process value modification (same as TUTORIAL_EDIT)
                    // Use synchronized req signals to avoid CDC issues
                    if (value_up_req_sync[1] && !value_up_ack) begin
                        if (user_answer_array[cursor_pos] == 3'd7) begin
                            user_answer_array[cursor_pos] <= 3'd0;
                        end else begin
                            user_answer_array[cursor_pos] <= user_answer_array[cursor_pos] + 1;
                        end
                        value_up_ack <= 1'b1;
                    end
                    if (!value_up_req_sync[1] && value_up_ack) begin
                        value_up_ack <= 1'b0;
                    end

                    if (value_down_req_sync[1] && !value_down_ack) begin
                        if (user_answer_array[cursor_pos] == 3'd0) begin
                            user_answer_array[cursor_pos] <= 3'd7;
                        end else begin
                            user_answer_array[cursor_pos] <= user_answer_array[cursor_pos] - 1;
                        end
                        value_down_ack <= 1'b1;
                    end
                    if (!value_down_req_sync[1] && value_down_ack) begin
                        value_down_ack <= 1'b0;
                    end

                    // Process cursor movement
                    // Use synchronized req signals to avoid CDC issues
                    if (cursor_left_req_sync[1] && !cursor_left_ack) begin
                        if (cursor_pos == 3'd0) begin
                            cursor_pos <= 3'd5;
                        end else begin
                            cursor_pos <= cursor_pos - 1;
                        end
                        cursor_left_ack <= 1'b1;
                    end
                    if (!cursor_left_req_sync[1] && cursor_left_ack) begin
                        cursor_left_ack <= 1'b0;
                    end

                    if (cursor_right_req_sync[1] && !cursor_right_ack) begin
                        if (cursor_pos == 3'd5) begin
                            cursor_pos <= 3'd0;
                        end else begin
                            cursor_pos <= cursor_pos + 1;
                        end
                        cursor_right_ack <= 1'b1;
                    end
                    if (!cursor_right_req_sync[1] && cursor_right_ack) begin
                        cursor_right_ack <= 1'b0;
                    end

                    // Keep bottom array colors from divide step
                    // (Don't change array_colors for work_array)

                    // Pulse timer for active merge regions (0.5s cycle)
                    pulse_timer <= pulse_timer + 1;
                    if (pulse_timer >= 6'd22) begin  // ~0.5s at 45Hz
                        pulse_timer <= 0;
                        pulse_state <= ~pulse_state;  // Toggle pulse state
                    end

                    // Determine which boxes are in active merge regions (progressive hints)
                    // Only show pulsing borders after at least 1 wrong attempt
                    if (wrong_attempt_count >= 3'd1) begin
                        case (tutorial_merge_step_target)
                            3'd0: begin  // Step 0: Merge pairs [0,1] and [3,4]
                                merge_region_active <= 6'b011011;  // boxes 0,1,3,4
                            end
                            3'd1: begin  // Step 1: Merge groups [0,1,2] and [3,4,5]
                                merge_region_active <= 6'b111111;  // All boxes
                            end
                            default: begin  // Step 2: Final merge all
                                merge_region_active <= 6'b111111;  // All boxes
                            end
                        endcase
                    end else begin
                        merge_region_active <= 6'b000000;  // No pulsing before first wrong attempt
                    end

                    // Hint timer countdown
                    if (hint_timer > 0) begin
                        hint_timer <= hint_timer - 1;
                    end

                    // Flash feedback based on per-element correctness
                    if (flash_timer > 0 && flash_timer < 8'd30) begin
                        // Flash in progress (~0.67 seconds = 30 ticks at 45Hz)
                        // Each box flashes green (correct) or red (wrong)
                        for (i = 0; i < 6; i = i + 1) begin
                            answer_colors[i] <= element_correct[i] ? COLOR_SORTED : COLOR_ACTIVE;  // Green or Red
                        end
                        // Each separator flashes green (correct) or red (wrong)
                        for (i = 0; i < 5; i = i + 1) begin
                            separator_colors[i] <= separator_correct[i] ? COLOR_SORTED : COLOR_ACTIVE;  // Green or Red
                        end
                        flash_timer <= flash_timer + 1;
                    end else if (flash_timer >= 8'd30) begin
                        // Flash complete - check if all correct
                        if (all_correct) begin
                            // All correct - start merge animation
                            flash_timer <= 0;
                            tutorial_answer_correct <= 1'b0;
                            tutorial_animating <= 1'b1;
                            // Copy answer to work_array for animation
                            work_array[0] <= user_answer_array[0];
                            work_array[1] <= user_answer_array[1];
                            work_array[2] <= user_answer_array[2];
                            work_array[3] <= user_answer_array[3];
                            work_array[4] <= user_answer_array[4];
                            work_array[5] <= user_answer_array[5];

                            // Update work array colors to show merge progression
                            case (tutorial_merge_step_target)
                                3'd0: begin  // After first merge: pairs get group colors
                                    array_colors[0] <= COLOR_GROUP1;  // Purple
                                    array_colors[1] <= COLOR_GROUP1;  // Purple (pair merged)
                                    array_colors[2] <= COLOR_GROUP3;  // Orange (single element)
                                    array_colors[3] <= COLOR_GROUP2;  // Cyan
                                    array_colors[4] <= COLOR_GROUP2;  // Cyan (pair merged)
                                    array_colors[5] <= COLOR_GROUP5;  // Blue (single element)
                                end
                                3'd1: begin  // After second merge: groups get group colors
                                    array_colors[0] <= COLOR_GROUP1;  // Purple
                                    array_colors[1] <= COLOR_GROUP1;  // Purple
                                    array_colors[2] <= COLOR_GROUP1;  // Purple (group merged)
                                    array_colors[3] <= COLOR_GROUP2;  // Cyan
                                    array_colors[4] <= COLOR_GROUP2;  // Cyan
                                    array_colors[5] <= COLOR_GROUP2;  // Cyan (group merged)
                                end
                                default: begin  // After final merge: all green (sorted)
                                    array_colors[0] <= COLOR_SORTED;  // Green
                                    array_colors[1] <= COLOR_SORTED;  // Green
                                    array_colors[2] <= COLOR_SORTED;  // Green
                                    array_colors[3] <= COLOR_SORTED;  // Green
                                    array_colors[4] <= COLOR_SORTED;  // Green
                                    array_colors[5] <= COLOR_SORTED;  // Green
                                end
                            endcase
                        end else begin
                            // Not all correct - reset flash timer to allow retry
                            flash_timer <= 0;
                            tutorial_answer_correct <= 1'b0;
                            // Reset answer and separator colors to normal
                            for (i = 0; i < 6; i = i + 1) begin
                                answer_colors[i] <= COLOR_NORMAL;  // White
                            end
                            for (i = 0; i < 5; i = i + 1) begin
                                separator_colors[i] <= COLOR_NORMAL;  // White
                            end
                        end
                    end else if (tutorial_animating) begin
                        // Hide answer boxes during merge animation (by making them match work array)
                        // Animation will be handled in animation_control block
                        // After animation completes and positions reach target, go to next step
                        if (all_positions_reached && step_timer >= 8'd45) begin
                            // Animation complete, reset for next step
                            tutorial_animating <= 1'b0;
                            tutorial_merge_step_target <= tutorial_merge_step_target + 1;
                            step_timer <= 0;

                            // Copy work array to answer boxes (start with current state)
                            user_answer_array[0] <= work_array[0];
                            user_answer_array[1] <= work_array[1];
                            user_answer_array[2] <= work_array[2];
                            user_answer_array[3] <= work_array[3];
                            user_answer_array[4] <= work_array[4];
                            user_answer_array[5] <= work_array[5];

                            // Initialize hint timer and separators for current step (already incremented)
                            hint_timer <= 6'd45;  // Show hints for 1 second
                            case (tutorial_merge_step_target)  // Current step (already incremented above)
                                3'd1: hint_separators <= 5'b00100;  // Step 1: position 2
                                3'd2: hint_separators <= 5'b00000;  // Step 2: no separators
                                default: hint_separators <= 5'b00000;
                            endcase

                            // Reset wrong attempt counter for new step
                            wrong_attempt_count <= 0;
                        end else begin
                            step_timer <= step_timer + 1;
                        end
                        // Keep answer boxes hidden (normal color)
                        answer_colors[0] <= COLOR_NORMAL;
                        answer_colors[1] <= COLOR_NORMAL;
                        answer_colors[2] <= COLOR_NORMAL;
                        answer_colors[3] <= COLOR_NORMAL;
                        answer_colors[4] <= COLOR_NORMAL;
                        answer_colors[5] <= COLOR_NORMAL;
                        // Keep separators normal during animation
                        separator_colors[0] <= COLOR_NORMAL;
                        separator_colors[1] <= COLOR_NORMAL;
                        separator_colors[2] <= COLOR_NORMAL;
                        separator_colors[3] <= COLOR_NORMAL;
                        separator_colors[4] <= COLOR_NORMAL;
                    end else begin
                        // Normal mode: Update answer box colors: cursor position gets CYAN, others get WHITE
                        answer_colors[0] <= (cursor_pos == 3'd0) ? COLOR_GROUP2 : COLOR_NORMAL;
                        answer_colors[1] <= (cursor_pos == 3'd1) ? COLOR_GROUP2 : COLOR_NORMAL;
                        answer_colors[2] <= (cursor_pos == 3'd2) ? COLOR_GROUP2 : COLOR_NORMAL;
                        answer_colors[3] <= (cursor_pos == 3'd3) ? COLOR_GROUP2 : COLOR_NORMAL;
                        answer_colors[4] <= (cursor_pos == 3'd4) ? COLOR_GROUP2 : COLOR_NORMAL;
                        answer_colors[5] <= (cursor_pos == 3'd5) ? COLOR_GROUP2 : COLOR_NORMAL;
                        // Separators remain normal (white) during editing
                        separator_colors[0] <= COLOR_NORMAL;
                        separator_colors[1] <= COLOR_NORMAL;
                        separator_colors[2] <= COLOR_NORMAL;
                        separator_colors[3] <= COLOR_NORMAL;
                        separator_colors[4] <= COLOR_NORMAL;

                        // Handle answer check request
                        // Use synchronized req signal to avoid CDC issues
                        if (check_answer_req_sync[1] && !check_answer_ack) begin
                            check_tutorial_answer(1'b0);
                            check_answer_ack <= 1'b1;
                        end
                        if (!check_answer_req_sync[1] && check_answer_ack) begin
                            check_answer_ack <= 1'b0;
                        end
                    end
                end
            end
        endcase
        end  // end of else if (demo_active...)
    end  // end of else begin (tutorial_mode_prev_movement tracking)
end

//==============================================================================
// Animation and Position Control
//==============================================================================
always @(posedge clk_movement or posedge reset) begin: animation_control
    if (reset) begin
        for (i = 0; i < 6; i = i + 1) begin
            array_positions_y[i] <= POS_TOP;
            target_y[i] <= POS_TOP;
        end
        // Initialize X positions to their slot positions
        array_positions_x[0] <= X_SLOT_0;
        array_positions_x[1] <= X_SLOT_1;
        array_positions_x[2] <= X_SLOT_2;
        array_positions_x[3] <= X_SLOT_3;
        array_positions_x[4] <= X_SLOT_4;
        array_positions_x[5] <= X_SLOT_5;
        target_x[0] <= X_SLOT_0;
        target_x[1] <= X_SLOT_1;
        target_x[2] <= X_SLOT_2;
        target_x[3] <= X_SLOT_3;
        target_x[4] <= X_SLOT_4;
        target_x[5] <= X_SLOT_5;
        move_direction <= 0;
    end else if (tutorial_mode_prev_movement && !tutorial_mode) begin
        // Mode transition: tutorial → educational
        // Reset positions immediately (no animation)
        for (i = 0; i < 6; i = i + 1) begin
            array_positions_y[i] <= POS_TOP;
            target_y[i] <= POS_TOP;
        end
        array_positions_x[0] <= X_SLOT_0;
        array_positions_x[1] <= X_SLOT_1;
        array_positions_x[2] <= X_SLOT_2;
        array_positions_x[3] <= X_SLOT_3;
        array_positions_x[4] <= X_SLOT_4;
        array_positions_x[5] <= X_SLOT_5;
        target_x[0] <= X_SLOT_0;
        target_x[1] <= X_SLOT_1;
        target_x[2] <= X_SLOT_2;
        target_x[3] <= X_SLOT_3;
        target_x[4] <= X_SLOT_4;
        target_x[5] <= X_SLOT_5;
        move_direction <= 0;
    end else if (!tutorial_mode_prev_movement && tutorial_mode) begin
        // Mode transition: educational → tutorial
        // Reset positions immediately (no animation)
        for (i = 0; i < 6; i = i + 1) begin
            array_positions_y[i] <= POS_TOP;
            target_y[i] <= POS_TOP;
        end
        array_positions_x[0] <= X_SLOT_0;
        array_positions_x[1] <= X_SLOT_1;
        array_positions_x[2] <= X_SLOT_2;
        array_positions_x[3] <= X_SLOT_3;
        array_positions_x[4] <= X_SLOT_4;
        array_positions_x[5] <= X_SLOT_5;
        target_x[0] <= X_SLOT_0;
        target_x[1] <= X_SLOT_1;
        target_x[2] <= X_SLOT_2;
        target_x[3] <= X_SLOT_3;
        target_x[4] <= X_SLOT_4;
        target_x[5] <= X_SLOT_5;
        move_direction <= 0;
    end else if (!demo_active) begin
        // Reset positions when demo_active goes low
        for (i = 0; i < 6; i = i + 1) begin
            array_positions_y[i] <= POS_TOP;
            target_y[i] <= POS_TOP;
        end
        array_positions_x[0] <= X_SLOT_0;
        array_positions_x[1] <= X_SLOT_1;
        array_positions_x[2] <= X_SLOT_2;
        array_positions_x[3] <= X_SLOT_3;
        array_positions_x[4] <= X_SLOT_4;
        array_positions_x[5] <= X_SLOT_5;
        target_x[0] <= X_SLOT_0;
        target_x[1] <= X_SLOT_1;
        target_x[2] <= X_SLOT_2;
        target_x[3] <= X_SLOT_3;
        target_x[4] <= X_SLOT_4;
        target_x[5] <= X_SLOT_5;
        move_direction <= 0;
    end else if (!paused && demo_active) begin
        if (state == STATE_INIT || state == STATE_TUTORIAL_INIT || state == STATE_TUTORIAL_EDIT) begin
            for (i = 0; i < 6; i = i + 1) begin
                array_positions_y[i] <= POS_TOP;
                target_y[i] <= POS_TOP;
            end
            // Reset X positions to their slots
            array_positions_x[0] <= X_SLOT_0;
            array_positions_x[1] <= X_SLOT_1;
            array_positions_x[2] <= X_SLOT_2;
            array_positions_x[3] <= X_SLOT_3;
            array_positions_x[4] <= X_SLOT_4;
            array_positions_x[5] <= X_SLOT_5;
            target_x[0] <= X_SLOT_0;
            target_x[1] <= X_SLOT_1;
            target_x[2] <= X_SLOT_2;
            target_x[3] <= X_SLOT_3;
            target_x[4] <= X_SLOT_4;
            target_x[5] <= X_SLOT_5;
        end
        else if (state == STATE_DIVIDE || (state == STATE_TUTORIAL_DIVIDE && !tutorial_practice_mode) || (state == STATE_TUTORIAL_DIVIDE && tutorial_animating)) begin
            // Special handling for tutorial animation (moving up after correct answer)
            if (state == STATE_TUTORIAL_DIVIDE && tutorial_animating) begin
                move_direction <= 1; // Moving up
                // Move to next merge step position based on tutorial_merge_step_target
                case (tutorial_merge_step_target)
                    3'd0: begin  // First merge - move to 2/3 position
                        for (j = 0; j < 6; j = j + 1) begin
                            target_y[j] <= POS_TOP + 2 * (POS_BOTTOM - POS_TOP) / 3;
                            if (array_positions_y[j] > target_y[j]) begin
                                array_positions_y[j] <= array_positions_y[j] - 1;
                            end
                        end
                    end
                    3'd1: begin  // Second merge - move to 1/3 position
                        for (j = 0; j < 6; j = j + 1) begin
                            target_y[j] <= POS_TOP + (POS_BOTTOM - POS_TOP) / 3;
                            if (array_positions_y[j] > target_y[j]) begin
                                array_positions_y[j] <= array_positions_y[j] - 1;
                            end
                        end
                    end
                    default: begin  // Final merge - move to top
                        for (j = 0; j < 6; j = j + 1) begin
                            target_y[j] <= POS_TOP;
                            if (array_positions_y[j] > target_y[j]) begin
                                array_positions_y[j] <= array_positions_y[j] - 1;
                            end
                        end
                    end
                endcase
            end else begin
                // Normal divide animation (moving down)
                move_direction <= 0; // Moving down
                case (divide_step)
                DIVIDE_STEP_1: begin // 1/3 down
                    for (j = 0; j < 6; j = j + 1) begin
                        target_y[j] <= POS_TOP + (POS_BOTTOM - POS_TOP) / 3;
                        if (array_positions_y[j] < target_y[j]) begin
                            array_positions_y[j] <= array_positions_y[j] + 1;
                        end
                    end
                end
                DIVIDE_STEP_2: begin // 2/3 down
                    for (j = 0; j < 6; j = j + 1) begin
                        target_y[j] <= POS_TOP + 2 * (POS_BOTTOM - POS_TOP) / 3;
                        if (array_positions_y[j] < target_y[j]) begin
                            array_positions_y[j] <= array_positions_y[j] + 1;
                        end
                    end
                end
                DIVIDE_STEP_3, DIVIDE_COMPLETE: begin // 3/3 (bottom)
                    for (j = 0; j < 6; j = j + 1) begin
                        target_y[j] <= POS_BOTTOM;
                        if (array_positions_y[j] < target_y[j]) begin
                            array_positions_y[j] <= array_positions_y[j] + 1;
                        end
                    end
                end
                default: begin
                    for (j = 0; j < 6; j = j + 1) begin
                        target_y[j] <= POS_BOTTOM;
                        if (array_positions_y[j] < target_y[j]) begin
                            array_positions_y[j] <= array_positions_y[j] + 1;
                        end
                    end
                end
                endcase
            end  // end of else (normal divide animation)
        end
        else if (state == STATE_MERGE) begin
            move_direction <= 1; // Moving up
            if (merge_step == 3'd0) begin // Step 1: 33% up from bottom
                for (k = 0; k < 6; k = k + 1) begin
                    target_y[k] <= POS_BOTTOM - (POS_BOTTOM - POS_TOP) / 3; // 67% from top
                    if (array_positions_y[k] > target_y[k]) begin
                        array_positions_y[k] <= array_positions_y[k] - 1;
                    end
                    // Animate X positions
                    if (array_positions_x[k] < target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] + 1;
                    end else if (array_positions_x[k] > target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] - 1;
                    end
                end
            end else if (merge_step == 3'd1) begin // Step 2: 67% up from bottom
                for (k = 0; k < 6; k = k + 1) begin
                    target_y[k] <= POS_BOTTOM - 2 * (POS_BOTTOM - POS_TOP) / 3; // 33% from top
                    if (array_positions_y[k] > target_y[k]) begin
                        array_positions_y[k] <= array_positions_y[k] - 1;
                    end
                    // Animate X positions
                    if (array_positions_x[k] < target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] + 1;
                    end else if (array_positions_x[k] > target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] - 1;
                    end
                end
            end else begin // Step 3 or later: 100% up (back to top)
                for (k = 0; k < 6; k = k + 1) begin
                    target_y[k] <= POS_TOP; // Back to top
                    if (array_positions_y[k] > target_y[k]) begin
                        array_positions_y[k] <= array_positions_y[k] - 1;
                    end
                    // Animate X positions
                    if (array_positions_x[k] < target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] + 1;
                    end else if (array_positions_x[k] > target_x[k]) begin
                        array_positions_x[k] <= array_positions_x[k] - 1;
                    end
                end
            end
        end
    end
end

//==============================================================================
// Array Data Assignment
//==============================================================================
always @(*) begin: array_data_assignment
    for (n = 0; n < 6; n = n + 1) begin
        array_data[n] = work_array[n];
    end
end

//==============================================================================
// Array to Flat Conversion (for module ports)
//==============================================================================
always @(*) begin: array_to_flat_conversion
    array_data_flat = {array_data[5], array_data[4], array_data[3], array_data[2], array_data[1], array_data[0]};
    answer_data_flat = {user_answer_array[5], user_answer_array[4], user_answer_array[3], user_answer_array[2], user_answer_array[1], user_answer_array[0]};
    array_positions_y_flat = {array_positions_y[5], array_positions_y[4], array_positions_y[3], array_positions_y[2], array_positions_y[1], array_positions_y[0]};
    array_positions_x_flat = {array_positions_x[5], array_positions_x[4], array_positions_x[3], array_positions_x[2], array_positions_x[1], array_positions_x[0]};
    array_colors_flat = {array_colors[5], array_colors[4], array_colors[3], array_colors[2], array_colors[1], array_colors[0]};
    answer_colors_flat = {answer_colors[5], answer_colors[4], answer_colors[3], answer_colors[2], answer_colors[1], answer_colors[0]};
    separator_colors_flat = {separator_colors[4], separator_colors[3], separator_colors[2], separator_colors[1], separator_colors[0]};
end

//==============================================================================
// Status Outputs
//==============================================================================
always @(*) begin
    current_state = state;
    divide_step_out = divide_step;
    merge_step_out = merge_step;
    cursor_pos_out = cursor_pos;
    practice_mode_active = tutorial_practice_mode;
    pulse_state_out = pulse_state;
    merge_region_active_flat = merge_region_active;
    hint_timer_out = hint_timer;
    hint_separators_flat = hint_separators;
    sorting_active = (state == STATE_DIVIDE || state == STATE_MERGE);
    animation_busy = (state != STATE_IDLE && state != STATE_SORTED);
    sort_complete = (state == STATE_SORTED);
end

//==============================================================================
// Helper Functions
//==============================================================================
function all_at_bottom; input dummy; integer i; begin all_at_bottom = 1;
for (i = 0; i < 6; i = i + 1) begin if (array_positions_y[i] != POS_BOTTOM) begin all_at_bottom = 0;
end end end endfunction
function all_at_top; input dummy; integer i; begin all_at_top = 1;
for (i = 0; i < 6; i = i + 1) begin if (array_positions_y[i] != POS_TOP) begin all_at_top = 0;
end end end endfunction
function sort_algorithm_complete; input dummy; begin sort_algorithm_complete = (merge_step >= 3'd3); end endfunction
function is_in_current_merge_range; input [2:0] index;
begin is_in_current_merge_range = (merge_step < 3'd3); end endfunction
function is_sorted_at_position; input [2:0] index;
begin case (index) 0: is_sorted_at_position = (work_array[0] == 3'd1); 1: is_sorted_at_position = (work_array[1] == 3'd2);
2: is_sorted_at_position = (work_array[2] == 3'd3); 3: is_sorted_at_position = (work_array[3] == 3'd4); 4: is_sorted_at_position = (work_array[4] == 3'd5);
5: is_sorted_at_position = (work_array[5] == 3'd6); default: is_sorted_at_position = 0;
endcase end endfunction

//==============================================================================
// Answer Checking Task for Tutorial Practice Mode
//==============================================================================
task check_tutorial_answer;
    input dummy;
    reg [2:0] expected_array [0:5];
    reg [4:0] expected_separators;
    reg answer_matches;
    reg separators_match;
    reg [2:0] temp;  // Temporary variable for bubble sort swapping
    integer check_idx;
    begin
        // Compute expected answer based on merge step
        case (tutorial_merge_step_target)
            3'd0: begin  // Step 0: Merge pairs [0,1], [2], [3,4], [5]
                // Sort pairs
                if (work_array[0] < work_array[1]) begin
                    expected_array[0] = work_array[0];
                    expected_array[1] = work_array[1];
                end else begin
                    expected_array[0] = work_array[1];
                    expected_array[1] = work_array[0];
                end
                expected_array[2] = work_array[2];  // Stays alone
                if (work_array[3] < work_array[4]) begin
                    expected_array[3] = work_array[3];
                    expected_array[4] = work_array[4];
                end else begin
                    expected_array[3] = work_array[4];
                    expected_array[4] = work_array[3];
                end
                expected_array[5] = work_array[5];  // Stays alone
                expected_separators = 5'b10110;  // Lines after indices 1, 2, 4
            end
            3'd1: begin  // Step 1: Merge groups [0,1,2], [3,4,5]
                // Sort left group [0,1,2]
                expected_array[0] = (work_array[0] < work_array[1] && work_array[0] < work_array[2]) ? work_array[0] :
                                   (work_array[1] < work_array[2]) ? work_array[1] : work_array[2];
                expected_array[2] = (work_array[0] > work_array[1] && work_array[0] > work_array[2]) ? work_array[0] :
                                   (work_array[1] > work_array[2]) ? work_array[1] : work_array[2];
                expected_array[1] = work_array[0] + work_array[1] + work_array[2] - expected_array[0] - expected_array[2];
                // Sort right group [3,4,5]
                expected_array[3] = (work_array[3] < work_array[4] && work_array[3] < work_array[5]) ? work_array[3] :
                                   (work_array[4] < work_array[5]) ? work_array[4] : work_array[5];
                expected_array[5] = (work_array[3] > work_array[4] && work_array[3] > work_array[5]) ? work_array[3] :
                                   (work_array[4] > work_array[5]) ? work_array[4] : work_array[5];
                expected_array[4] = work_array[3] + work_array[4] + work_array[5] - expected_array[3] - expected_array[5];
                expected_separators = 5'b00100;  // Line after index 2
            end
            default: begin  // Step 2: Merge all [0,1,2,3,4,5]
                // Sort the work_array to get expected result
                // Copy work_array to temp variables for sorting
                expected_array[0] = work_array[0];
                expected_array[1] = work_array[1];
                expected_array[2] = work_array[2];
                expected_array[3] = work_array[3];
                expected_array[4] = work_array[4];
                expected_array[5] = work_array[5];

                // Simple bubble sort (6 elements, unrolled)
                // Pass 1
                if (expected_array[0] > expected_array[1]) begin temp = expected_array[0]; expected_array[0] = expected_array[1]; expected_array[1] = temp; end
                if (expected_array[1] > expected_array[2]) begin temp = expected_array[1]; expected_array[1] = expected_array[2]; expected_array[2] = temp; end
                if (expected_array[2] > expected_array[3]) begin temp = expected_array[2]; expected_array[2] = expected_array[3]; expected_array[3] = temp; end
                if (expected_array[3] > expected_array[4]) begin temp = expected_array[3]; expected_array[3] = expected_array[4]; expected_array[4] = temp; end
                if (expected_array[4] > expected_array[5]) begin temp = expected_array[4]; expected_array[4] = expected_array[5]; expected_array[5] = temp; end
                // Pass 2
                if (expected_array[0] > expected_array[1]) begin temp = expected_array[0]; expected_array[0] = expected_array[1]; expected_array[1] = temp; end
                if (expected_array[1] > expected_array[2]) begin temp = expected_array[1]; expected_array[1] = expected_array[2]; expected_array[2] = temp; end
                if (expected_array[2] > expected_array[3]) begin temp = expected_array[2]; expected_array[2] = expected_array[3]; expected_array[3] = temp; end
                if (expected_array[3] > expected_array[4]) begin temp = expected_array[3]; expected_array[3] = expected_array[4]; expected_array[4] = temp; end
                if (expected_array[4] > expected_array[5]) begin temp = expected_array[4]; expected_array[4] = expected_array[5]; expected_array[5] = temp; end
                // Pass 3
                if (expected_array[0] > expected_array[1]) begin temp = expected_array[0]; expected_array[0] = expected_array[1]; expected_array[1] = temp; end
                if (expected_array[1] > expected_array[2]) begin temp = expected_array[1]; expected_array[1] = expected_array[2]; expected_array[2] = temp; end
                if (expected_array[2] > expected_array[3]) begin temp = expected_array[2]; expected_array[2] = expected_array[3]; expected_array[3] = temp; end
                if (expected_array[3] > expected_array[4]) begin temp = expected_array[3]; expected_array[3] = expected_array[4]; expected_array[4] = temp; end
                if (expected_array[4] > expected_array[5]) begin temp = expected_array[4]; expected_array[4] = expected_array[5]; expected_array[5] = temp; end
                // Pass 4
                if (expected_array[0] > expected_array[1]) begin temp = expected_array[0]; expected_array[0] = expected_array[1]; expected_array[1] = temp; end
                if (expected_array[1] > expected_array[2]) begin temp = expected_array[1]; expected_array[1] = expected_array[2]; expected_array[2] = temp; end
                if (expected_array[2] > expected_array[3]) begin temp = expected_array[2]; expected_array[2] = expected_array[3]; expected_array[3] = temp; end
                if (expected_array[3] > expected_array[4]) begin temp = expected_array[3]; expected_array[3] = expected_array[4]; expected_array[4] = temp; end
                if (expected_array[4] > expected_array[5]) begin temp = expected_array[4]; expected_array[4] = expected_array[5]; expected_array[5] = temp; end
                // Pass 5
                if (expected_array[0] > expected_array[1]) begin temp = expected_array[0]; expected_array[0] = expected_array[1]; expected_array[1] = temp; end
                if (expected_array[1] > expected_array[2]) begin temp = expected_array[1]; expected_array[1] = expected_array[2]; expected_array[2] = temp; end
                if (expected_array[2] > expected_array[3]) begin temp = expected_array[2]; expected_array[2] = expected_array[3]; expected_array[3] = temp; end
                if (expected_array[3] > expected_array[4]) begin temp = expected_array[3]; expected_array[3] = expected_array[4]; expected_array[4] = temp; end
                if (expected_array[4] > expected_array[5]) begin temp = expected_array[4]; expected_array[4] = expected_array[5]; expected_array[5] = temp; end

                expected_separators = 5'b00000;  // No lines
            end
        endcase

        // Check each element individually and store per-element correctness
        // All steps now check against expected_array (step 2 now has computed sorted array)
        for (check_idx = 0; check_idx < 6; check_idx = check_idx + 1) begin
            element_correct[check_idx] <= (user_answer_array[check_idx] == expected_array[check_idx]);
        end

        // Check each separator individually
        for (check_idx = 0; check_idx < 5; check_idx = check_idx + 1) begin
            separator_correct[check_idx] <= (separator_visible[check_idx] == expected_separators[check_idx]);
        end

        // Compute overall correctness (all elements AND all separators correct)
        // All steps now check against expected_array
        answer_matches = 1'b1;
        for (check_idx = 0; check_idx < 6; check_idx = check_idx + 1) begin
            if (user_answer_array[check_idx] != expected_array[check_idx]) begin
                answer_matches = 1'b0;
            end
        end
        separators_match = (separator_visible == expected_separators);
        all_correct <= (answer_matches && separators_match);

        // Set correct flag and start flash timer
        tutorial_answer_correct <= (answer_matches && separators_match);
        flash_timer <= 1;  // Start flash timer at 1 to trigger flash immediately

        // Increment wrong attempt counter if answer is incorrect (for progressive hints)
        if (!(answer_matches && separators_match)) begin
            wrong_attempt_count <= wrong_attempt_count + 1;
        end
    end
endtask

//==============================================================================
// Color Setting Tasks for Divide Phase Visualization
//==============================================================================
task set_divide_colors_step1; input dummy; begin array_colors[0] <= COLOR_GROUP1; array_colors[1] <= COLOR_GROUP1;
array_colors[2] <= COLOR_GROUP1; array_colors[3] <= COLOR_GROUP2; array_colors[4] <= COLOR_GROUP2; array_colors[5] <= COLOR_GROUP2; end endtask
task set_divide_colors_step2; input dummy;
begin array_colors[0] <= COLOR_GROUP1; array_colors[1] <= COLOR_GROUP1; array_colors[2] <= COLOR_GROUP3; array_colors[3] <= COLOR_GROUP2; array_colors[4] <= COLOR_GROUP2; array_colors[5] <= COLOR_GROUP4;
end endtask
task set_divide_colors_step3; input dummy; begin array_colors[0] <= COLOR_GROUP1; array_colors[1] <= COLOR_GROUP5; array_colors[2] <= COLOR_GROUP3; array_colors[3] <= COLOR_GROUP2;
array_colors[4] <= COLOR_GROUP6; array_colors[5] <= COLOR_GROUP4; end endtask

//==============================================================================
// Helper Tasks for Swapping
//==============================================================================

// Helper function to get X slot position for a given slot index
function [6:0] get_x_slot;
    input [2:0] slot;
    begin
        case (slot)
            3'd0: get_x_slot = X_SLOT_0;
            3'd1: get_x_slot = X_SLOT_1;
            3'd2: get_x_slot = X_SLOT_2;
            3'd3: get_x_slot = X_SLOT_3;
            3'd4: get_x_slot = X_SLOT_4;
            3'd5: get_x_slot = X_SLOT_5;
            default: get_x_slot = X_SLOT_0;
        endcase
    end
endfunction

// Helper task to swap two positions
task swap_positions;
    input [2:0] pos_a;
    input [2:0] pos_b;
    reg [2:0] temp_data;
    reg [2:0] temp_color;
    reg [2:0] temp_id;
    begin
        // Swap values
        temp_data = work_array[pos_a];
        work_array[pos_a] <= work_array[pos_b];
        work_array[pos_b] <= temp_data;

        // Swap colors
        temp_color = array_colors[pos_a];
        array_colors[pos_a] <= array_colors[pos_b];
        array_colors[pos_b] <= temp_color;

        // Swap element IDs
        temp_id = element_ids[pos_a];
        element_ids[pos_a] <= element_ids[pos_b];
        element_ids[pos_b] <= temp_id;

        // Set new target X positions (elements swap slots)
        target_x[pos_a] <= get_x_slot(pos_b);
        target_x[pos_b] <= get_x_slot(pos_a);
    end
endtask

//==============================================================================
// Merge Phase Tasks with Color Coding - FIXED VERSION
//==============================================================================

// Merge Step 1: Merge pairs [4,2] -> [2,4] and [1,5] -> [1,5]
task merge_and_sort_step1;
    input dummy;
    begin
        // --- Set Colors Based on Timer ---
        if (step_timer < 8'd30) begin  // First phase: maintain divide colors from DIVIDE_STEP_3
            // Keep existing colors - do nothing

        end else if (step_timer < 8'd75) begin  // Second phase: show comparison/sorting
            // Keep existing divide colors while sorting
            // No color change during comparison

        end else if (step_timer == 8'd75) begin  // Trigger swaps ONCE on this tick
            // Perform swap for pair 1 if needed and not yet done
            if (!swap_done_step1_pair1 && work_array[0] > work_array[1]) begin
                swap_positions(3'd0, 3'd1);  // Swap 4 and 2 -> [2,4,6,1,5,3]
                swap_done_step1_pair1 <= 1;
            end
            // Perform swap for pair 2 if needed and not yet done
            if (!swap_done_step1_pair2 && work_array[3] > work_array[4]) begin
                swap_positions(3'd3, 3'd4);  // Swap if 1 > 5 (won't happen)
                swap_done_step1_pair2 <= 1;
            end

        end else begin  // After swap completes: change to new merged group colors
            // Group 1: [2 4] is now a merged pair - assign new group color
            array_colors[0] <= COLOR_GROUP1;  // Purple
            array_colors[1] <= COLOR_GROUP1;  // Purple
            // Group 2: [1 5] is now a merged pair - assign new group color
            array_colors[3] <= COLOR_GROUP2;  // Cyan
            array_colors[4] <= COLOR_GROUP2;  // Cyan
            // Elements 2 and 5 keep their divide colors (not yet merged)
        end
    end
endtask

// Merge Step 2: Merge [2,4] + [6] -> [2,4,6] and [1,5] + [3] -> [1,3,5]
task merge_and_sort_step2;
    input dummy;
    begin
        // --- Set Colors Based on Timer ---
        if (step_timer < 8'd60) begin  // First half: keep colors from step 1
            // Keep existing colors from step 1:
            // [2,4] = purple (from step 1), [6] = divide color (orange/red)
            // [1,5] = cyan (from step 1), [3] = divide color (blue)
            // No color change during sorting

        end else if (step_timer == 8'd60) begin  // Trigger swap ONCE on this tick
            // Merge [1,5] + [3] -> [1,3,5]
            // Current array: [2,4,6,1,5,3]
            // Need to insert 3 between 1 and 5
            if (!swap_done_step2 && work_array[5] < work_array[4]) begin
                swap_positions(3'd4, 3'd5);  // Swap 5 and 3 -> [2,4,6,1,3,5]
                swap_done_step2 <= 1;
            end

        end else begin  // After sorting: assign new group colors
            // Set merged group [2,4,6] to new group color (Purple)
            array_colors[0] <= COLOR_GROUP1; // Purple
            array_colors[1] <= COLOR_GROUP1; // Purple
            array_colors[2] <= COLOR_GROUP1; // Purple

            // Set merged group [1,3,5] to new group color (Cyan)
            array_colors[3] <= COLOR_GROUP2; // Cyan
            array_colors[4] <= COLOR_GROUP2; // Cyan
            array_colors[5] <= COLOR_GROUP2; // Cyan
        end
    end
endtask

// Merge Step 3: Merge [2,4,6] + [1,3,5] -> [1,2,3,4,5,6]
task merge_and_sort_step3;
    input dummy;
    begin
        // --- Set Colors Based on Timer ---
        if (step_timer < 8'd30) begin  // First phase: keep colors from step 2
            // Keep existing colors from step 2:
            // [2,4,6] = purple (from step 2)
            // [1,3,5] = cyan (from step 2)
            // No color change yet

        end else if (step_timer >= 8'd30 && step_timer < 8'd90) begin  // Swapping phase
            // Perform sequential swaps to achieve final order
            // Current: [2,4,6,1,3,5]
            // Target:  [1,2,3,4,5,6]

            // Strategy: Move 1 to front, then 3 to position 2
            // [2,4,6,1,3,5] -> swap(0,3) -> [1,4,6,2,3,5]
            // [1,4,6,2,3,5] -> swap(1,3) -> [1,2,6,4,3,5]
            // [1,2,6,4,3,5] -> swap(2,4) -> [1,2,3,4,6,5]
            // [1,2,3,4,6,5] -> swap(4,5) -> [1,2,3,4,5,6]

            if (step_timer == 8'd30 && swap_count_step3 == 3'd0) begin
                swap_positions(3'd0, 3'd3);  // Swap pos 0 and 3: [2,4,6,1,3,5] -> [1,4,6,2,3,5]
                swap_count_step3 <= 3'd1;
            end else if (step_timer == 8'd40 && swap_count_step3 == 3'd1) begin
                swap_positions(3'd1, 3'd3);  // Swap pos 1 and 3: [1,4,6,2,3,5] -> [1,2,6,4,3,5]
                swap_count_step3 <= 3'd2;
            end else if (step_timer == 8'd50 && swap_count_step3 == 3'd2) begin
                swap_positions(3'd2, 3'd4);  // Swap pos 2 and 4: [1,2,6,4,3,5] -> [1,2,3,4,6,5]
                swap_count_step3 <= 3'd3;
            end else if (step_timer == 8'd60 && swap_count_step3 == 3'd3) begin
                swap_positions(3'd4, 3'd5);  // Swap pos 4 and 5: [1,2,3,4,6,5] -> [1,2,3,4,5,6]
                swap_count_step3 <= 3'd4;
            end

            // Keep existing colors during swapping (purple/cyan from step 2)
            // No color change while sorting

        end else begin  // After sorting completes: assign final sorted color
            // Set all colors to sorted (Green) - entire array is now one sorted group
            array_colors[0] <= COLOR_SORTED; // Green
            array_colors[1] <= COLOR_SORTED; // Green
            array_colors[2] <= COLOR_SORTED; // Green
            array_colors[3] <= COLOR_SORTED; // Green
            array_colors[4] <= COLOR_SORTED; // Green
            array_colors[5] <= COLOR_SORTED; // Green
        end
    end
endtask

endmodule