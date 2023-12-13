//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 11-Dec-23  DWW     1  Initial creation
//====================================================================================

/*
     This module strobe an interrupt output every time the programmable timer expires
*/


module timer # (parameter CLK_PER_MSEC=100000)
(
    input clk, resetn,

    output interrupt,

    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[31:0]                             S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[31:0]                             S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================

);  

    //==========================================================================
    // The indicies of the AXI registers
    localparam REG_FORCE = 0;
    localparam REG_TIMER = 1;
    //==========================================================================


    //==========================================================================
    // We'll communicate with the AXI4-Lite Slave core with these signals.
    //==========================================================================
    // AXI Slave Handler Interface for write requests
    wire[31:0]  ashi_waddr;     // Input:  Write-address
    wire[31:0]  ashi_wdata;     // Input:  Write-data
    wire        ashi_write;     // Input:  1 = Handle a write request
    reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
    wire        ashi_widle;     // Output: 1 = Write state machine is idle

    // AXI Slave Handler Interface for read requests
    wire[31:0]  ashi_raddr;     // Input:  Read-address
    wire        ashi_read;      // Input:  1 = Handle a read request
    reg[31:0]   ashi_rdata;     // Output: Read data
    reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
    wire        ashi_ridle;     // Output: 1 = Read state machine is idle
    //==========================================================================

    // The state of the state-machines that handle AXI4-Lite read and AXI4-Lite write
    reg[3:0] axi4_write_state, axi4_read_state;

    // The AXI4 slave state machines are idle when in state 0 and their "start" signals are low
    assign ashi_widle = (ashi_write == 0) && (axi4_write_state == 0);
    assign ashi_ridle = (ashi_read  == 0) && (axi4_read_state  == 0);
   
    // These are the valid values for ashi_rresp and ashi_wresp
    localparam OKAY   = 0;
    localparam SLVERR = 2;
    localparam DECERR = 3;

    // An AXI slave is gauranteed a minimum of 128 bytes of address space
    // (128 bytes is 32 32-bit registers)
    localparam ADDR_MASK = 7'h7F;

    // The bit definitions of pg_control_1 and pg_control_2
    localparam CTL_START  = 0;
    localparam CTL_HALT   = 1;
    localparam CTL_INJECT = 2;

    // This counts down timer ticks
    reg[31:0] clk_counter;

    // This counts down milliseconds
    reg[31:0] ms_counter;

    // This is the user-controlled value of the timer
    reg[31:0] timer_value;

    // The interrupt is forced high any time this counter is non-zero
    reg[31:0] force_counter;

    // The interrupt strobes high on the 2nd to last clk cycle of the counter
    assign interrupt = (force_counter != 0) | ({ms_counter, clk_counter} == 1);


    //==========================================================================
    // This state machine handles AXI4-Lite write requests
    //
    // Drives:
    //==========================================================================
    always @(posedge clk) begin
    
        //---------------------------------------------
        // This block of code manages the counters
        //---------------------------------------------
        if (timer_value) begin
            if (clk_counter)
                clk_counter <= clk_counter - 1;
            else begin
                clk_counter <= CLK_PER_MSEC;
                if (ms_counter)
                    ms_counter <= ms_counter -1;
                else
                    ms_counter <= timer_value;
            end
        end
        //---------------------------------------------

        // The force_counter always counts down to zero
        if (force_counter) force_counter <= force_counter - 1;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            axi4_write_state  <= 0;

        // If we're not in reset, and a write-request has occured...        
        end else case (axi4_write_state)
        
       
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // Convert the byte address into a register index
                case ((ashi_waddr & ADDR_MASK) >> 2)

                    REG_FORCE:
                        begin
                            clk_counter   <= 0;
                            ms_counter    <= 0;
                            timer_value   <= 0;
                            force_counter <= ashi_wdata;
                        end

                    REG_TIMER:
                        
                        // If the user is setting the timer...
                        if (ashi_wdata) begin
                            clk_counter <= CLK_PER_MSEC;
                            ms_counter  <= ashi_wdata;
                            timer_value <= ashi_wdata;
                        end

                        // Otherwise, if the user is cancelling the timer...
                        else begin
                            clk_counter <= 0;
                            ms_counter  <= 0;
                            timer_value <= 0;
                        end

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                
                endcase
            end

        endcase
    end
    //==========================================================================




    //==========================================================================
    // World's simplest state machine for handling AXI4-Lite read requests
    //==========================================================================
    always @(posedge clk) begin

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            axi4_read_state <= 0;
        
        // If we're not in reset, and a read-request has occured...        
        end else if (ashi_read) begin
       
            // Assume for the moment that the result will be OKAY
            ashi_rresp <= OKAY;              
            
            // Convert the byte address into a register index
            case ((ashi_raddr & ADDR_MASK) >> 2)

                // Allow a read from any valid register                
                REG_TIMER:  ashi_rdata <= timer_value;

                // Reads of any other register are a decode-error
                default: ashi_rresp <= DECERR;
            endcase
        end
    end
    //==========================================================================



    //==========================================================================
    // This connects us to an AXI4-Lite slave core
    //==========================================================================
    axi4_lite_slave axi_slave
    (
        .clk            (clk),
        .resetn         (resetn),
        
        // AXI AW channel
        .AXI_AWADDR     (S_AXI_AWADDR),
        .AXI_AWVALID    (S_AXI_AWVALID),   
        .AXI_AWPROT     (S_AXI_AWPROT),
        .AXI_AWREADY    (S_AXI_AWREADY),
        
        // AXI W channel
        .AXI_WDATA      (S_AXI_WDATA),
        .AXI_WVALID     (S_AXI_WVALID),
        .AXI_WSTRB      (S_AXI_WSTRB),
        .AXI_WREADY     (S_AXI_WREADY),

        // AXI B channel
        .AXI_BRESP      (S_AXI_BRESP),
        .AXI_BVALID     (S_AXI_BVALID),
        .AXI_BREADY     (S_AXI_BREADY),

        // AXI AR channel
        .AXI_ARADDR     (S_AXI_ARADDR), 
        .AXI_ARVALID    (S_AXI_ARVALID),
        .AXI_ARPROT     (S_AXI_ARPROT),
        .AXI_ARREADY    (S_AXI_ARREADY),

        // AXI R channel
        .AXI_RDATA      (S_AXI_RDATA),
        .AXI_RVALID     (S_AXI_RVALID),
        .AXI_RRESP      (S_AXI_RRESP),
        .AXI_RREADY     (S_AXI_RREADY),

        // ASHI write-request registers
        .ASHI_WADDR     (ashi_waddr),
        .ASHI_WDATA     (ashi_wdata),
        .ASHI_WRITE     (ashi_write),
        .ASHI_WRESP     (ashi_wresp),
        .ASHI_WIDLE     (ashi_widle),

        // ASHI read registers
        .ASHI_RADDR     (ashi_raddr),
        .ASHI_RDATA     (ashi_rdata),
        .ASHI_READ      (ashi_read ),
        .ASHI_RRESP     (ashi_rresp),
        .ASHI_RIDLE     (ashi_ridle)
    );
    //==========================================================================


endmodule
