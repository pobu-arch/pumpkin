`include "parameters.vh"

module unified_cache_bank
#(
    parameter NUM_INPUT_PORT                     = 2,
    parameter NUM_SET                            = 4,
    parameter NUM_WAY                            = 4,
    parameter BLOCK_SIZE_IN_BYTES                = 4,

    parameter BANK_NUM                           = 0,
    parameter MODE                               = `UNIFIED_CACHE_BANK_ARCHITECTURE,

    parameter UNIFIED_CACHE_PACKET_WIDTH_IN_BITS = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS,
    parameter BLOCK_SIZE_IN_BITS                 = BLOCK_SIZE_IN_BYTES * `BYTE_LEN_IN_BITS,
    parameter SET_PTR_WIDTH_IN_BITS              = $clog2(NUM_SET) + 1
)
(
    input                                                                   clk_in,
    input                                                                   reset_in,
    input  [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]  input_request_flatted_in,
    input  [NUM_INPUT_PORT                                        - 1 : 0]  input_request_valid_flatted_in,
    input  [NUM_INPUT_PORT                                        - 1 : 0]  input_request_critical_flatted_in,
    output [NUM_INPUT_PORT                                        - 1 : 0]  input_request_ack_out,

    input  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS                    - 1 : 0]  fetched_request_in,
    input                                                                   fetched_request_valid_in,
    output                                                                  fetch_ack_out,

    output [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS                    - 1 : 0]  miss_request_out,
    output                                                                  miss_request_valid_out,
    output                                                                  miss_request_critical_out,
    input                                                                   miss_request_ack_in,

    output [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS                    - 1 : 0]  writeback_request_out,
    output                                                                  writeback_request_valid_out,
    output                                                                  writeback_request_critical_out,
    input                                                                   writeback_request_ack_in,

    output [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS                    - 1 : 0]  return_request_out,
    output                                                                  return_request_valid_out,
    output                                                                  return_request_critical_out,
    input                                                                   return_request_ack_in
);

generate

if(MODE == "Bypass")
begin
    priority_arbiter
    #(
        .SINGLE_REQUEST_WIDTH_IN_BITS(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS),
        .NUM_REQUEST(NUM_INPUT_PORT),
        .INPUT_QUEUE_SIZE(2)
    )
    intra_bank_arbiter
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        // the arbiter considers priority from right(high) to left(low)
        .request_flatted_in             (input_request_flatted_in),
        .request_valid_flatted_in       (input_request_valid_flatted_in),
        .request_critical_flatted_in    (input_request_critical_flatted_in),
        .issue_ack_out                  (input_request_ack_out),

        .request_out                    (miss_request_out),
        .request_valid_out              (miss_request_valid_out),
        .issue_ack_in                   (miss_request_ack_in)
    );

    assign miss_request_critical_out        = 1'b0;

    assign return_request_out               = fetched_request_in;
    assign return_request_valid_out         = fetched_request_valid_in;
    assign fetch_ack_out                    = return_request_ack_in;
    assign return_request_critical_out      = 1'b1;

    assign writeback_request_out            = 0;
    assign writeback_request_valid_out      = 0;
    assign writeback_request_critical_out   = 0;
end

else if(MODE == "Basic")
begin
    priority_arbiter
    #(
        .NUM_REQUEST(NUM_INPUT_PORT + 1), // input requests + miss replay
        .SINGLE_REQUEST_WIDTH_IN_BITS(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)
    )
    intra_bank_arbiter
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        // the arbiter considers priority from right(high) to left(low)
        .request_flatted_in             ({input_request_flatted_in}),
        .request_valid_flatted_in       ({input_request_valid_flatted_in}),
        .request_critical_flatted_in    ({input_request_critical_flatted_in}),
        .issue_ack_out                  ({input_request_ack_out}),

        .request_out                    (access_packet),
        .request_valid_out              (),
        .issue_ack_in                   (access_packet_ack)
    );

    associative_single_port_array
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS  (`UNIFIED_CACHE_TAG_LEN_IN_BITS),
        .NUM_SET                    (NUM_SET),
        .NUM_WAY                    (NUM_WAY),
        .STORAGE_TYPE               ("BlockRAM")
    )
    tag_array
    (
        .reset_in                   (reset_in),
        .clk_in                     (clk_in),

        .access_en_in               (),
        .write_en_in                (),
        
        .access_set_addr_in         (),
        .way_select_in              (),
        
        .read_set_out               (),
        .read_single_entry_out      (),
        .write_single_entry_in      ()
    );

    single_port_blockram
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (BLOCK_SIZE_IN_BITS),
        .NUM_SET                        (NUM_SET)
    )
    data_array
    (
        .clk_in                         (clk_in),

        .access_en_in                   (),
        .write_en_in                    (),

        .access_set_addr_in             (),

        .write_entry_in                 (),
        .read_entry_out                 ()
    );
end

else if(MODE == "Aggressive")
begin
    wire                                              is_miss_queue_about_to_full;
    wire [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0] miss_replay_request;
    wire                                              miss_replay_request_ack;

    wire [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0] access_packet;
    wire                                              access_packet_ack;

    wire                                              request_critical_lower_flatted = is_miss_queue_about_to_full ?
                                                                                        ~input_request_critical_flatted_in :
                                                                                        input_request_critical_flatted_in;

    priority_arbiter
    #(
        .NUM_REQUEST(NUM_INPUT_PORT + 1), // input requests + miss replay
        .SINGLE_REQUEST_WIDTH_IN_BITS(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)
    )
    intra_bank_arbiter
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        // the arbiter considers priority from right(high) to left(low)
        .request_flatted_in             ({miss_replay_request, input_request_flatted_in}),
        .request_valid_flatted_in       ({miss_replay_request[`UNIFIED_CACHE_PACKET_VALID_POS], input_request_valid_flatted_in}),
        .request_critical_flatted_in    ({is_miss_queue_about_to_full, input_request_critical_flatted_in}),
        .issue_ack_out                  ({miss_replay_request_ack, input_request_ack_out}),

        .request_out                    (access_packet),
        .request_valid_out              (),
        .issue_ack_in                   (access_packet_ack)
    );

    associative_single_port_array
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS  (1),
        .NUM_SET                    (NUM_SET),
        .NUM_WAY                    (NUM_WAY),
        .STORAGE_TYPE               ("LUTRAM")
    )
    valid_array
    (
        .reset_in                   (reset_in),
        .clk_in                     (clk_in),

        .access_en_in               (),
        .write_en_in                (),
        
        .access_set_addr_in         (),
        .way_select_in              (),
        
        .read_set_out               (),
        .read_single_entry_out      (),
        .write_single_entry_in      ()
    );

    associative_single_port_array
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS  (1),
        .NUM_SET                    (NUM_SET),
        .NUM_WAY                    (NUM_WAY),
        .STORAGE_TYPE               ("BlockRAM")
    )
    history_array
    (
        .reset_in                   (reset_in),
        .clk_in                     (clk_in),

        .access_en_in               (),
        .write_en_in                (),
        
        .access_set_addr_in         (),
        .way_select_in              (),
        
        .read_set_out               (),
        .read_single_entry_out      (),
        .write_single_entry_in      ()
    );

    associative_single_port_array
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS  (1),
        .NUM_SET                    (NUM_SET),
        .NUM_WAY                    (NUM_WAY),
        .STORAGE_TYPE               ("BlockRAM")
    )
    dirty_array
    (
        .reset_in                   (reset_in),
        .clk_in                     (clk_in),

        .access_en_in               (),
        .write_en_in                (),
        
        .access_set_addr_in         (),
        .way_select_in              (),
        
        .read_set_out               (),
        .read_single_entry_out      (),
        .write_single_entry_in      ()
    );

    associative_single_port_array
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS  (`UNIFIED_CACHE_TAG_LEN_IN_BITS),
        .NUM_SET                    (NUM_SET),
        .NUM_WAY                    (NUM_WAY),
        .STORAGE_TYPE               ("BlockRAM")
    )
    tag_array
    (
        .reset_in                   (reset_in),
        .clk_in                     (clk_in),

        .access_en_in               (),
        .write_en_in                (),
        
        .access_set_addr_in         (),
        .way_select_in              (),
        
        .read_set_out               (),
        .read_single_entry_out      (),
        .write_single_entry_in      ()
    );

    // writeback buffer
    tri_port_regfile
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (1),
        .NUM_ENTRY                      (`UNIFIED_CACHE_WRITEBACK_BUFFER_SIZE)
    )
    writeback_buffer_valid_array
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .read_en_in                     (),
        .write_en_in                    (),
        .cam_en_in                      (),

        .read_entry_addr_decoded_in     (),
        .write_entry_addr_decoded_in    (),
        .cam_entry_in                   (),

        .write_entry_in                 (),
        .read_entry_out                 (),
        .cam_result_decoded_out         ()
    );

    tri_port_regfile
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (`UNIFIED_CACHE_TAG_LEN_IN_BITS),
        .NUM_ENTRY                      (`UNIFIED_CACHE_WRITEBACK_BUFFER_SIZE)
    )
    writeback_buffer_tag_array
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .read_en_in                     (),
        .write_en_in                    (),
        .cam_en_in                      (),

        .read_entry_addr_decoded_in     (),
        .write_entry_addr_decoded_in    (),
        .cam_entry_in                   (),

        .write_entry_in                 (),
        .read_entry_out                 (),
        .cam_result_decoded_out         ()
    );

    single_port_blockram
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (BLOCK_SIZE_IN_BITS),
        .NUM_SET                        (`UNIFIED_CACHE_WRITEBACK_BUFFER_SIZE)
    )
    writeback_buffer_data_array
    (
        .clk_in                         (clk_in),

        .access_en_in                   (),
        .write_en_in                    (),

        .access_set_addr_in             (),

        .write_entry_in                 (),
        .read_entry_out                 ()
    );

    // miss buffer
    tri_port_regfile
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (1),
        .NUM_ENTRY                      (`UNIFIED_CACHE_MISS_BUFFER_SIZE)
    )
    miss_buffer_valid_array
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .read_en_in                     (),
        .write_en_in                    (),
        .cam_en_in                      (),

        .read_entry_addr_decoded_in     (),
        .write_entry_addr_decoded_in    (),
        .cam_entry_in                   (),

        .write_entry_in                 (),
        .read_entry_out                 (),
        .cam_result_decoded_out         ()
    );

    tri_port_regfile
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (1),
        .NUM_ENTRY                      (`UNIFIED_CACHE_MISS_BUFFER_SIZE)
    )
    miss_buffer_fetched_array
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .read_en_in                     (),
        .write_en_in                    (),
        .cam_en_in                      (),

        .read_entry_addr_decoded_in     (),
        .write_entry_addr_decoded_in    (),
        .cam_entry_in                   (),

        .write_entry_in                 (),
        .read_entry_out                 (),
        .cam_result_decoded_out         ()
    );

    tri_port_regfile
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (`UNIFIED_CACHE_TAG_LEN_IN_BITS),
        .NUM_ENTRY                      (`UNIFIED_CACHE_MISS_BUFFER_SIZE)
    )
    miss_buffer_tag_array
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .read_en_in                     (),
        .write_en_in                    (),
        .cam_en_in                      (),

        .read_entry_addr_decoded_in     (),
        .write_entry_addr_decoded_in    (),
        .cam_entry_in                   (),

        .write_entry_in                 (),
        .read_entry_out                 (),
        .cam_result_decoded_out         ()
    );

    single_port_blockram
    #(
        .SINGLE_ENTRY_SIZE_IN_BITS      (BLOCK_SIZE_IN_BITS),
        .NUM_SET                        (`UNIFIED_CACHE_WRITEBACK_BUFFER_SIZE)
    )
    miss_buffer_data_array
    (
        .clk_in                         (clk_in),

        .access_en_in                   (),
        .write_en_in                    (),

        .access_set_addr_in             (),

        .write_entry_in                 (),
        .read_entry_out                 ()
    );


    cache_main_pipe_stage_1_ctrl
    #(

    )
    cache_main_pipe_stage_1_ctrl
    (

    );
end
endgenerate

endmodule