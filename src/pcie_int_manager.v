`timescale 1ns / 1ps

//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 06-Sep-22  DWW  1000  Initial creation
//====================================================================================

/*

Usage:

   This module is an AXI4-Lite slave that allows an application to generate or clear
   PCIe interrupts using the legacy interrupt mechanism.

   We support up to 32 interrupt sources, number 0 thru 31

   To use:

   <<<<<<<<<<<<<<<<<<  FILL THIS IN !!!!!!!!!!!!!!!!! >>>>>>>>>>>>>>>>>>>>
*/


module pcie_int_manager#(parameter IRQ_COUNT=1)
(
    // Clock and reset
    input clk, resetn,

    output[IRQ_COUNT-1:0] dbg_pending_irq,
    output[31:0] dbg_counter0,
    output dbg_newly_pending,
    output dbg_make_irq_req,

    // We raise this line to ask the PCIe bridge to generate an interrupt
    output reg IRQ_REQ,
    
    // This line goes high when the PCIe bridge acknowledges our request
    input  IRQ_ACK,

    // Strobing any of these lines high marks that interrupt source as requested
    input[IRQ_COUNT-1:0] IRQ_IN,

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

    integer i;

    //==========================================================================
    // We'll communicate with the AXI4-Lite Slave core with these signals.
    //==========================================================================
    // AXI Slave Handler Interface for write requests
    wire[31:0]  ashi_waddr;     // Input:  Write-address
    wire[31:0]  ashi_windx;     // Input:  Register index
    wire[31:0]  ashi_wdata;     // Input:  Write-data
    wire        ashi_write;     // Input:  1 = Handle a write request
    reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
    wire        ashi_widle;     // Output: 1 = Write state machine is idle

    // AXI Slave Handler Interface for read requests
    wire[31:0]  ashi_raddr;     // Input:  Read-address
    wire[31:0]  ashi_rindx;     // Input:  Register index
    wire        ashi_read;      // Input:  1 = Handle a read request
    reg[31:0]   ashi_rdata;     // Output: Read data
    reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
    wire        ashi_ridle;     // Output: 1 = Read state machine is idle
    //==========================================================================

    //====================================================
    // The names of our registers
    //====================================================
    localparam REG_IRQ_PENDING        =  0;
    localparam REG_IRQ_ACK            =  1;
    localparam REG_IRQ_MASK           =  2;
    localparam REG_GLOB_ENABLE        =  3;
    localparam REG_COUNTERS           = 32;
    localparam REG_LAST_VALID_COUNTER = REG_COUNTERS + IRQ_COUNT - 1;
    localparam REG_LAST_COUNTER       = REG_COUNTERS + 31;

    // The state of our AXI-register read/write state machines
    reg[2:0] read_state, write_state;

    // The state machines are idle when they're in state 0 and their "start" signals are low
    assign ashi_widle = (ashi_write == 0) && (write_state == 0);
    assign ashi_ridle = (ashi_read  == 0) && (read_state  == 0);

    // These are the valid values for ashi_rresp and ashi_wresp
    localparam OKAY   = 0;
    localparam SLVERR = 2;
    localparam DECERR = 3;

    // This module requires 256 bytes of address space 
    localparam ADDR_MASK = 8'hFF;

    // Counts the number of interrupts for each IRQ
    reg[31:0] irq_counter[0:IRQ_COUNT-1];
    
    // When a bit in the irq_mask is zero, that interrupt can never become pending
    reg[IRQ_COUNT-1:0] irq_mask;

    // This is a "global enable/disable" for interrupts
    reg global_irq_enable;

    // An interrupt is pending any time the following things are all true:
    //   (1) Its counter is non-zero
    //   (2) Its bit in irq_mask is 1
    //   (3) global_irq_enable is 1
    wire[IRQ_COUNT-1:0] pending_irq;
    genvar k;
    for (k=0; k<IRQ_COUNT; k=k+1) begin
        assign pending_irq[k] = (irq_counter[k] != 0) & irq_mask[k] & global_irq_enable;
    end

    // These bits are similar to IRQ_IN, but are set via AXI register
    reg[IRQ_COUNT-1:0] axi_irq_in;

    // This is a bitmap of which IRQ lines are high, regardless of source
    wire[IRQ_COUNT-1:0] irq_in = IRQ_IN | axi_irq_in;

    // The state of the "interrupt state machine"
    reg[1:0] ism_state;

    // "Clear IRQ", set by writing to a register
    reg[IRQ_COUNT-1:0] wclear_irq;
    
    // "Clear IRQ" set by reading from a register
    reg[IRQ_COUNT-1:0] rclear_irq;
    
    // A 1 bit means "clear the counter associated with this IRQ"
    wire[IRQ_COUNT-1:0] clear_irq = wclear_irq | rclear_irq;

    //==========================================================================
    // This block counts the number of times each interrupt has occured
    //
    // The count can be cleared by strobing high the appropriate bit in
    // "clear_irq"
    //
    // It's important to the design of this interrupt controller that we never
    // miss an interrupt when we're counting them.
    //==========================================================================
    always @(posedge clk) begin
        for (i=0; i<IRQ_COUNT; i=i+1) begin
            if (resetn == 0)
                irq_counter[i] <= 0;
            else if (clear_irq[i])
                irq_counter[i] <= irq_in[i];
            else
                irq_counter[i] <= irq_counter[i] + irq_in[i];
        end
    end
    //==========================================================================


    //==========================================================================
    // This state machine manages IRQ_REQ/IRQ_ACK interaction.
    //
    // As per the Xilinx PG194 documentation, the state of IRQ_REQ is not 
    // allowed to change while we are waiting for a pending IRQ_ACK that
    // acknowledges the prior IRQ_REQ state change.  Every change of state
    // on IRQ_REQ requires us to wait for a corresponding IRQ_ACK before
    // changing the state of IRQ_REQ again.
    //--------------------------------------------------------------------------
    
    // Which interrupts were pending during the previous clock cycle?
    reg[IRQ_COUNT-1:0] prior_pending;
    
    // This is high when there are newly pending interrupts on this clock cycle
    wire newly_pending = ((pending_irq & ~prior_pending) != 0);
    
    // This will be high if we need to generate an IRQ REQ to the PCI bridge
    reg  make_irq_req;

    //==========================================================================    
    always @(posedge clk) begin

        // If there are new pending interrupts, we need to 
        // generate an IRQ_REQ
        if (newly_pending) make_irq_req <= 1;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            ism_state     <= 0;
            IRQ_REQ       <= 0;
            prior_pending <= 0;
            make_irq_req  <= 0;
        
        // Otherwise, if we're not in reset...
        end else case (ism_state)

            // If there are pending interrupts the host hasn't been notified about...
            0:  if (newly_pending | make_irq_req) begin
                    make_irq_req <= 0;
                    IRQ_REQ      <= 1;
                    ism_state    <= 1;
                end

            // When we receive the first IRQ_ACK, lower IRQ_REQ
            1:  if (IRQ_ACK) begin
                    IRQ_REQ   <= 0;
                    ism_state <= 2;
                end

            // After we see the 2nd IRQ_ACK, it's safe to assert
            // IRQ_REQ again
            2:  if (IRQ_ACK) ism_state <= 0;

        endcase

        // In the next cycle, "prior_pending" is whatever "pending_irq"
        // was on this clock-cycle, but with the bits for the recently
        // clear IRQs turned off.
        prior_pending <= pending_irq & ~clear_irq;
    end
    //==========================================================================




    //==========================================================================
    // This state machine handles AXI write-requests
    //==========================================================================
    always @(posedge clk) begin

        // These bits will strobe high when set via AXI command
        axi_irq_in <= 0;
        wclear_irq <= 0;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            write_state <= 0;
        
        // If we're not in reset...
        end else begin

            // If a write-request has come in...
            if (ashi_write) begin

                // Assume for a moment that we will be reporting "OKAY" as a write-response
                ashi_wresp <= OKAY;

                case(ashi_windx)

                    // Is the user trying to manually generate an interrupt?
                    REG_IRQ_PENDING:    axi_irq_in <= ashi_wdata;

                    // Is the user acknowledging one or more pending interrupts?
                    REG_IRQ_ACK:        wclear_irq <= ashi_wdata;

                    // Is the user masking-out/masking-in one or more IRQs?
                    REG_IRQ_MASK:       irq_mask <= ashi_wdata;

                    // Is the user enabling/disabling interrupts globally?
                    REG_GLOB_ENABLE:    global_irq_enable <= ashi_wdata;

                    // A write to any other address is a slave-error
                    default: ashi_wresp <= SLVERR;

                endcase
            end

        end
    end
    //==========================================================================


 
    //==========================================================================
    // World's simplest state machine for handling read requests
    //==========================================================================

    // This maps a counter register index to its IRQ number
    wire[7:0] irq = ashi_rindx - REG_COUNTERS;
        
    always @(posedge clk) begin

        // These strobe high for only 1 cycle
        rclear_irq <= 0;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            read_state <= 0;
        
        // If we're not in reset, and a read-request has occured...        
        end else if (ashi_read) begin

            // Assume for a moment that the user is trying to read a valid register
            ashi_rresp <= OKAY;

            // Examine the register index to decide what to do
            case(ashi_rindx)

                REG_IRQ_PENDING:    ashi_rdata <= pending_irq;
                REG_IRQ_ACK:        ashi_rdata <= pending_irq;
                REG_IRQ_MASK:       ashi_rdata <= irq_mask;
                REG_GLOB_ENABLE:    ashi_rdata <= global_irq_enable;

                default:

                    // If we're reading one of the interrupt counters...
                    if (ashi_rindx >= REG_COUNTERS && ashi_rindx <= REG_LAST_VALID_COUNTER) begin
                        ashi_rdata      <= irq_counter[irq] + irq_in[irq];
                        rclear_irq[irq] <= 1;
                    end

                    // Otherwise, it's an error
                    else begin
                        ashi_rresp <= SLVERR;
                        ashi_rdata <= 0;
                        read_state <= 0;
                    end

            endcase

        end
    end
    //==========================================================================





    //==========================================================================
    // This connects us to an AXI4-Lite slave core
    //==========================================================================
    axi4_lite_slave#(ADDR_MASK) axi_slave
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
        .ASHI_WINDX     (ashi_windx),
        .ASHI_WDATA     (ashi_wdata),
        .ASHI_WRITE     (ashi_write),
        .ASHI_WRESP     (ashi_wresp),
        .ASHI_WIDLE     (ashi_widle),

        // ASHI-read-request registers
        .ASHI_RADDR     (ashi_raddr),
        .ASHI_RINDX     (ashi_rindx),
        .ASHI_RDATA     (ashi_rdata),
        .ASHI_READ      (ashi_read ),
        .ASHI_RRESP     (ashi_rresp),
        .ASHI_RIDLE     (ashi_ridle)
    );
    //==========================================================================

assign dbg_pending_irq = pending_irq;
assign dbg_counter0 = irq_counter[0];
assign dbg_newly_pending = newly_pending;
assign dbg_make_irq_req  = make_irq_req;
endmodule



