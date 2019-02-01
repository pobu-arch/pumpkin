module integer_multiplier
#(
    parameter OPERAND_WIDTH_IN_BITS = 64,
    parameter PRODUCT_WIDTH_IN_BITS = OPERAND_WIDTH_IN_BITS * 2
)
(
    input reset_in,
    input clk_in,

    input multiplicand_valid_in,
    input multiplicand_sign_in,
    input [(OPERAND_WIDTH_IN_BITS - 1):0] multiplicand_in,

    input multiplier_valid_in,
    input multiplier_sign_in,
    input [(OPERAND_WIDTH_IN_BITS - 1):0] multiplier_in,

    output reg issue_ack_out,

    output reg product_valid_out,
    output reg product_sign_out,
    output reg [(PRODUCT_WIDTH_IN_BITS- 1):0] product_out,

    input issue_ack_in,

    output reg multiply_exception_out
);

reg has_issued_ack_out;
reg is_running_flag;
reg [31:0] multiplicand_shifted_ctr;

reg multiplicand_sign_reg;
reg multiplier_sign_reg;
reg [(OPERAND_WIDTH_IN_BITS - 1):0] multiplicand_reg;
reg [(OPERAND_WIDTH_IN_BITS - 1):0] multiplier_reg;

wire input_enable;
wire output_enable;

wire multiplicand_reg_least_significant_bit;

assign input_enable =  multiplicand_valid_in & multiplier_valid_in;
assign output_enable = (multiplicand_shifted_ctr == OPERAND_WIDTH_IN_BITS);

assign multiplicand_reg_least_significant_bit = multiplicand_reg[0];

always @ (posedge clk_in)
begin
    if (reset_in)
    begin
        has_issued_ack_out <= 1'b0;
        is_running_flag <= 1'b0;
        issue_ack_out <= 1'b0;

        multiplicand_sign_reg <= 1'b0;
        multiplicand_reg <= {(OPERAND_WIDTH_IN_BITS){1'b0}};

        multiplier_sign_reg <= 1'b0;
        multiplier_reg <= {(OPERAND_WIDTH_IN_BITS){1'b0}};
    end
    else
    begin

        if (issue_ack_out)
        begin
            issue_ack_out <= 1'b0;
        end
        else
        begin
            if (input_enable)
            begin
                if (~is_running_flag)
                begin
                    multiplicand_sign_reg <= multiplier_sign_in;
                    multiplicand_reg <= {{1'b0}, multiplicand_in[(OPERAND_WIDTH_IN_BITS - 1):1]};

                    multiplier_sign_reg <= multiplier_sign_in;
                    multiplier_reg <= multiplier_in;

                    product_out <= (multiplicand_in[0])? (multiplier_in << OPERAND_WIDTH_IN_BITS) : {(PRODUCT_WIDTH_IN_BITS){1'b0}};

                    is_running_flag <= 1'b1;
                end
                else
                begin
                    if (has_issued_ack_out)
                    begin
                        issue_ack_out <= 1'b0;
                    end
                    else
                    begin
                        issue_ack_out <= 1'b1;
                        has_issued_ack_out <= 1'b1;
                    end
                end
            end
        end

        if (product_valid_out & issue_ack_in)
        begin
            has_issued_ack_out <= 1'b0;
            is_running_flag <= 1'b0;

            multiplicand_sign_reg <= 1'b0;
            multiplier_sign_reg <= 1'b0;
            multiplicand_reg <= {(OPERAND_WIDTH_IN_BITS){1'b0}};
            multiplier_reg <= {(OPERAND_WIDTH_IN_BITS){1'b0}};
        end
    end
end

always @ (posedge clk_in)
begin
    if (reset_in)
    begin
        product_valid_out <= 1'b0;
        product_sign_out <= 1'b0;
        product_out <= {(PRODUCT_WIDTH_IN_BITS){1'b0}};
    end
    else
    begin
        if (output_enable)
        begin
            product_valid_out <= 1'b1;
            product_sign_out <= multiplicand_sign_reg ^ multiplier_sign_reg;
        end

        if (product_valid_out & issue_ack_in)
        begin
            product_valid_out <= 1'b0;
            product_sign_out <= 1'b0;
            product_out <= {(PRODUCT_WIDTH_IN_BITS){1'b0}};
        end
    end
end

always @ (posedge clk_in)
begin
    if (reset_in)
    begin
        multiplicand_shifted_ctr <= 32'b0;
    end
    else
    begin
        if (~output_enable & is_running_flag)
        begin
            product_out <= (multiplicand_reg_least_significant_bit)? ((product_out >> 1) + (multiplier_reg << OPERAND_WIDTH_IN_BITS)) : (product_out >> 1);
            //product_out <= multiplicand_reg_least_significant_bit + 1;
            multiplicand_reg <= multiplicand_reg >> 1;
            multiplicand_shifted_ctr <= multiplicand_shifted_ctr + 1'b1;
        end

        if (product_valid_out & issue_ack_in)
        begin
            multiplicand_shifted_ctr <= 1'b0;
        end
    end
end

endmodule