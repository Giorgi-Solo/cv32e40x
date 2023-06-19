
////////////////////////////////////////////////////////////////////////////////
// Engineer:       Giorgi Solomnishvili - giorgisolomnishvili349@gmail.com    //
//                                                                            //                                       //
// Design Name:    cv32e40x_BTB_BTH                                           //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module cv32e40x_BTB_BTH import cv32e40x_pkg::*;
#(
    parameter int size  = 256,
    parameter int width = 8
)
(
    input  logic clk,
    input  logic rst_n,

    // inputs/outputs from/to IF stage
    input  logic [31:0] pc_if_i,              // program counter from IF stage
    output logic [31:0] target_pc_if_o,       // address of the branch target instruction send to IF stage
    output logic [1:0]  prediction_cnt_o,     // 2-bit prediction counter
    output logic hit_o,                       // hit is 1 if pc_if corresponds to one of the cachelines

    // inputs from ex stage
    input logic [31:0] pc_ex_i,            // program counter from ex stage
    input logic [31:0] target_pc_ex_i,     // address of the branch target instruction recieved from ex stage
    input cache_cmd cache_operatoin        
);
    // signals for monitoring number of valid entries in cache. 
    int i = 0;
    int fd;
    int num_valid_entries = 0;
    int num_branches, num_predictions, corr_prediction, inccorr_prediction;

    cache_cmd cache_operatoin_r;

    // Cache
    cache_line_t BTB_BHT_cache [size]; 

    // Internal signals
    logic [30 :0] tag;         // tag   taken from current  pc (pc_if_i)
    logic [width - 1  :0] index, pre_index;       // index taken from current  pc (pc_if_i)
    logic [width - 1  :0] index_ex, pre_index_ex;    // index taken from EX stage pc (pc_ex_i)
    cache_line_t cache_line; // cache line corresponding to current pc (pc_if_i)
    
    logic [1:0] prediction_cnt;  

    // logic [31:0] pc_ex_i_r;

    assign tag       = pc_if_i[31    : 1];
    assign pre_index = pc_if_i[width : 1];
    assign index     = pre_index < size ? pre_index : pre_index - size;

    assign pre_index_ex = pc_ex_i[width : 1];
    assign index_ex     = pre_index_ex < size ? pre_index_ex : pre_index_ex - size;
    
    assign cache_line =  BTB_BHT_cache[index];
    
    assign prediction_cnt = BTB_BHT_cache[index_ex].prediction_cnt;

    assign target_pc_if_o = cache_line.target_pc;
    assign prediction_cnt_o = cache_line.prediction_cnt;
    assign hit_o = cache_line.valid & (tag == cache_line.tag);

    
        always_ff @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin                        // make all cache lines invalid
                for(int i = 0; i < size; i++) begin: invalidation
                    BTB_BHT_cache[i].valid <= 1'b0;
                    BTB_BHT_cache[i].prediction_cnt <= '0;
                    BTB_BHT_cache[i].tag            <= '0;
                    BTB_BHT_cache[i].target_pc      <= '0;
                end
                // num_branches <= 0;
            end
            else begin
                case(cache_operatoin)  // update cache
                    INCREMENT: begin   // increment prediction_cnt of the line corresponding to the last predicted branch
                        BTB_BHT_cache[index_ex].prediction_cnt <= {prediction_cnt[1] |   prediction_cnt[0],
                                                                        prediction_cnt[1] | (~prediction_cnt[0])};
                        // num_branches <= num_branches + 1;
                    end
                    DECREMENT: begin   // decrement prediction_cnt of the line corresponding to the last predicted branch
                        BTB_BHT_cache[index_ex].prediction_cnt <= {prediction_cnt[1] &   prediction_cnt[0],
                                                                        prediction_cnt[1] & (~prediction_cnt[0])};
                        // num_branches <= num_branches + 1;
                    end
                    NEW_ENTRY: begin  // add new entry to the cahce
                        BTB_BHT_cache[index_ex].valid          <= 1'b1;
                        BTB_BHT_cache[index_ex].tag            <= pc_ex_i[31 : 1];
                        BTB_BHT_cache[index_ex].target_pc      <= target_pc_ex_i;
                        BTB_BHT_cache[index_ex].prediction_cnt <= 2'b11;

                        // num_branches <= num_branches + 1;
                    end
                endcase
            end
        end

    // THIS PART IS FOR THE SIMULATION ONLY. COMMENT IT OUT FOR SYNTHESIS ####### GS 
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(rst_n == 1'b0) begin
            cache_operatoin_r <= NOP;
            num_branches <= 0;
            num_predictions <= 0;
            corr_prediction <= 0;
        end else begin
            cache_operatoin_r <= cache_operatoin;
            if(((cache_operatoin_r == NOP) && (cache_operatoin != NOP)) || ((cache_operatoin_r == cache_operatoin) && (cache_operatoin != NOP)))begin
            // if(cache_operatoin != NOP) begin
                num_branches <= num_branches + 1;
                if(cache_operatoin != NEW_ENTRY) begin
                    num_predictions <= num_predictions + 1; 
                    if((prediction_cnt[1]) && (cache_operatoin == INCREMENT)) begin
                        corr_prediction <= corr_prediction + 1;
                    end else if((!prediction_cnt[1]) && (cache_operatoin == DECREMENT)) begin
                        corr_prediction <= corr_prediction + 1;
                    end
                end
            end 

            
        end
    end
    
    initial begin
        fd = $fopen("./btb_cache_statistics.txt","w");
        wait(pc_if_i == 32'h00000356);
        
        num_valid_entries = 0;

        for(int i = 0; i < size; i++) begin: invalidation
            num_valid_entries = BTB_BHT_cache[i].valid + num_valid_entries;
        end

        inccorr_prediction = num_predictions - corr_prediction;

        $fdisplay(fd,"size   of BTB_BHT_cache           = %0d entries",size);
        $fdisplay(fd,"width  of BTB_BHT_cache           = %0d bits",width);
        $fdisplay(fd,"number of valid entries           = %0d entries",num_valid_entries);
        $fdisplay(fd,"number of branch instrs           = %0d"        ,num_branches);
        
        $fdisplay(fd,"number of predictions             = %0d",num_predictions);
        $fdisplay(fd,"number of corr predictions        = %0d",corr_prediction);
        $fdisplay(fd,"number of incorr inpredictions    = %0d",inccorr_prediction);


        $display("Closing######################3");
        $fclose(fd);
    end
    

endmodule