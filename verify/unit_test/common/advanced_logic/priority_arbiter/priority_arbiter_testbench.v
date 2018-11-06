`include "parameters.h"

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

integer                                                 test_case;
integer                                                 index;

reg                                                     test_judge;                                      

reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          request_to_arb_buffer   [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0];
reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          request_from_arb_buffer [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0];
reg     [(SINGLE_REQUEST_WIDTH_IN_BITS - 1):0]          passed_request_buffer   [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0]; 
 
reg     [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0] request_critical_to_arb_array; 
reg     [(NUM_SINGLE_REQUEST_TEST * NUM_REQUEST - 1):0] check_request_judge_array;

reg     [31:0]                                          request_from_arb_buffer_pointer; 
reg     [31:0]                                          passed_request_buffer_pointer;
reg     [31:0]                                          sim_write_pointer_array [(NUM_REQUEST - 1):0];

wire    [(NUM_REQUEST - 1):0]                           packed_end_write_flag;
wire                                                    end_read_flag;

assign end_read_flag = (request_from_arb_buffer_pointer == NUM_SINGLE_REQUEST_TEST * NUM_REQUEST);

//write
generate
genvar gen;
    for (gen = 0; gen < NUM_REQUEST; gen = gen + 1)
    begin
        parameter   START_POSITION_IN_BUFFER                = gen * NUM_SINGLE_REQUEST_TEST;
        parameter   END_POSITION_IN_BUFFER                  = (gen + 1) * NUM_SINGLE_REQUEST_TEST - 1;   
        
        reg [31:0]  request_to_arb_buffer_pointer;
        
        wire        end_write_flag;
        wire        issue_ack_from_arb;
        
        assign packed_end_write_flag[gen]                   = end_write_flag;
        assign end_write_flag                               = (request_to_arb_buffer_pointer == END_POSITION_IN_BUFFER + 2);
        assign issue_ack_from_arb                           = packed_issue_ack_from_arb[gen];
        
        always @(posedge clk_in)
        begin
            if (reset_in)
            begin
                packed_request_valid_to_arb[gen]            <= 1'b0;            
                packed_request_to_arb[gen]                  <= request_to_arb_buffer[START_POSITION_IN_BUFFER];
                packed_request_critical_to_arb[gen]         <= request_critical_to_arb_array[START_POSITION_IN_BUFFER];
                
                request_to_arb_buffer_pointer               <= START_POSITION_IN_BUFFER + 1'b1;
                
            end
            else
            begin
                if (~end_write_flag)
                begin
                    packed_request_valid_to_arb[gen]        <= 1'b1;
                    
                    if (issue_ack_from_arb)
                    begin
                        packed_request_to_arb[gen]          <= request_to_arb_buffer[request_to_arb_buffer_pointer];
                        packed_request_critical_to_arb[gen] <= request_critical_to_arb_array[request_to_arb_buffer_pointer];
                        request_to_arb_buffer_pointer       <= request_to_arb_buffer_pointer + 1'b1; 
                    end
                end
                
                //finish writing
                else
                begin
                    packed_request_valid_to_arb[gen]        <= 1'b0;
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
        request_from_arb_buffer_pointer                     <= 0;
        issue_ack_to_arb                                    <= 0;
    end
    else
    begin
        //delay 1 cycle
        if (issue_ack_to_arb)
        begin
            issue_ack_to_arb                                <= 1'b0;
        end
        else
        begin
            if (~end_read_flag)
            begin
                if (request_valid_from_arb)
                begin
                    request_from_arb_buffer[request_from_arb_buffer_pointer] <= request_from_arb;
                    issue_ack_to_arb                                         <= 1'b1;
                    
                    request_from_arb_buffer_pointer                          <= request_from_arb_buffer_pointer + 1'b1;
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

//check
generate
    for (gen = 0; gen < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; gen = gen + 1)
    begin
        always @(posedge clk_in)
        begin
            if (reset_in)
            begin
                check_request_judge_array[gen]                              <= 1'b0; 
            end
            else if (end_read_flag & (&(packed_end_write_flag)))
            begin
                check_request_judge_array[gen]                              <= (request_from_arb_buffer[gen] == passed_request_buffer[gen]);
            end
            else
            begin
                check_request_judge_array[gen]                              <= check_request_judge_array[gen];
            end
        end
    end
endgenerate

always @(posedge clk_in)
begin
    if (reset_in)
    begin
        test_judge                                                          <= 1'b0;
    end
    else if (end_read_flag & (&(packed_end_write_flag)))
    begin
        if (&(check_request_judge_array) == 1'b1)
        begin
            test_judge                                                  <= 1'b1;
        end
        else
        begin
            test_judge                                                  <= 1'b0;
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
    reset_in                                    <= 1'b1;
    
    //init
    passed_request_buffer_pointer               <= {(32){1'b0}};
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        request_to_arb_buffer[index]            <= index;
        request_critical_to_arb_array[index]    <= 1'b0;
        request_from_arb_buffer[index]          <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
    end
    
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST; index = index + 1)
    begin
        sim_write_pointer_array[index]          <= index * NUM_SINGLE_REQUEST_TEST;
    end
    
    for (index = 0; index < NUM_SINGLE_REQUEST_TEST * NUM_REQUEST; index = index + 1)
    begin
        passed_request_buffer[index]            <= request_to_arb_buffer[sim_write_pointer_array[(FIRST_WAY + index) % NUM_REQUEST]];
        sim_write_pointer_array[(FIRST_WAY + index) % NUM_REQUEST] <= sim_write_pointer_array[(FIRST_WAY + index) % NUM_REQUEST] + 1'b1;
    end
    
    test_case                                   <= 1'b0;
    #(`FULL_CYCLE_DELAY * 10)   reset_in        <= 1'b0;

    #(`FULL_CYCLE_DELAY * 200)  $display("[info-rtl] test case %d %35s : \t%s", test_case, "normal request", test_judge? "passed": "failed");
    
    #(`FULL_CYCLE_DELAY * 10) $display("\n[info-rtl] simulation comes to the end\n");
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
