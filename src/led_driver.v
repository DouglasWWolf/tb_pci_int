module led_driver
(
    input clk, resetn,

    input interrupt,

    output reg led
);

always @(posedge clk) begin
    if (resetn == 0)
        led <= 0;
    else begin
        if (interrupt) led <= ~led;
    end

end


endmodule


