`include "parameters.h"

module unified_cache
#(
    parameter NUM_INPUT_PORT                     = 2,
    parameter NUM_BANK                           = `NUM_CACHE_BANK,
    parameter UNIFIED_CACHE_PACKET_WIDTH_IN_BITS = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS

)
(
    input                                                                               reset_in,
    input                                                                               clk_in,

    // input packet
    input   [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]             input_packet_flatted_in,
    output  [NUM_INPUT_PORT - 1 : 0]                                                    input_packet_ack_flatted_out,

    // return packet
    output  [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]             output_packet_flatted_out,
    input   [NUM_INPUT_PORT - 1 : 0]                                                    output_packet_ack_flatted_in,

    // from mem
    input   [(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]                              from_mem_packet_in,
    output                                                                              from_mem_packet_ack_out,

    // to mem
    output  [(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]                              to_mem_packet_out,
    input                                                                               to_mem_packet_ack_in
);

wire  [(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]                    input_packet_packed [NUM_INPUT_PORT - 1 : 0];
wire  [NUM_INPUT_PORT - 1 : 0]                                          is_input_queue_full_flatted;

wire  [(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]                    input_packet_to_cache_packed [NUM_INPUT_PORT - 1 : 0];
wire  [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]   input_packet_to_cache_flatted;
wire  [NUM_INPUT_PORT - 1 : 0]                                          input_packet_valid_to_cache_flatted;
wire  [NUM_INPUT_PORT - 1 : 0]                                          input_packet_critical_to_cache_flatted;
wire  [NUM_INPUT_PORT - 1 : 0]                                          cache_to_input_queue_ack_merged;

// generate auto-connection between mulitple ports and banks
generate
genvar port_index, bank_index;

for(port_index = 0; port_index < NUM_INPUT_PORT; port_index = port_index + 1)
begin

    assign input_packet_packed[port_index] = 
           input_packet_flatted_in[(port_index + 1) * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 :
                                    port_index      * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)];
    
    fifo_queue
    #(
        .QUEUE_SIZE                     (`INPUT_QUEUE_SIZE),
        .QUEUE_PTR_WIDTH_IN_BITS        ($clog2(`INPUT_QUEUE_SIZE)),
        .SINGLE_ENTRY_WIDTH_IN_BITS     (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)
    )
    input_queue
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .is_empty_out                   (), // intened left unconnected
        .is_full_out                    (is_input_queue_full_flatted[port_index]),

        .request_in                     (input_packet_packed[port_index]),
        .request_valid_in               (input_packet_packed[port_index][`UNIFIED_CACHE_PACKET_VALID_POS]),
        .issue_ack_out                  (input_packet_ack_flatted_out[port_index]),
        
        .request_out                    (input_packet_to_cache_packed[port_index]),
        .request_valid_out              (input_packet_valid_to_cache_flatted[port_index]),
        .issue_ack_in                   (cache_to_input_queue_ack_merged[port_index])
    );

    assign input_packet_to_cache_flatted[(port_index + 1) * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 :
                                               port_index * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)]
            = input_packet_to_cache_packed[port_index];
    
    assign input_packet_critical_to_cache_flatted[port_index] = is_input_queue_full_flatted[port_index];
end
endgenerate

wire  [NUM_INPUT_PORT * NUM_BANK                     - 1 : 0] cache_to_input_queue_ack_flatted;
wire  [NUM_INPUT_PORT                                - 1 : 0] from_mem_packet_ack_flatted;

wire  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_BANK - 1 : 0] miss_request_flatted;
wire  [NUM_BANK                                      - 1 : 0] miss_request_valid_flatted;
wire  [NUM_BANK                                      - 1 : 0] miss_request_critical_flatted;
wire  [NUM_BANK                                      - 1 : 0] miss_request_ack_flatted;

wire  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_BANK - 1 : 0] writeback_request_flatted;
wire  [NUM_BANK                                      - 1 : 0] writeback_request_valid_flatted;
wire  [NUM_BANK                                      - 1 : 0] writeback_request_critical_flatted;
wire  [NUM_BANK                                      - 1 : 0] writeback_request_ack_flatted;

wire  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_BANK - 1 : 0] return_request_flatted;
wire  [NUM_BANK                                      - 1 : 0] return_request_valid_flatted;
wire  [NUM_BANK                                      - 1 : 0] return_request_critical_flatted;
wire  [NUM_BANK                                      - 1 : 0] return_request_ack_merged;

// generate cache banks
generate
for(bank_index = 0; bank_index < NUM_BANK; bank_index = bank_index + 1)
begin
    unified_cache_bank
    #(
        .UNIFIED_CACHE_PACKET_WIDTH_IN_BITS (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS),
        .BANK_NUM                           (bank_index)
    )
    cache_bank
    (
        .request_flatted_in                 (input_packet_to_cache_flatted),
        .request_valid_flatted_in           (input_packet_valid_to_cache_flatted),
        .request_critical_flatted_in        (input_packet_critical_to_cache_flatted),
        .issue_ack_out                      (cache_to_input_queue_ack_flatted[(bank_index+1) * NUM_INPUT_PORT - 1 :
                                                                                  bank_index * NUM_INPUT_PORT]),

        .fetched_request_in                 (from_mem_packet_in),
        .fetched_request_valid_in           (from_mem_packet_in[`UNIFIED_CACHE_PACKET_VALID_POS]),
        .fetch_ack_out                      (from_mem_packet_ack_flatted[bank_index]),

        .miss_request_out                   (miss_request_flatted[(bank_index+1) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 :
                                                                   bank_index * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS]),
        .miss_request_valid_out             (miss_request_valid_flatted[bank_index]),
        .miss_request_critical_out          (miss_request_critical_flatted[bank_index]),
        .miss_request_ack_in                (miss_request_ack_flatted[bank_index]),

        .writeback_request_out              (writeback_request_flatted[(bank_index+1) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 :
                                                                        bank_index * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS]),
        .writeback_request_valid_out        (writeback_request_valid_flatted[bank_index]),
        .writeback_request_critical_out     (writeback_request_critical_flatted[bank_index]),
        .writeback_request_ack_in           (writeback_request_ack_flatted[bank_index]),

        .return_request_out                 (return_request_flatted[(bank_index+1) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 :
                                                                     bank_index * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS]),
        .return_request_valid_out           (return_request_valid_flatted[bank_index]),
        .return_request_critical_out        (return_request_critical_flatted[bank_index]),
        .return_request_ack_in              (return_request_ack_merged[bank_index])
    );
end
endgenerate

// ack to/from mem
assign from_mem_packet_ack_out = |from_mem_packet_ack_flatted;

wire [NUM_BANK - 1 : 0] cache_to_input_queue_ack_packed[NUM_INPUT_PORT - 1 : 0];
generate
    for(port_index = 0; port_index < NUM_INPUT_PORT; port_index = port_index + 1)
    begin
        for(bank_index = 0; bank_index < NUM_BANK; bank_index = bank_index + 1)
        begin
            assign cache_to_input_queue_ack_packed [port_index][bank_index] =
                   cache_to_input_queue_ack_flatted[bank_index * port_index + port_index];
        end
    end
endgenerate

assign cache_to_input_queue_ack_merged[port_index] = |(cache_to_input_queue_ack_packed[port_index]);

priority_arbiter
#(
    .NUM_REQUEST(NUM_INPUT_PORT),
    .SINGLE_REQUEST_WIDTH_IN_BITS(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)
)
to_mem_arbiter
(
    .reset_in                       (reset_in),
    .clk_in                         (clk_in),

    // the arbiter considers priority from right(high) to left(low)
    .request_flatted_in             ({miss_request_flatted, writeback_request_flatted}),
    .request_valid_flatted_in       ({miss_request_valid_flatted, writeback_request_valid_flatted}),
    .request_critical_flatted_in    ({miss_request_critical_flatted, writeback_request_critical_flatted}),
    .issue_ack_out                  ({miss_request_ack_flatted, writeback_request_ack_flatted}),
    
    .request_out                    (to_mem_packet_out),
    .request_valid_out              (),
    .issue_ack_in                   (to_mem_packet_ack_in)
);

wire  [NUM_INPUT_PORT * NUM_BANK                     - 1 : 0] return_request_ack_flatted;
wire  [NUM_INPUT_PORT                                - 1 : 0] return_request_ack_packed [NUM_BANK - 1 : 0];
generate
    for(port_index = 0; port_index < NUM_INPUT_PORT; port_index = port_index + 1)
    begin
        for(bank_index = 0; bank_index < NUM_BANK; bank_index = bank_index + 1)
        begin
            assign return_request_ack_packed [bank_index][port_index] =
                   return_request_ack_flatted[port_index * bank_index + bank_index];
        end
    end
endgenerate

generate
    for(port_index = 0; port_index < NUM_INPUT_PORT; port_index = port_index + 1)
    begin

        wire [NUM_BANK - 1 : 0] is_right_port;
        for(bank_index = 0; bank_index < NUM_BANK; bank_index = bank_index + 1)
        begin
            assign is_right_port[bank_index] = return_request_flatted[(bank_index * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_PORT_NUM_LO) +: `UNIFIED_CACHE_PACKET_PORT_ID_WIDTH]
                                                ==
                                                port_index;
        end

        priority_arbiter
        #(
            .NUM_REQUEST(NUM_INPUT_PORT),
            .SINGLE_REQUEST_WIDTH_IN_BITS(UNIFIED_CACHE_PACKET_WIDTH_IN_BITS)
        )
        return_arbiter
        (
            .reset_in                       (reset_in),
            .clk_in                         (clk_in),

            // the arbiter considers priority from right(high) to left(low)
            .request_flatted_in             (return_request_flatted),
            .request_valid_flatted_in       (return_request_valid_flatted | is_right_port),
            .request_critical_flatted_in    (return_request_critical_flatted),
            .issue_ack_out                  (return_request_ack_flatted[(port_index+1) * NUM_BANK -1 : port_index * NUM_BANK]),
            
            .request_out                    (output_packet_flatted_out[(port_index+1) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 :
                                                                           port_index * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS]),
            .request_valid_out              (),
            .issue_ack_in                   (output_packet_ack_flatted_in[port_index])
        );
    end
endgenerate

endmodule