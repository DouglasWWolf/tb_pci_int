

module sim_pci_bridge
(
    input clk, resetn,

    input IRQ_REQ,

    output reg IRQ_ACK
);

reg[2:0] fsm_state;

reg[31:0] counter;

always @(posedge clk) begin
    
    IRQ_ACK <= 0;

    if (counter) counter <= counter - 1;

    if (resetn == 0)
        fsm_state <= 0;
    
    else case(fsm_state)

        0:  if (IRQ_REQ) begin
                counter   <= 5;
                fsm_state <= 1;
            end

        1:  if (counter == 0) begin
                IRQ_ACK   <= 1;
                counter   <= 5;
                fsm_state <= 2;
            end

        2:  if (counter == 0) begin
                IRQ_ACK   <= 1;
                fsm_state <= 0;
            end

    endcase

end


endmodule
