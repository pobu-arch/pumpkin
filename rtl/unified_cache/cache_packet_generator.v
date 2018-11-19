`include "parameters.h"

module cache_packet_generator
#(
    parameter NUM_WAY                                 = 2,
    parameter NUM_REQUEST                             = 16,
    parameter TIMING_OUT_CYCLE                        = 100000,

    parameter MEM_SIZE                                = 65536,
    parameter NUM_TEST_CASE                           = 2,
    parameter MAX_NUM_TASK                            = 2,
    parameter NUM_TASK_TYPE                           = 2,

    parameter UNIFIED_CACHE_PACKET_WIDTH_IN_BITS      = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS,
    parameter UNIFIED_CACHE_PACKET_PORT_ID_WIDTH      = `UNIFIED_CACHE_PACKET_PORT_ID_WIDTH,
    parameter UNIFIED_CACHE_PACKET_BYTE_MASK_LEN      = `UNIFIED_CACHE_PACKET_BYTE_MASK_LEN,
    parameter UNIFIED_CACHE_BLOCK_OFFSET_LEN_IN_BITS  = `UNIFIED_CACHE_BLOCK_OFFSET_LEN_IN_BITS,
    parameter UNIFIED_CACHE_PACKET_TYPE_WIDTH         = `UNIFIED_CACHE_PACKET_TYPE_WIDTH,
    parameter UNIFIED_CACHE_BLOCK_SIZE_IN_BITS        = `UNIFIED_CACHE_BLOCK_SIZE_IN_BITS,
    parameter CPU_ADDR_LEN_IN_BITS                    = `CPU_ADDR_LEN_IN_BITS
)
(
    input                                                           reset_in,
    input                                                           clk_in,

    output  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_WAY  - 1 : 0] test_packet_flatted_out,
    input   [NUM_WAY                                       - 1 : 0] test_packet_ack_flatted_in,

    input   [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_WAY  - 1 : 0] return_packet_flatted_in,
    output  [NUM_WAY                                       - 1 : 0] return_packet_ack_flatted_out,

    output                                                          done,
    output                                                          error
);

// generate ctrl state
`define STATE_INIT      0
`define STATE_CLEAR     1
`define STATE_FINAL     2
`define STATE_CASE_0    3

// test case ctrl state
`define TEST_CASE_STATE_IDLE        0
`define TEST_CASE_STATE_CONFIG      1
`define TEST_CASE_STATE_DELAY       2
`define TEST_CASE_STATE_PREPROCESS  3
`define TEST_CASE_STATE_RUNNING     4
`define TEST_CASE_STATE_CHECK       5
`define TEST_CASE_STATE_FINAL       6

reg  [NUM_WAY - 1 : 0]                              return_packet_ack;
reg  [NUM_WAY - 1 : 0]                              done_way;
reg  [NUM_WAY - 1 : 0]                              error_way;
wire [UNIFIED_CACHE_PACKET_BYTE_MASK_LEN - 1 : 0]   write_mask;

assign done                             = &done_way;
assign error                            = |error_way;
assign return_packet_ack_flatted_out    = return_packet_ack;
assign write_mask                       = {{(UNIFIED_CACHE_PACKET_BYTE_MASK_LEN/2){2'b11}}};

reg [`UNIFIED_CACHE_BLOCK_SIZE_IN_BITS - 1 : 0] sim_memory [`MEM_SIZE - 1 : 0];

// test case state
reg [31:0] test_case;
reg [31:0] generator_ctrl_state;
reg [31:0] test_case_ctrl_state;

// request buffer
reg [(NUM_REQUEST * NUM_WAY) - 1 : 0] packed_way_packet_out_buffer [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0];
reg [(NUM_REQUEST * NUM_WAY) - 1 : 0] packed_way_packet_in_buffer [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0];
reg [NUM_WAY - 1 : 0] packed_way_packet_out_buffer_boundry [31:0];
reg [NUM_WAY - 1 : 0] packed_way_packet_in_buffer_boundry [31:0];

// couter
// reg [NUM_WAY - 1 : 0] packed_way_packet_out_buffer_ctr [31:0];
// reg [NUM_WAY - 1 : 0] packed_way_packet_in_buffer_ctr [31:0];
reg [$clog2(MAX_NUM_TASK) - 1 : 0] task_list_ctr;
// reg [NUM_WAY * 32 - 1 : 0] way_out_time_delay_ctr;
// reg [NUM_WAY * 32 - 1 : 0] way_in_time_delay_ctr;

// test case config reg - task list
reg [MAX_NUM_TASK - 1 : 0] task_type_list_reg;
reg [MAX_NUM_TASK - 1 : 0] task_num_request_reg [NUM_REQUEST - 1 : 0];
reg [$clog2(MAX_NUM_TASK) - 1 : 0] num_task;

// test case config reg - request in & out
reg [NUM_WAY - 1 : 0] way_in_enable_reg;
reg [NUM_WAY - 1 : 0] way_out_enable_reg;
reg [NUM_WAY * 32 - 1 : 0] way_in_time_delay;
reg [NUM_WAY * 32 - 1 : 0] way_out_time_delay;

// test case config reg - check
reg ckeck_mode_reg; // 0 - default check method (scoreboard), 1 - user-defined

// test case config reg - preprocess
reg preprocess_mode_reg // 0 - no pretreatment, 1 - user-defined
reg preprocess_end_flag;


// error & done
reg [NUM_TEST_CASE - 1 : 0] done_vector [NUM_WAY - 1 : 0];
reg [NUM_TEST_CASE - 1 : 0] error_vector [NUM_WAY - 1 : 0];

// way control
wire [NUM_WAY - 1 : 0] packet_in_enable_way;
wire [NUM_WAY - 1 : 0] packet_out_enable_way;
wire [NUM_WAY - 1 : 0] packet_out_end_way_flag;
wire [NUM_WAY - 1 : 0] packet_in_end_way_flag;
wire [NUM_WAY - 1 : 0] check_end_way_flag;
wire packet_out_end_flag;
wire packet_in_end_flag;
wire check_end_flag;
wire way_clear_flag;

// task way control flag
wire [MAX_NUM_TASK - 1 : 0] running_end_task_flag;
wire running_end_flag;
wire [NUM_WAY * NUM_TASK_TYPE - 1 : 0] task_end_way_flag;
wire task_end_flag;
wire next_task_clear_flag;


// test case state abstract
wire test_case_config;
wire test_case_preprocess;
wire test_case_runnig;
wire test_case_check;
wire test_case_final;

// test case state abstract
assign test_case_config = test_case_ctrl_state == TEST_CASE_STATE_CONFIG;
assign test_case_preprocess = test_case_ctrl_state == TEST_CASE_STATE_PREPROCESS;
assign test_case_running = test_case_ctrl_state == TEST_CASE_STATE_RUNNING;
assign test_case_check = test_case_ctrl_state == TEST_CASE_STATE_CHECK;
assign test_case_final = test_case_ctrl_state == TEST_CASE_STATE_FINAL;

// send & recieve
generate
genvar WAY_INDEX;

for(WAY_INDEX = 0; WAY_INDEX < NUM_WAY; WAY_INDEX = WAY_INDEX + 1)
begin:way_logic

    if(WAY_INDEX == 0)
    begin

        integer request_in_index;
        integer scoreboard_index;

        reg  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]   test_packet;
        assign test_packet_flatted_out[WAY_INDEX * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS +: UNIFIED_CACHE_PACKET_WIDTH_IN_BITS] = test_packet;

        assign packet_out_end_way_flag[WAY_INDEX] = ~error_way[WAY_INDEX] & packet_in_enable_way[WAY_INDEX];

        // counter
        reg  [31                                     : 0]   request_counter;
        reg  [63                                     : 0]   timeout_counter;
        reg  [31                                     : 0]   delay_counter;

        wire [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]   packet_concatenated;
        wire [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]   packet_from_buffer;

        assign packet_from_buffer = (packed_way_packet_in_buffer
                                    [WAY_INDEX * NUM_REQUEST + request_counter - 1 : 0]);

        // from buffer
        packet_concat test_packet_concat
        (
            .addr_in        (packet_from_buffer[UNIFIED_CACHE_PACKET_ADDR_POS_HI : UNIFIED_CACHE_PACKET_ADDR_POS_LO]),
            .data_in        (packet_from_buffer[UNIFIED_CACHE_PACKET_DATA_POS_HI : UNIFIED_CACHE_PACKET_DATA_POS_LO]),
            .type_in        (packet_from_buffer[UNIFIED_CACHE_PACKET_TYPE_POS_HI : UNIFIED_CACHE_PACKET_TYPE_POS_LO]),
            .write_mask_in  (packet_from_buffer[UNIFIED_CACHE_PACKET_BYTE_MASK_POS_HI : UNIFIED_CACHE_PACKET_BYTE_MASK_POS_LO]),
            .port_num_in    (packet_from_buffer[UNIFIED_CACHE_PACKET_PORT_NUM_HI : UNIFIED_CACHE_PACKET_PORT_NUM_LO]),
            .valid_in       (packet_from_buffer[UNIFIED_CACHE_PACKET_VALID_POS]),
            .is_write_in    (packet_from_buffer[UNIFIED_CACHE_PACKET_IS_WRITE_POS]),
            .cacheable_in   (packet_from_buffer[UNIFIED_CACHE_PACKET_CACHEABLE_POS]),
            .packet_out     (packet_concatenated)
        );

        // packet_concat test_packet_concat
        // (
        //     .addr_in        ({(CPU_ADDR_LEN_IN_BITS/32){32'h0000_1000}} + (request_counter << UNIFIED_CACHE_BLOCK_OFFSET_LEN_IN_BITS)),
        //     .data_in        ({(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS/32){request_counter}}),
        //     .type_in        ({(UNIFIED_CACHE_PACKET_TYPE_WIDTH){1'b0}}),
        //     .write_mask_in  (write_mask),
        //     .port_num_in    ({(UNIFIED_CACHE_PACKET_PORT_ID_WIDTH){1'b0}}),
        //     .valid_in       (1'b1),
        //     .is_write_in    (1'b1),
        //     .cacheable_in   (1'b1),
        //     .packet_out     (packet_concatenated)
        // );

        // request out
        always@(posedge clk_in)
        begin
            if(reset_in)
            begin
                test_packet                     <= 0;
                request_counter                 <= 0;
                timeout_counter                 <= 0;
                return_packet_ack[WAY_INDEX]    <= 0;
                done_way[WAY_INDEX]             <= 0;
                error_way[WAY_INDEX]            <= 0;
            end

            else if(packet_in_enable_way[WAY_INDEX])
            begin
                if (way_clear_flag)
                begin
                    test_packet                     <= 0;
                    request_counter                 <= 0;
                    timeout_counter                 <= 0;
                    return_packet_ack[WAY_INDEX]    <= 0;
                    done_way[WAY_INDEX]             <= 0;
                    error_way[WAY_INDEX]            <= 0;
                end

                else if (~error_way[WAY_INDEX])
                begin
                    if(~test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & ~done_way[WAY_INDEX])
                    begin
                        test_packet                     <= packet_concatenated;
                        request_counter                 <= request_counter;
                        timeout_counter                 <= 0;
                        done_way[WAY_INDEX]             <= 0;
                        error_way[WAY_INDEX]            <= 0;
                    end

                    else if(test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & test_packet_ack_flatted_in[WAY_INDEX])
                    begin
                        test_packet                     <= 0;
                        request_counter                 <= request_counter + 1'b1;
                        timeout_counter                 <= 0;
                        done_way[WAY_INDEX]             <= request_counter == NUM_REQUEST - 1;
                        error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE ? 1'b1 : 1'b0;
                    end

                    else
                    begin
                        test_packet                     <= test_packet;
                        request_counter                 <= request_counter;
                        timeout_counter                 <= timeout_counter + 1'b1;
                        done_way[WAY_INDEX]             <= done_way[WAY_INDEX];
                        error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE & ~done_way[WAY_INDEX]? 1'b1 : 1'b0;
                    end
                end
            end
        end

        // request in
        always@(posedge clk_in)
        begin
            if(reset_in)
            begin
                return_packet_ack[WAY_INDEX]    <= 0;
                timeout_counter                 <= 0;
                expected_data                   <= 32'h0000_0000;
                error_way[WAY_INDEX]            <= 0;
            end

            else if(~error_way[WAY_INDEX])
            begin

                //
                if(return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 1;
                    timeout_counter                 <= 0;
                    error_way[WAY_INDEX]            <= (return_data !=
                                                    ({(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS/32){expected_data}} & write_mask))
                                                    | timeout_counter >= TIMING_OUT_CYCLE;
                    expected_data                   <= expected_data + 1'b1;
                end

                // wait
                else if(~return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 0;
                    timeout_counter                 <= timeout_counter + 1'b1;
                    error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE;
                    expected_data                   <= expected_data;
                end
            end
        end

        // check
        always@(posedge clk_in)
        begin
            if (reset_in)
            begin
                request_in_counter
                request_out_counter

                request_in_buffer
                request_out_buffer

                scoreboard_valid_array

                request_in_from_buffer
                request_out_from_buffer

                request_out_valid
            end
            else
            begin
                if (check_enable)
                begin
                    if (~check_end_flag)
                    begin
                        // scoreboard

                        request_in_counter <= request_in_counter + 1'b1;

                        for (scoreboard_index = 0; scoreboard_index < NUM_REQUEST; scoreboard_index = scoreboard_index + 1'b1;)
                        begin: next_score

                            if ((request_out_buffer[request_out_index]
                                    [UNIFIED_CACHE_PACKET_ADDR_POS_HI : UNIFIED_CACHE_PACKET_ADDR_POS_LO]
                                == request_in_buffer[request_in_index]
                                    [UNIFIED_CACHE_PACKET_ADDR_POS_HI : UNIFIED_CACHE_PACKET_ADDR_POS_LO])
                                & scoreboard_valid_array[request_in_index])
                            begin
                                scoreboard_valid_array[request_in_index] <= 1'b0;
                                disable next_score;
                            end
                        end
                    end
                end
            end
        end

    end

    if(WAY_INDEX == 1)
    begin
        reg [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS  - 1 : 0]    test_packet;
        assign test_packet_flatted_out[WAY_INDEX * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS +: UNIFIED_CACHE_PACKET_WIDTH_IN_BITS] = test_packet;

        reg [31                                      : 0]    request_counter;
        reg [63                                      : 0]    timeout_counter;
        reg [31                                      : 0]    expected_data;

        wire [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]    packet_concatenated;
        packet_concat test_packet_concat
        (
            .addr_in        ({(CPU_ADDR_LEN_IN_BITS/32){32'h0000_1000 + (request_counter << UNIFIED_CACHE_BLOCK_OFFSET_LEN_IN_BITS)}}),
            .data_in        ({(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS){1'b0}}),
            .type_in        ({(UNIFIED_CACHE_PACKET_TYPE_WIDTH){1'b0}}),
            .write_mask_in  ({(UNIFIED_CACHE_PACKET_BYTE_MASK_LEN){1'b0}}),
            .port_num_in    ({{(UNIFIED_CACHE_PACKET_PORT_ID_WIDTH-2){1'b0}}, {2'b01}}),
            .valid_in       (1'b1),
            .is_write_in    (1'b0),
            .cacheable_in   (1'b1),
            .packet_out     (packet_concatenated)
        );

        always@(posedge clk_in)
        begin
            if(reset_in)
            begin
                test_packet                     <= 0;
                request_counter                 <= 0;
                done_way[WAY_INDEX]             <= 0;
            end

            else if(done_way[WAY_INDEX-1] & ~error_way[WAY_INDEX])
            begin
                if(~test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & ~done_way[WAY_INDEX])
                begin
                    test_packet                     <= packet_concatenated;
                    request_counter                 <= request_counter;
                    done_way[WAY_INDEX]             <= 0;
                end

                else if(test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & test_packet_ack_flatted_in[WAY_INDEX])
                begin
                    test_packet                     <= 0;
                    request_counter                 <= request_counter + 1'b1;
                    done_way[WAY_INDEX]             <= request_counter == NUM_REQUEST;
                end

                else
                begin
                    test_packet                     <= test_packet;
                    request_counter                 <= request_counter;
                    done_way[WAY_INDEX]             <= done_way[WAY_INDEX];
                end
            end
        end

        wire [`UNIFIED_CACHE_PACKET_DATA_POS_HI : `UNIFIED_CACHE_PACKET_DATA_POS_LO] return_data =
        return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_DATA_POS_LO +:
                                                                                    UNIFIED_CACHE_BLOCK_SIZE_IN_BITS];

        always@(posedge clk_in)
        begin
            if(reset_in)
            begin
                return_packet_ack[WAY_INDEX]    <= 0;
                timeout_counter                 <= 0;
                expected_data                   <= 32'h0000_0000;
                error_way[WAY_INDEX]            <= 0;
            end

            else if(~error_way[WAY_INDEX])
            begin

                //
                if(return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 1;
                    timeout_counter                 <= 0;
                    error_way[WAY_INDEX]            <= (return_data !=
                                                    ({(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS/32){expected_data}} & write_mask))
                                                    | timeout_counter >= TIMING_OUT_CYCLE;
                    expected_data                   <= expected_data + 1'b1;
                end

                // wait
                else if(~return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 0;
                    timeout_counter                 <= timeout_counter + 1'b1;
                    error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE;
                    expected_data                   <= expected_data;
                end
            end
        end
    end
end
endgenerate


// generator ctrl state
always @ (posedge clk_in)
begin
    if (reset_in)
    begin
        generator_ctrl_state <= `STATE_INIT;
    end
    else
    begin
        case (generator_ctrl_state)


            `STATE_INIT:
            begin

            end


            `STATE_CLEAR:
            begin

            end


            `STATE_FINAL:
            begin
                generator_ctrl_state <= generator_ctrl_state;
            end


            `STATE_CASE_0:
            begin
                if (test_case_config)
                begin

                end

                if (test_case_preprocess)
                begin

                end

                if (test_case_check)
                begin

                end

                if (test_case_final)
                begin
                    //state transition
                    if (generator_ctrl_state == `STATE_CASE_0 + NUM_TEST_CASE - 1)
                    begin
                        generator_ctrl_state <= `STATE_FINAL;
                    end
                    else
                    begin
                        generator_ctrl_state <= generator_ctrl_state + 1;
                    end
                end
            end

/**
            `STATE_CASE_X:
            begin
                if (test_case_config)
                begin
                    // insert your code
                end
                if (test_case_preprocess)
                begin
                    // insert your code
                end
                if (test_case_check)
                begin
                    // insert your code
                end
                if (test_case_final)
                begin
                    //state transition
                    if (generator_ctrl_state == `STATE_CASE_0 + NUM_TEST_CASE - 1)
                    begin
                        generator_ctrl_state <= `STATE_FINAL;
                    end
                    else
                    begin
                        generator_ctrl_state <= generator_ctrl_state + 1;
                    end
                end
            end
 **/

            default: ;
        endcase

    end
end

// test case ctrl state
always @(posedge clk_in)
begin
    if (reset_in)
    begin
        test_case_ctrl_state <= 1'b0;
    end
    else
    begin
        case (test_case_ctrl_state)

            `TEST_CASE_STATE_IDLE:
            begin

            end

            `TEST_CASE_STATE_CONFIG:
            begin
                test_case_ctrl_state <= `TEST_CASE_STATE_DELAY;
            end

            `TEST_CASE_STATE_DELAY:
            begin
                if (preprocess_mode_reg)
                begin
                    test_case_ctrl_state <= `TEST_CASE_STATE_PREPROCESS;
                end
                else
                begin
                    test_case_ctrl_state <= `TEST_CASE_STATE_RUNNING;
                end
            end

            `TEST_CASE_STATE_PREPROCESS:
            begin
                if (preprocess_end_flag)
                begin
                    test_case_ctrl_state <= `TEST_CASE_STATE_RUNNING;
                end
            end

            `TEST_CASE_STATE_RUNNING:
            begin
                if (packet_in_end_flag & packet_out_end_flag)
                begin
                    test_case_ctrl_state <= `TEST_CASE_STATE_CHECK;
                end
            end

            `TEST_CASE_STATE_CHECK:
            begin
                if (check_end_flag)
                begin
                    test_case_ctrl_state <= `TEST_CASE_STATE_FINAL;
                end
            end

            `TEST_CASE_STATE_FINAL:
            begin
                test_case_ctrl_state <= `TEST_CASE_STATE_IDLE;
            end
        end
    endcase
end
endmodule
