

module sim_pci_bridge
(
    input clk, resetn,

    input IRQ_REQ,

    output IRQ_ACK
);

reg previous_irq_req;
reg[31:0] counter;

assign IRQ_ACK = (counter == 1);

always @(posedge clk) begin
    
    if (counter) counter <= counter - 1;

    if (resetn == 0) 
        previous_irq_req <= 0;
    else if (previous_irq_req != IRQ_REQ) begin
        counter <= 5;
        previous_irq_req <= IRQ_REQ;
    end


end


endmodule
