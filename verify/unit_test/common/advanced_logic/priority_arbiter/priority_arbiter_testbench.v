`include "parameters.vh"

module priority_arbiter_testbench();

parameter NUM_REQUEST  = 3;
parameter SINGLE_REQUEST_WIDTH_IN_BITS = 64;
parameter NUM_SINGLE_REQUEST_TEST = 16;

parameter FIRST_WAY = 1;

reg                                                     clk_in;
reg                                                     reset_in;

reg     [SINGLE_REQUEST_WIDTH_IN_BITS - 1 : 0]          packed_request_to_arb   [(NUM_REQUEST - 1):0];
reg     [(NUM_REQUEST - 1):0]                           packed_request_valid_to_arb;
reg     [(NUM_REQUEST - 1):0]                           packed_request_critical_to_arb;
wire    [(NUM_REQUEST - 1):0]                           packed_issue_ack_from_arb;


wire    [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          request_from_arb;
wire                                                    request_valid_from_arb;
reg                                                     issue_ack_to_arb;

reg                                                     ack_to_arb_mode;
integer                                                 test_case;
integer                                                 index;
integer                                                 check_index;
integer                                                 read_delay;

reg                                                     test_judge;
reg     [31:0]                                          read_nop_ctr;

reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          request_to_arb_buffer   [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0];
reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          request_from_arb_buffer [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0];
reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          passed_request_buffer   [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0];

reg     [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0] request_critical_to_arb_array;
reg     [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0] request_valid_to_arb_array;
reg     [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0] check_request_judge_array;

reg     [31:0]                                          check_ctr;
reg     [31:0]                                          check_way_now;
reg     [31:0]                                          check_way_pointer_array [(NUM_REQUEST - 1):0];

reg     [31:0]                                          request_from_arb_buffer_pointer;
reg     [31:0]                                          passed_request_buffer_pointer;
reg     [31:0]                                          sim_write_pointer_array [(NUM_REQUEST - 1):0];
reg     [31:0]                                          end_read_boundary;

wire    [(NUM_REQUEST - 1):0]                           packed_end_write_flag;
wire                                                    end_read_flag;
wire                                                    end_check_flag;
reg                                                     ready_to_write_flag;

assign end_read_flag = (request_from_arb_buffer_pointer == end_read_boundary);
assign end_check_flag = (check_ctr == NUM_SINGLE_REQUEST_TEST * NUM_REQUEST);

//write
generate
genvar gen;
    for (gen = 0; gen < NUM_REQUEST; gen = gen + 1)
    begin

        reg [31:0]  request_to_arb_buffer_pointer;

        wire        end_write_flag;
        wire        issue_ack_from_arb;

        assign packed_end_write_flag[gen]                   = end_write_flag;
        assign end_write_flag                               = (request_to_arb_buffer_pointer == (gen + 1) * NUM_SINGLE_REQUEST_TEST + 1'b1);
        assign issue_ack_from_arb                           = packed_issue_ack_from_arb[gen];

        always @(posedge clk_in)
        begin
            if (reset_in)
            begin
                packed_request_valid_to_arb[gen]            <= 0;
                packed_request_to_arb[gen]                  <= 0;
                packed_request_critical_to_arb[gen]         <= 0;

                request_to_arb_buffer_pointer               <= 0;
                
                ready_to_write_flag                         <= 1;
            end
            else
            begin
                if (ready_to_write_flag)
                begin
                    packed_request_valid_to_arb[gen]            <= 1'b1;
                    packed_request_to_arb[gen]                  <= request_to_arb_buffer[gen * NUM_SINGLE_REQUEST_TEST];
                    packed_request_critical_to_arb[gen]         <= request_critical_to_arb_array[gen * NUM_SINGLE_REQUEST_TEST];
    
                    request_to_arb_buffer_pointer               <= gen * NUM_SINGLE_REQUEST_TEST + 1'b1;             
                    
                    ready_to_write_flag                         <= 0;   
                end
            
                else if (~end_write_flag)
                begin
                    if (request_to_arb_buffer_pointer == gen * NUM_SINGLE_REQUEST_TEST + 1'b1)
                    begin
                        packed_request_valid_to_arb[gen]    <= request_valid_to_arb_array[gen * NUM_SINGLE_REQUEST_TEST];
                    end

                    if (issue_ack_from_arb)
                    begin
                        if (request_to_arb_buffer_pointer < (gen + 1) * NUM_SINGLE_REQUEST_TEST)
                        begin
                            packed_request_valid_to_arb[gen]    <= request_valid_to_arb_array[request_to_arb_buffer_pointer];
                            packed_request_to_arb[gen]          <= request_to_arb_buffer[request_to_arb_buffer_pointer];
                            packed_request_critical_to_arb[gen] <= request_critical_to_arb_array[request_to_arb_buffer_pointer];
                        end
                        else
                        begin
                            packed_request_valid_to_arb[gen]        <= 1'b0;
                            packed_request_to_arb[gen]              <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
                            packed_request_critical_to_arb[gen]     <= 1'b0;
                        end

                        request_to_arb_buffer_pointer       <= request_to_arb_buffer_pointer + 1'b1;
                    end
                end
            end
        end


    end
endgenerate


//read
always @(posedge clk_in)
begin
    if (reset_in)
    begin
        read_nop_ctr                                        <= 1;
        request_from_arb_buffer_pointer                     <= 0;
        issue_ack_to_arb                                    <= 0;
    end
    else
    begin
        //delay 1 cycle
        if (issue_ack_to_arb && (ack_to_arb_mode == 0))
        begin
            issue_ack_to_arb                                <= 1'b0;
        end
        else
        begin
            if (~end_read_flag)
            begin
                if (request_valid_from_arb)
                begin
                    read_nop_ctr <= read_nop_ctr + 1'b1;
                    if ((read_nop_ctr % read_delay) == 0)
                    begin
                        if (ack_to_arb_mode == 1)
                        begin
                            if (issue_ack_to_arb)
                            begin
                                request_from_arb_buffer[request_from_arb_buffer_pointer] <= request_from_arb; 
                                request_from_arb_buffer_pointer                          <= request_from_arb_buffer_pointer + 1'b1;                                                           
                            end
                        end
                        
                        else
                        begin
                            request_from_arb_buffer[request_from_arb_buffer_pointer] <= request_from_arb;
                            request_from_arb_buffer_pointer                          <= request_from_arb_buffer_pointer + 1'b1;                        
                        end

                        issue_ack_to_arb                                         <= 1'b1;
                    end
                end
                else
                begin
                    request_from_arb_buffer[request_from_arb_buffer_pointer] <= request_from_arb_buffer[request_from_arb_buffer_pointer];
                    issue_ack_to_arb                                         <= issue_ack_to_arb;

                    request_from_arb_buffer_pointer                          <= request_from_arb_buffer_pointer;
                end
            end
        end
    end
end


always @ (posedge clk_in) begin
    if (reset_in)
    begin
        check_ctr <= 32'b0;
        check_way_now <= FIRST_WAY;
        for (check_index = 0; check_index < NUM_REQUEST; check_index = check_index + 1'b1)
        begin
            check_way_pointer_array[check_index] <= check_index * NUM_SINGLE_REQUEST_TEST;
        end
    end
    else
    begin
        if (~end_check_flag & end_read_flag & (&(packed_end_write_flag)))
        begin
            check_ctr <= check_ctr + 1'b1;
            for (check_index = 0; check_index < NUM_REQUEST; check_index = check_index + 1'b1)
            begin:CHECK
                if (request_from_arb_buffer[check_ctr] == request_to_arb_buffer[check_way_pointer_array[(check_way_now + check_index) % NUM_REQUEST]])
                begin
                    check_way_now <= (check_way_now + check_index) % NUM_REQUEST;
                    check_way_pointer_array[(check_way_now + check_index) % NUM_REQUEST] <= check_way_pointer_array[(check_way_now + check_index) % NUM_REQUEST] + 1'b1;
                    check_request_judge_array[check_ctr] <= 1'b1;
                    disable CHECK;
                end
            end
        end
    end
end

always @(posedge clk_in)
begin
    if (reset_in)
    begin
        test_judge                                                          <= 1'b0;
    end
    else if (end_read_flag & (&(packed_end_write_flag)) & end_check_flag)
    begin
        if (&(check_request_judge_array) == 1'b1)
        begin
            test_judge                                                      <= 1'b1;
        end
        else
        begin
            test_judge                                                      <= 1'b0;
        end
    end
end

initial
begin

    `ifdef DUMP
        $dumpfile(`DUMP_FILENAME);
        $dumpvars(0, priority_arbiter_testbench);
    `endif

    $display("\n[info-testbench] simulation for %m begins now");
    clk_in                                      <= 1'b0;
    ack_to_arb_mode                             <= 1'b0;

    /*test case 1 */
    test_case                                   <= 0;
    reset_in                                    <= 1'b1;
    read_delay                                  <= 1;

    $display("[info-testbench] %m testbench reset completed");

    //init
    end_read_boundary                           <= NUM_SINGLE_REQUEST_TEST * NUM_REQUEST;
    passed_request_buffer_pointer               <= {(32){1'b0}};
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        request_to_arb_buffer[index]            <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b1}} - index;
        request_from_arb_buffer[index]          <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
        request_valid_to_arb_array[index]       <= 1'b1;

        if (index < NUM_SINGLE_REQUEST_TEST)
        begin
            request_critical_to_arb_array[index]    <= 1'b1;
        end
        else
        begin
            request_critical_to_arb_array[index]    <= 1'b0;
        end
        
        check_request_judge_array[index]        <= 1'b0;

    end

    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
        sim_write_pointer_array[index]          <= index * NUM_SINGLE_REQUEST_TEST;
    end

    //Conditions of passage
    #(`FULL_CYCLE_DELAY * 2)

    //Critical request
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
         passed_request_buffer[index]                                               <= request_to_arb_buffer[index];
    end

    for (index = NUM_SINGLE_REQUEST_TEST; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        #(`FULL_CYCLE_DELAY) passed_request_buffer[index]                           <= request_to_arb_buffer[sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]];
        sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]    <= sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)] + 1'b1;
    end

    #(`FULL_CYCLE_DELAY * 10.5)   reset_in        <= 1'b0;

    #(`FULL_CYCLE_DELAY * 1000)  $display("[info-testbench] test case %2d %80s : \t%s (delay %2d cycle)", test_case, "basic request", test_judge? "passed": "failed", read_delay);

    /*test case 2 */
    test_case                                   <= test_case + 1'b1;
    reset_in                                    <= 1'b1;
    read_delay                                  <= 20;

    //init
    end_read_boundary                           <= NUM_SINGLE_REQUEST_TEST * NUM_REQUEST;
    passed_request_buffer_pointer               <= {(32){1'b0}};
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        request_to_arb_buffer[index]            <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b1}} - index;
        request_from_arb_buffer[index]          <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
        request_valid_to_arb_array[index]       <= 1'b1;

        if (index < NUM_SINGLE_REQUEST_TEST)
        begin
            request_critical_to_arb_array[index]    <= 1'b1;
        end
        else
        begin
            request_critical_to_arb_array[index]    <= 1'b0;
        end
        
        check_request_judge_array[index]        <= 1'b0;
    end

    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
        sim_write_pointer_array[index]          <= index * NUM_SINGLE_REQUEST_TEST;
    end

    //Conditions of passage
    #(`FULL_CYCLE_DELAY * 2)

    //Critical request
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
         passed_request_buffer[index]                                               <= request_to_arb_buffer[index];
    end

    for (index = NUM_SINGLE_REQUEST_TEST; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        #(`FULL_CYCLE_DELAY) passed_request_buffer[index]                           <= request_to_arb_buffer[sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]];
        sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]    <= sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)] + 1'b1;
    end

    #(`FULL_CYCLE_DELAY * 10)   reset_in        <= 1'b0;

    #(`FULL_CYCLE_DELAY * 1500)  $display("[info-testbench] test case %2d %80s : \t%s (delay %2d cycle)", test_case, "basic request", test_judge? "passed": "failed", read_delay);


    /*test case 3 */
    test_case                                   <= test_case + 1'b1;
    ack_to_arb_mode                             <= 1;
    
    reset_in                                    <= 1'b1;
    read_delay                                  <= 1;

    //init
    end_read_boundary                           <= NUM_SINGLE_REQUEST_TEST * NUM_REQUEST;
    passed_request_buffer_pointer               <= {(32){1'b0}};
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        request_to_arb_buffer[index]            <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b1}} - index;
        request_from_arb_buffer[index]          <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
        request_valid_to_arb_array[index]       <= 1'b1;

        if (index < NUM_SINGLE_REQUEST_TEST)
        begin
            request_critical_to_arb_array[index]    <= 1'b1;
        end
        else
        begin
            request_critical_to_arb_array[index]    <= 1'b0;
        end
        
        check_request_judge_array[index]        <= 1'b0;
    end

    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
        sim_write_pointer_array[index]          <= index * NUM_SINGLE_REQUEST_TEST;
    end

    //Conditions of passage
    #(`FULL_CYCLE_DELAY * 2)

    //Critical request
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
         passed_request_buffer[index]                                               <= request_to_arb_buffer[index];
    end

    for (index = NUM_SINGLE_REQUEST_TEST; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        #(`FULL_CYCLE_DELAY) passed_request_buffer[index]                           <= request_to_arb_buffer[sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]];
        sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)]    <= sim_write_pointer_array[1 + (FIRST_WAY - 1 + index) % (NUM_REQUEST - 1)] + 1'b1;
    end

    #(`FULL_CYCLE_DELAY * 10)   reset_in        <= 1'b0;

    #(`FULL_CYCLE_DELAY * 1500)  $display("[info-testbench] test case %2d %80s : \t%s (with early ack)", test_case, "basic request", test_judge? "passed": "failed");

    #(`FULL_CYCLE_DELAY * 10)   $display("[info-testbench] simulation comes to the end\n");
    $finish;
end

always begin #(`HALF_CYCLE_DELAY) clk_in <= ~clk_in; end

priority_arbiter
#(
    .NUM_REQUEST                                    (NUM_REQUEST),
    .SINGLE_REQUEST_WIDTH_IN_BITS                   (SINGLE_REQUEST_WIDTH_IN_BITS)
 )

priority_arbiter
(
    .reset_in                                       (reset_in),
    .clk_in                                         (clk_in),

    // the arbiter considers priority from right(high) to left(low)
    .request_flatted_in                             ({packed_request_to_arb[2],             packed_request_to_arb[1],           packed_request_to_arb[0]}),
    .request_valid_flatted_in                       ({packed_request_valid_to_arb[2],       packed_request_valid_to_arb[1],     packed_request_valid_to_arb[0]}),
    .request_critical_flatted_in                    ({packed_request_critical_to_arb[2],    packed_request_critical_to_arb[1],  packed_request_critical_to_arb[0]}),
    .issue_ack_out                                  ({packed_issue_ack_from_arb[2],         packed_issue_ack_from_arb[1],       packed_issue_ack_from_arb[0]}),

    .request_out                                    (request_from_arb),
    .request_valid_out                              (request_valid_from_arb),
    .issue_ack_in                                   (issue_ack_to_arb)
);

endmodule
