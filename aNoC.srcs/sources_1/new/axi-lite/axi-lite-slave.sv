module axi_lite_slave#(
    parameter int N_REG = 16
)(
    input logic     clk,rst_n,
    //写地址AW
    input logic  [7:0] awaddr,input logic awvalid,output logic awready,
    //写数据W
    input logic  [31:0] wdata, input logic [3:0] wstrb,input logic wvalid,output logic wready,
    //写相应B
    output logic [1:0] bresp,output logic bvalid,input logic bready,    
    //读地址AR
    input logic [7:0] araddr,input logic arvalid,output logic arready,
    //读数据R
    output logic [31:0] rdata,output logic [1:0] rresp,output logic rvalid,input logic rready
);
logic [31:0] mem[N_REG];
logic [7:0] awaddr_q;logic [31:0] wdata_q;logic [3:0] wstrb_q;
// ---- 写: 收齐地址+数据 → 写入 → 回 B ----
always_ff @( posedge clk ) begin 
    if(!rst_n)begin
        for(int i = 0;i < N_REG;i++)begin
            mem[i] <= 32'h0;
        end
        awready <= 1;wready <= 1;bvalid <= 0; bresp <= 0;
    end
    else begin
        if(awvalid && awready)begin
            awaddr_q <= awaddr;awready <= 1'b0;
        end
        if(wvalid && wready)begin
            wdata_q <= wdata;wstrb_q <= wstrb;wready <= 1'b0;
        end
        if(!awready && !wready && !bvalid)begin
            for(int i=0;i<4;i++)begin
                if(wstrb_q[i])begin
                    //写入寄存器
                    mem[awaddr_q[5:2]][i*8+:8] <=wdata_q[i*8+:8]; 
                end
            end
            bvalid <= 1'b1;bresp <= 2'b00;
        end
        if(bvalid && bready) begin
            bvalid <= 1'b0;awready <= 1'b1;wready <= 1'b1;
        end
    end
end


//---- 读: 收齐地址 → 读出数据 → 回 R ----
logic [7:0] araddr_q;
always_ff @( posedge clk ) begin 
    if(!rst_n)begin
        arready <= 1'b1;rvalid <= 0; rresp <= 0;
    end
    else begin
        if(arvalid && arready)begin
            araddr_q <= araddr; arready <= 1'b0;
        end
        if(!arready  && !rvalid)begin
            rdata <= mem[araddr_q[5:2]]; rvalid <= 1'b1;rresp <= 2'b00;
        end
        if(rvalid && rready) begin
            rvalid <= 1'b0; arready <= 1'b1;
        end
    end
end
endmodule