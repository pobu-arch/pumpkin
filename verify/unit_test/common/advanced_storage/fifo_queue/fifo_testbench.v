`include "parameters.vh"

module fifo_queue_testbench();

parameter SINGLE_ENTRY_WIDTH_IN_BITS = 64;
parameter QUEUE_SIZE = 4;
parameter QUEUE_PTR_WIDTH_IN_BITS = 2;
parameter STORAGE_TYPE = "LUTRAM";

integer i;


reg                                                     clk_in;
reg                                                     reset_in;
reg     [31:0]                                          clk_ctr;

reg                                                     ack_to_fifo_mode;
reg                                                     jump_mode;

integer                                    	            test_case;
reg     [31:0]                                          test_ctr;
integer                                                 test_gen;

reg                                                     test_judge;

reg     [SINGLE_ENTRY_WIDTH_IN_BITS - 1:0]              request_in_buffer[QUEUE_SIZE * 2 - 1 :0];
reg     [QUEUE_SIZE * 2 : 0]                            request_valid_in_buffer;

reg     [SINGLE_ENTRY_WIDTH_IN_BITS - 1:0]              request_out_buffer[QUEUE_SIZE * 2 - 1 : 0];
reg     [SINGLE_ENTRY_WIDTH_IN_BITS - 1:0]              correct_result_buffer[QUEUE_SIZE * 2 - 1 : 0];

reg     [31:0]                                          request_in_ctr;
reg     [31:0]                                          request_in_ctr_boundary;
reg     [31:0]                                          request_out_ctr;
reg     [31:0]                                          result_ctr;
reg     [31:0]                                          result_ctr_boundary;

reg     [31:0]                                          request_out_clk_ctr;

reg                                                     is_from_request_in_buffer;

reg                                                     request_in_enable;
reg                                                     request_out_enable;   
reg                                                     check_enable; 

wire                                                    is_empty;
wire		                                            is_full;

wire     [SINGLE_ENTRY_WIDTH_IN_BITS - 1:0]             request_in;
wire                                                    request_valid_in;
wire                                                    issue_ack_from_fifo;
wire    [SINGLE_ENTRY_WIDTH_IN_BITS - 1:0]              request_out;
wire                                                    request_valid_out;

reg     	                                            issue_ack_to_fifo;

reg                                                     is_ready_to_write;

reg                                                     jump_to_read_data;
reg                                                     jump_to_check_data;

assign request_in                                       = is_from_request_in_buffer? request_in_buffer[request_in_ctr] : {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}};
assign request_valid_in                                 = is_from_request_in_buffer? request_valid_in_buffer[request_in_ctr] : 1'b0;

// write data
always@(posedge clk_in)
begin
    if (reset_in)
    begin
        request_in_ctr                                  <= 0;
        is_from_request_in_buffer                       <= 0;
        request_in_enable                               <= 0;
                
        is_ready_to_write                               <= 0;
        jump_to_read_data                               <= 0;
    end
    else if (request_in_enable)
    begin
    
        if (issue_ack_from_fifo)
        begin

            is_from_request_in_buffer                   <= 1;
            request_in_ctr                              <= request_in_ctr + 1;

            // stop writing
            if (request_in_ctr == request_in_ctr_boundary - 1)
            begin
                request_in_enable                       <= 0; 
                is_from_request_in_buffer               <= 0;      
            end

        end
        
    end
    
    //init
    if (is_ready_to_write)
    begin
        is_ready_to_write                               <= 0;
        request_in_enable                               <= 1;
        is_from_request_in_buffer                       <= 1;
        
    end
    
    // jump to read data
    if (jump_to_read_data & (jump_mode == 0))
    begin
        request_in_enable                               <= 0;
        jump_to_read_data                               <= 0;
        
        is_from_request_in_buffer                       <= 0;
    end
end

// read data
always@(posedge clk_in)
begin
    if (reset_in)
    begin
        request_out_enable                              <= 0;
        request_out_ctr                                 <= 0;
        issue_ack_to_fifo                               <= 0;
        
        request_out_clk_ctr                             <= 0;
        jump_to_check_data                              <= 0;
    end
    
    else if (jump_to_read_data & (jump_mode == 0))
    begin
        request_out_enable                              <= 1;    
    end
    
    else if (request_out_enable)
    begin
        
        if (ack_to_fifo_mode == 0)
        begin
            if (issue_ack_to_fifo)
            begin
                issue_ack_to_fifo                           <= 0;
            end
            else
            begin
                if (request_valid_out)
                begin
                    issue_ack_to_fifo                       <= 1;
                    
                    request_out_buffer[request_out_ctr]     <= request_out;
                    request_out_ctr                         <= request_out_ctr + 1;
                end
            end
            
            // stop reading
            if (request_out_ctr == result_ctr_boundary)
            begin
                request_out_enable                          <= 0;        
            end
        end

        else if (ack_to_fifo_mode == 1)
        begin
            // stop reading
            if (request_out_ctr == result_ctr_boundary)
            begin
                request_out_enable                          <= 0;        
            end
            
            else
            begin
                if (request_valid_out & issue_ack_to_fifo)
                begin
                    request_out_buffer[request_out_ctr]         <= request_out;
                    request_out_ctr                             <= request_out_ctr + 1;
                end   
            end
            
            issue_ack_to_fifo                                   <= 1;
        end
    end
    
    // jump to check data
    if (jump_to_check_data)
    begin
        if (jump_mode == 0)
        begin
            request_out_enable                              <= 0;
        end
        
        else if (jump_mode == 1)
        begin
            request_out_enable                              <= 0;
        end
    end
end

// check data
always@(posedge clk_in)
begin
    if (reset_in)
    begin
        result_ctr                                      <= 0;
        test_judge                                      <= 0;
        check_enable                                    <= 0;
    end
    
    else if (jump_to_check_data)
    begin
        if (jump_mode == 0)
        begin
            test_judge                                  <= 1;
            check_enable                                <= 1; 
            jump_to_check_data                          <= 0;            
        end
        
        else if (jump_mode == 1)
        begin
            if (jump_to_read_data)
            begin
                test_judge                              <= 1;
                check_enable                            <= 1; 
                jump_to_check_data                      <= 0;
            end          
        end 
    end
    
    else if (check_enable)
    begin
        if (result_ctr < result_ctr_boundary)
        begin
            test_judge                                  <= test_judge & (correct_result_buffer[result_ctr] == request_out_buffer[result_ctr]);
            result_ctr                                  <= result_ctr + 1;
        end
        else
        begin
            if (test_judge)
            begin
                test_judge                              <= 1'b1;
            end
            else
            begin
                test_judge                              <= 1'b0;
            end
        end
    end
end

fifo_queue
#
(
    .QUEUE_SIZE                                         (QUEUE_SIZE),
    .QUEUE_PTR_WIDTH_IN_BITS                            (QUEUE_PTR_WIDTH_IN_BITS),
    .SINGLE_ENTRY_WIDTH_IN_BITS                         (SINGLE_ENTRY_WIDTH_IN_BITS),
    .STORAGE_TYPE                                       (STORAGE_TYPE)
)
fifo_queue
(
    .clk_in				                                (clk_in),
    .reset_in			                                (reset_in),

    .is_empty_out		                                (is_empty),
    .is_full_out		                                (is_full),

    .request_in			                                (request_in),
    .request_valid_in	                                (request_valid_in),
    .issue_ack_out		                                (issue_ack_from_fifo),
    .request_out		                                (request_out),
    .request_valid_out                                  (request_valid_out),
    .issue_ack_in		                                (issue_ack_to_fifo)
);

initial
begin
    `ifdef DUMP
        $dumpfile(`DUMP_FILENAME);
        $dumpvars(0, fifo_queue_testbench);
    `endif

        $display("\n[info-testbench] simulation for %m begins now");

        clk_in                                                          <= 1'b0;
        reset_in                                                        <= 1'b0;
        ack_to_fifo_mode                                                <= 1'b0;
        jump_mode                                                       <= 1'b0;

        test_case                                                       <= 0;

        request_in_ctr_boundary                                         <= 0;
        result_ctr_boundary                                             <= 0;

        $display("[info-testbench] %m testbench reset completed");
        
        #(`FULL_CYCLE_DELAY * 50) //init
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_in_buffer[test_gen]                                 <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;
            request_valid_in_buffer[test_gen]                           <= 0;
        end
        
        for (test_gen = 0; test_gen < QUEUE_SIZE; test_gen = test_gen + 1)
        begin
            correct_result_buffer[test_gen]                             <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}};
                      
        end        
        
        // test case 0
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;        
        end
        
        for (test_gen = 0; test_gen < QUEUE_SIZE / 2; test_gen = test_gen + 1)
        begin
            #(`FULL_CYCLE_DELAY ) request_in_buffer[test_gen]           <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);

                                  request_valid_in_buffer[test_gen]     <= 1;
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
                      
        end
                                request_in_ctr_boundary                 <= test_gen;
                                result_ctr_boundary                     <= test_gen;
         #(`FULL_CYCLE_DELAY )  reset_in                                <= 1;
         #(`FULL_CYCLE_DELAY )  reset_in                                <= 0;
         
                                is_ready_to_write                       <= 1;

         #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_read_data         <= 1;
         #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_check_data        <= 1;

         #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] test case %d %80s : \t%s", test_case, "normal write/read", ((test_judge == 1'b1))? "passed" : "failed");
        // test case 1
                                test_case                               <= test_case + 1;
 
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;        
        end
                                                               
        for (test_gen = 0; test_gen < QUEUE_SIZE; test_gen = test_gen + 1)
        begin
            #(`FULL_CYCLE_DELAY ) request_in_buffer[test_gen]           <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
            
            if (test_gen < 4)
            begin
                                  request_valid_in_buffer[test_gen]     <= 1;
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
            end
            else
            begin
                                  request_valid_in_buffer[test_gen]     <= 0;
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}};
            end
                                 
        end
                                request_in_ctr_boundary                 <= test_gen - QUEUE_SIZE / 2;
                                result_ctr_boundary                     <= test_gen - QUEUE_SIZE / 2;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 1;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 0;

                               is_ready_to_write                        <= 1;

        #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_read_data          <= 1;
        #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_check_data         <= 1;
        
        #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] test case %d %80s : \t%s", test_case, "write invalue data", ((test_judge == 1'b1))? "passed" : "failed");
        
        // test case 2
        test_case                                                       <= test_case + 1;
        
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;        
        end
           
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2; test_gen = test_gen + 1)
        begin
            #(`FULL_CYCLE_DELAY ) request_in_buffer[test_gen]           <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
                                  request_valid_in_buffer[test_gen]     <= 1;
            
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);                                 
        end
                                request_in_ctr_boundary                 <= test_gen;
                                result_ctr_boundary                     <= test_gen;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 1;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 0;
        
                                is_ready_to_write                       <= 1;
        
        #(`FULL_CYCLE_DELAY * (QUEUE_SIZE + 1))    jump_mode            <= 1;
                                             request_out_enable         <= 1;
        #(`FULL_CYCLE_DELAY)                 jump_to_read_data          <= 1;
        #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_check_data         <= 1;


        #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] test case %d %80s : \t%s", test_case, "write data to full queue", ((test_judge == 1'b1))? "passed" : "failed");
        
        // test case 3
        test_case                                                       <= test_case + 1;
        ack_to_fifo_mode                                                <= 1;
        jump_mode                                                       <= 1;
        

        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;        
        end
        
        for (test_gen = 0; test_gen < QUEUE_SIZE; test_gen = test_gen + 1)
        begin
            #(`FULL_CYCLE_DELAY ) request_in_buffer[test_gen]           <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);

                                  request_valid_in_buffer[test_gen]     <= 1;
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
                      
        end
                                request_in_ctr_boundary                 <= test_gen;
                                result_ctr_boundary                     <= test_gen;
         #(`FULL_CYCLE_DELAY )  reset_in                                <= 1;
         #(`FULL_CYCLE_DELAY )  reset_in                                <= 0;
         
                                is_ready_to_write                       <= 1;
                                request_out_enable                      <= 1;
                                 

         #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_read_data         <= 1;
         #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_check_data        <= 1;

         #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] test case %d %80s : \t%s", test_case, "normal write/read with early ack", ((test_judge == 1'b1))? "passed" : "failed");
        
        // test case 4
        test_case                                                       <= test_case + 1;
        jump_mode                                                       <= 0;
        
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2 + 1; test_gen = test_gen + 1)
        begin
            request_out_buffer[test_gen]                                <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b0}} ;        
        end
           
        for (test_gen = 0; test_gen < QUEUE_SIZE * 2; test_gen = test_gen + 1)
        begin
            #(`FULL_CYCLE_DELAY ) request_in_buffer[test_gen]           <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
                                  request_valid_in_buffer[test_gen]     <= 1;
            
                                  correct_result_buffer[test_gen]       <= {(SINGLE_ENTRY_WIDTH_IN_BITS){1'b1}} - test_gen * (test_case + 1);
                                 
        end
                                request_in_ctr_boundary                 <= test_gen;
                                result_ctr_boundary                     <= test_gen;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 1;
        #(`FULL_CYCLE_DELAY )   reset_in                                <= 0;
        
                                is_ready_to_write                       <= 1;
        
//        #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_mode                  <= 1;
        #(`FULL_CYCLE_DELAY * (QUEUE_SIZE + 1))    jump_mode            <= 1;

                                             request_out_enable         <= 1;
        #(`FULL_CYCLE_DELAY)                 jump_to_read_data          <= 1;
        #(`FULL_CYCLE_DELAY * test_gen * 6)  jump_to_check_data         <= 1;


        #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] test case %d %80s : \t%s", test_case, "write data to full queue with early ack", ((test_judge == 1'b1))? "passed" : "failed");
        
        
        #(`FULL_CYCLE_DELAY * 300) $display("[info-testbench] simulation comes to the end\n");
                                   $finish;
end

always begin #`HALF_CYCLE_DELAY clk_in                                  <= ~clk_in; end

endmodule

