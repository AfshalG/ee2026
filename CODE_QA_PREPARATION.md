# Code Q&A Preparation Guide
## EE2026 Merge Sort Visualization Project

This document highlights key code segments you should be prepared to explain during your Q&A session.

---

## 1. PROJECT OVERVIEW

**What it does:** FPGA-based merge sort visualization system with educational and tutorial modes, displaying animated sorting on an OLED screen.

**Key Features:**
- Educational mode: Automated merge sort visualization
- Tutorial mode: Interactive learning with user input
- Practice mode: Users solve merge steps themselves
- Real-time animation with color-coded visualization

---

## 2. TOP-LEVEL ARCHITECTURE (Top_Student.v)

### 2.1 Clock Generation System (Lines 24-43)

```verilog
reg [15:0] clk_counter_6p25MHz = 0;
reg clk_6p25MHz = 0;

always @(posedge clk) begin
    clk_counter_6p25MHz <= clk_counter_6p25MHz + 1;
    if (clk_counter_6p25MHz >= 16'd7) begin
        clk_counter_6p25MHz <= 0;
        clk_6p25MHz <= ~clk_6p25MHz;
    end
end
```

**Why this matters:**
- Generates 6.25MHz clock from 100MHz system clock
- Required for OLED display interface (SPI communication)
- Uses clock division: 100MHz / 8 = 12.5MHz, then toggle = 6.25MHz
- Counter resets every 8 cycles to maintain frequency accuracy

**Q&A Tip:** Explain why we need different clock domains for different peripherals.

---

### 2.2 Button Debouncing (Lines 58-70)

```verilog
reg [2:0] btnU_sync = 3'b000;
always @(posedge clk) begin
    btnU_sync <= {btnU_sync[1:0], btnU};
end
```

**Why this matters:**
- 3-stage shift register for button synchronization
- Prevents metastability from asynchronous button inputs
- Registers button state across 3 clock cycles for stable reading

**Q&A Tip:** Discuss metastability issues in digital design and CDC (Clock Domain Crossing).

---

### 2.3 Edge Detection (Lines 74-76)

```verilog
assign btn_start = btnU_sync[2] && !btnU_sync[1];
```

**Why this matters:**
- Detects rising edge: current state HIGH, previous state LOW
- Produces single-cycle pulse instead of continuous signal
- Prevents multiple triggers from single button press

**Q&A Tip:** Show how this prevents accidental repeated actions.

---

### 2.4 Mode Control Logic (Lines 49-52)

```verilog
wire educational_mode;
wire tutorial_mode;
assign educational_mode = sw[15] && !sw[10];
assign tutorial_mode = sw[15] && sw[10];
```

**Why this matters:**
- sw[15] = Master enable for merge sort demo
- sw[10] = Tutorial mode toggle
- Clear separation between viewing mode and interactive mode

---

## 3. MERGE SORT CONTROLLER FSM (merge_sort_controller.v)

### 3.1 State Machine Definition (Lines 88-96)

```verilog
localparam STATE_IDLE = 3'b000;
localparam STATE_INIT = 3'b001;
localparam STATE_DIVIDE = 3'b010;
localparam STATE_MERGE = 3'b011;
localparam STATE_SORTED = 3'b100;
localparam STATE_TUTORIAL_INIT = 3'b101;
localparam STATE_TUTORIAL_EDIT = 3'b110;
localparam STATE_TUTORIAL_DIVIDE = 3'b111;
```

**Why this matters:**
- 8 states for complete visualization flow
- Separate states for educational vs tutorial modes
- Binary encoding for efficient FPGA implementation

**Q&A Tip:** Explain the state transition diagram and why each state is necessary.

---

### 3.2 Clock Domain Crossing (Lines 160-172, 233-248)

```verilog
// CDC Synchronizers (2-stage) for req signals (clk -> clk_movement)
reg [1:0] cursor_left_req_sync;
always @(posedge clk_movement) begin
    cursor_left_req_sync <= {cursor_left_req_sync[0], cursor_left_req};
end
```

**Why this matters:**
- **CRITICAL CONCEPT:** Two different clock domains:
  - `clk` domain (100MHz): Button detection, fast response
  - `clk_movement` domain (~45Hz): Animation updates
- 2-stage synchronizer prevents metastability
- Handshake protocol ensures reliable data transfer

**Q&A Tip:** This is a VERY IMPORTANT topic! Be ready to explain:
1. Why we need multiple clock domains
2. What metastability is
3. How 2-stage synchronizers work
4. The request/acknowledge handshake mechanism

---

### 3.3 Color Coding System (Lines 54-65)

```verilog
localparam COLOR_NORMAL = 3'b000;    // White
localparam COLOR_ACTIVE = 3'b001;    // Red (currently being processed)
localparam COLOR_SORTED = 3'b010;    // Green (in final sorted position)
localparam COLOR_COMPARE = 3'b011;   // Yellow (being compared)
localparam COLOR_GROUP1 = 3'b100;    // Magenta
localparam COLOR_GROUP2 = 3'b101;    // Cyan
```

**Why this matters:**
- Visual feedback system for algorithm state
- 3-bit color codes map to RGB565 colors in display module
- Groups distinguished by color during divide phase

**Q&A Tip:** Explain how color helps users understand what the algorithm is doing.

---

### 3.4 Position System (Lines 68-85)

```verilog
localparam POS_TOP = 6'd8;
localparam POS_MID = 6'd32;
localparam POS_BOTTOM = 6'd48;

localparam X_SLOT_0 = 7'd1;
localparam X_SLOT_1 = 7'd17;
localparam X_SLOT_2 = 7'd33;
// ... (spacing = 16 pixels per box)
```

**Why this matters:**
- Y positions: 3 vertical levels for merge tree visualization
- X positions: 6 horizontal slots for array elements
- Box width = 14px, spacing = 2px, margin = 1px
- Total: 1 + 6*(14+2) = 97 pixels (fits in 96px OLED width with adjustment)

**Q&A Tip:** Show how the layout fits the 96x64 OLED display constraints.

---

### 3.5 Animation System (Lines 220-228)

```verilog
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
```

**Why this matters:**
- Handshake signal between animation engine and FSM
- FSM sets target positions, animation engine moves incrementally
- State machine waits for `all_positions_reached` before next step
- Ensures smooth, non-blocking animations

**Q&A Tip:** Explain the producer-consumer pattern here.

---

### 3.6 Debounce Timers (Lines 174-179, 269-274)

```verilog
reg [19:0] debounce_left;   // ~10ms debounce

if (debounce_left > 20'd0) debounce_left <= debounce_left - 1;

if (btn_left_edge && debounce_left == 20'd0) begin
    cursor_left_req <= 1'b1;
    debounce_left <= 20'd20000000;  // 200ms at 100MHz
end
```

**Why this matters:**
- Prevents button bounce from creating multiple events
- 200ms lockout period after each button press
- Unconditional decrement ensures timer always counts down

**Q&A Tip:** Explain mechanical button bounce and why software debouncing is needed.

---

## 4. DISPLAY ENGINE (merge_sort_display.v)

### 4.1 Pixel Coordinate System (Lines 66-70)

```verilog
wire [6:0] x_coord;
wire [5:0] y_coord;
assign x_coord = pixel_index % OLED_WIDTH;
assign y_coord = pixel_index / OLED_WIDTH;
```

**Why this matters:**
- OLED controller provides linear pixel index (0-6143)
- Convert to 2D coordinates: x (0-95), y (0-63)
- Division/modulo implemented in hardware (expensive!)

**Q&A Tip:** Discuss hardware costs of division vs multiplication.

---

### 4.2 Array Unpacking (Lines 57-64)

```verilog
wire [2:0] array_data [0:5];
assign {array_data[5], array_data[4], array_data[3],
        array_data[2], array_data[1], array_data[0]} = array_data_flat;
```

**Why this matters:**
- Module ports can't have 2D arrays in Verilog
- "Flatten" arrays to 1D bit vectors for ports
- "Unpack" inside module for easier manipulation
- 6 elements × 3 bits = 18-bit flat vector

**Q&A Tip:** Explain Verilog limitations and workarounds.

---

### 4.3 Generate Blocks for Box Rendering (Lines 106-121)

```verilog
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
            .is_cursor(...),
            .pixel_color(box_pixel_colors[i]),
            .is_box_pixel(box_is_active[i])
        );
    end
endgenerate
```

**Why this matters:**
- `generate` creates 6 parallel box renderer instances
- Each box renderer operates independently for same pixel
- Priority encoder selects which box to display
- **Key insight:** All boxes render simultaneously, not sequentially

**Q&A Tip:** Explain parallelism in hardware vs software loops.

---

### 4.4 Priority Encoder (Lines 177-186)

```verilog
assign any_box_active = box_is_active[0] | box_is_active[1] |
                        box_is_active[2] | box_is_active[3] |
                        box_is_active[4] | box_is_active[5];

assign active_box_index = box_is_active[0] ? 3'd0 :
                         box_is_active[1] ? 3'd1 :
                         box_is_active[2] ? 3'd2 :
                         // ... priority: box 0 highest
```

**Why this matters:**
- Resolves overlapping boxes at same pixel
- Box 0 has highest priority (rendered on top)
- Single combinational logic path (no loops)
- Essential for layered rendering

**Q&A Tip:** Explain why priority matters during animations when boxes move.

---

### 4.5 Pixel Pipeline (Lines 259-292)

```verilog
always @(*) begin
    if (!demo_active) begin
        pixel_data = COLOR_BLACK;
    end else if (any_pulsing_border) begin
        pixel_data = COLOR_YELLOW;
    end else if (any_answer_box_active) begin
        pixel_data = answer_box_pixel_colors[...];
    end else if (any_box_active) begin
        pixel_data = box_pixel_colors[...];
    end else if (is_separator_pixel) begin
        pixel_data = /* separator color */;
    end else if (is_hint_separator_pixel) begin
        pixel_data = COLOR_FAINT_WHITE;
    end else begin
        pixel_data = background_pixel;
    end
end
```

**Why this matters:**
- Priority chain: highest priority elements checked first
- Pulsing borders > answer boxes > main boxes > separators > hints > background
- Determines final pixel color for OLED display
- Runs for EVERY pixel (6144 times per frame!)

**Q&A Tip:** Discuss rendering performance and priority ordering.

---

## 5. FONT RENDERING (merge_sort_numbers.v)

### 5.1 ROM-Based Font Storage (Lines 20-100)

```verilog
reg [5:0] font_rom [0:63];

initial begin
    // Number 1 (addresses 8-15)
    font_rom[8] = 6'b001100; // Row 0
    font_rom[9] = 6'b011100; // Row 1
    // ... 8 rows per digit
    font_rom[15] = 6'b111111; // Row 7
end
```

**Why this matters:**
- 6x8 pixel font for digits 0-7
- ROM = Read-Only Memory (initialized at synthesis)
- 8 digits × 8 rows = 64 addresses
- 6 bits per row (6 pixels wide)

**Q&A Tip:** Explain ROM vs RAM and why ROM is used here.

---

### 5.2 Font Address Calculation (Lines 103-107)

```verilog
wire [5:0] rom_address;
assign rom_address = (number << 3) + row;

wire [5:0] row_data = font_rom[rom_address];
```

**Why this matters:**
- `number << 3` = `number * 8` (bit shift is faster)
- Each digit occupies 8 consecutive addresses
- `+ row` selects which row within the digit
- Single-cycle lookup (combinational)

**Q&A Tip:** Explain bit shifting as fast multiplication/division by powers of 2.

---

### 5.3 Pixel Extraction (Lines 109-116)

```verilog
always @(*) begin
    if (number <= 3'd7 && row < 4'd8 && col < 4'd6) begin
        pixel_on = row_data[5 - col];
    end else begin
        pixel_on = 1'b0;
    end
end
```

**Why this matters:**
- `row_data[5 - col]`: MSB is leftmost pixel
- Bounds checking prevents invalid accesses
- Returns 1 (pixel on) or 0 (pixel off)

---

### 5.4 Box Renderer Integration (Lines 125-234)

```verilog
module number_box_renderer(
    input  wire [6:0]  x_coord,
    input  wire [5:0]  y_coord,
    input  wire [2:0]  number_value,
    input  wire [6:0]  box_x_pos,
    input  wire [5:0]  box_y_pos,
    input  wire [2:0]  color_code,
    input  wire        is_cursor,
    output reg  [15:0] pixel_color,
    output wire        is_box_pixel
);
```

**Why this matters:**
- Combines border rendering + number font
- Dynamic positioning (box can move during animation)
- Cursor mode: 3-pixel thick border vs 1-pixel normal
- Outputs RGB565 color for OLED

**Key calculations:**
- Border detection (Lines 195-197)
- Number centering (Lines 200-208)
- Color selection (Lines 222-231)

---

## 6. KEY ALGORITHMIC CONCEPTS

### 6.1 Bottom-Up Merge Sort Strategy

**Educational Mode Visualization:**
1. **Divide Phase** (visual only, no actual sorting):
   - Show array being split into groups
   - 3 steps: [426|153] → [42|6|15|3] → [4|2|6|1|5|3]

2. **Merge Phase** (actual sorting):
   - Step 0: Merge pairs → [24|6|15|3]
   - Step 1: Merge groups of 4 → [246|135]
   - Step 2: Final merge → [123456]

**Q&A Tip:** Explain why "bottom-up" (iterative) vs "top-down" (recursive).

---

### 6.2 Tutorial Mode Features

1. **Edit Mode:**
   - User sets initial array values (0-7)
   - Cursor navigation with LEFT/RIGHT
   - Value adjust with UP/DOWN

2. **Practice Mode:**
   - System shows divide animation
   - User places separator lines to segment array
   - User fills in merged result (top row)
   - System validates and provides feedback

3. **Hint System:**
   - Ghost separators appear after 1 second
   - Pulsing yellow borders show active merge regions
   - Progressive hints based on wrong attempts

---

## 7. COMMON Q&A TOPICS

### Topic 1: Why Multiple Clock Domains?

**Answer:**
- OLED SPI requires 6.25MHz clock
- Animations need slow updates (~45Hz) for visibility
- Button handling needs fast response (100MHz)
- Each peripheral has different timing requirements

### Topic 2: How Does Animation Work?

**Answer:**
1. FSM sets target X/Y positions
2. Animation engine increments current position each clk_movement cycle
3. When current == target, animation complete
4. FSM waits for `all_positions_reached` handshake

### Topic 3: RGB565 Color Format

**Answer:**
- 16-bit color: 5 bits red, 6 bits green, 5 bits blue
- Green gets extra bit (human eye more sensitive)
- Example: `16'hF800` = pure red (11111_000000_00000)
- Trade-off: Less storage than RGB888, good enough for OLED

### Topic 4: Why Flatten Arrays?

**Answer:**
- Verilog doesn't allow 2D arrays in module ports
- Solution: Pack into flat bit vector
- Example: `[3:0] data [0:2]` → `[11:0] data_flat`
- Unpack inside module using concatenation assignment

### Topic 5: Generate vs For Loop

**Answer:**
- `generate`: Creates hardware instances at synthesis time
- `for` loop: Sequential operations at runtime
- Generate = parallel hardware (6 box renderers simultaneously)
- For loop = single hardware unit reused sequentially

---

## 8. DEMO TALKING POINTS

### Demonstration Flow:

1. **Show Educational Mode:**
   - Press btnU to start
   - Watch divide phase visualization
   - Point out color coding
   - Show merge animation with movement

2. **Show Tutorial Mode:**
   - Toggle sw[10] to enter tutorial
   - Edit array values
   - Confirm with btnC
   - Attempt merge step with intentional mistakes
   - Show hint system activating

3. **Highlight Technical Features:**
   - Smooth animations (clk_movement)
   - Button debouncing (no double-triggers)
   - Color feedback (visual algorithm state)
   - Clock domain crossing (stable operation)

---

## 9. POTENTIAL QUESTIONS & ANSWERS

**Q: Why 6 elements instead of 8?**
A: OLED width constraint (96 pixels). 6 boxes × 16 pixels/box = 96 pixels exactly.

**Q: How do you handle button bounce?**
A: 3-stage synchronizer + 200ms debounce timer prevents multiple triggers.

**Q: What happens if boxes overlap during animation?**
A: Priority encoder selects highest priority box (box 0 > box 1 > ...).

**Q: Why use ROM for fonts instead of RAM?**
A: Font data never changes, so ROM is smaller/faster. Initialized at synthesis.

**Q: How does the separator feedback work?**
A: System compares user's switches with correct positions, flashes green/red, shows per-separator status.

**Q: What's the frame rate?**
A: OLED refreshes at ~60Hz (controlled by Oled_Display.v). Animations update at 45Hz.

**Q: Why tutorial mode?**
A: Educational research shows interactive learning improves understanding vs passive watching.

---

## 10. CODE METRICS

- **Total Lines:** ~2700 lines across 5 Verilog files
- **State Machine:** 8 states, ~50 transitions
- **Clock Domains:** 3 (100MHz, 6.25MHz, 45Hz)
- **Module Hierarchy:** 4 levels deep
- **Parameterization:** 20+ localparam definitions

---

## 11. TESTING STRATEGY

Key test scenarios you should mention:
1. Mode transitions (educational ↔ tutorial)
2. Button timing (rapid presses, simultaneous)
3. Edge cases (all same numbers, already sorted)
4. Tutorial validation (all wrong, all correct, partial)
5. Animation interruption (mode switch during animation)

---

## FINAL TIPS

1. **Know your trade-offs:**
   - Hardware parallelism vs resource usage
   - ROM speed vs RAM flexibility
   - Clock speed vs power consumption

2. **Explain the "why" not just "what":**
   - Don't just say "this is a 2-stage synchronizer"
   - Say "this prevents metastability in clock domain crossings"

3. **Use diagrams:**
   - Draw FSM state diagram
   - Show box layout on OLED
   - Illustrate merge tree structure

4. **Connect to theory:**
   - Merge sort O(n log n) time complexity
   - Bottom-up vs top-down approaches
   - Digital design principles (setup/hold, metastability)

Good luck with your Q&A! 🎓
