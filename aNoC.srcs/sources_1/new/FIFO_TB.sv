`timescale 1ns/1ns
module test ;

reg       clk   ;
reg       rst_n ;
reg       wr_en ;
reg       rd_en ;
wire  [7:0]  r_data;  // 修复：应该是8位
reg   [7:0]  w_data;  // 修复：应该是8位
wire       full;
wire       empty;

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// 移除自动递增逻辑，改为手动控制以便更灵活的测试

FIFO #(
    .DATA_WIDTH ( 8  ),
    .ADDR_WIDTH ( 8 ),
    .DEPTH      ( 256 ))
    u_FIFO (
    .wr_clk                  ( clk     ),
    .wr_rst_n                ( rst_n   ),
    .wr_en                   ( wr_en      ),
    .w_data                  ( w_data     ),
    .rd_clk                  ( clk     ),
    .rd_rst_n                ( rst_n   ),
    .rd_en                   ( rd_en      ),

    .full                    ( full       ),
    .r_data                  ( r_data     ),
    .empty                   ( empty      )
);

// 数据校验队列
reg [7:0] expected_data[$];
integer error_count = 0;
reg [7:0] exp_data;  // 用于存储期望数据

initial begin
    // 初始化信号
    wr_en = 0;
    rd_en = 0;
    w_data = 0;

    // 复位序列（修复：先低后高）
    rst_n = 0;
    #50;
    rst_n = 1;
    #20;

    $display("========== Test 1: 基本写入测试 ==========");
    // 写入16个数据（填满FIFO）
    repeat(256) begin
        @(posedge clk);
        #1;
        wr_en = 1;
        w_data = w_data + 1;
        expected_data.push_back(w_data);
        $display("Time=%0t: Write data=%d, full=%b", $time, w_data, full);
    end
    @(posedge clk);
    wr_en <= 0;

    $display("\n========== Test 2: FIFO满状态测试 ==========");
    // 尝试再写入（应该失败）
    @(posedge clk);
    #1
    wr_en = 1;
    w_data = 8'hFF;
    @(posedge clk);
    if(full) $display("PASS: FIFO correctly reports FULL");
    else $display("FAIL: FIFO should be FULL but isn't");
    wr_en = 0;

    #50;
    $display("\n========== Test 3: 基本读取测试 ==========");
    // 读取所有数据
    repeat(256) begin
        
        @(posedge clk);  // 先置 rd_en，再等时钟沿
        #1;
        rd_en = 1;
        if(expected_data.size() > 0) begin
            exp_data = expected_data.pop_front();
            if(r_data !== exp_data) begin
                $display("FAIL: Time=%0t, Expected=%d, Got=%d", $time, exp_data, r_data);
                error_count++;
            end else begin
                $display("PASS: Time=%0t, Read data=%d", $time, r_data);
            end
        end
    end
    @(posedge clk);#1;
    rd_en <= 0;


    $display("\n========== Test 4: FIFO空状态测试 ==========");
    @(posedge clk);
    if(empty) $display("PASS: FIFO correctly reports EMPTY");
    else $display("FAIL: FIFO should be EMPTY but isn't");

    #50;
    $display("\n========== Test 5: 读中断后继续读测试 ==========");
    // 写入8个数据
    repeat(8) begin
        @(posedge clk);
        #1;
        wr_en = 1;
        w_data = w_data + 1;
        expected_data.push_back(w_data);
    end
    @(posedge clk);#1;
    wr_en <= 0;

    // 读4个
    repeat(4) begin
        @(posedge clk);  // 先置 rd_en，再等时钟沿
        #1;
        rd_en = 1;
        exp_data = expected_data.pop_front();
        $display("Read-1: data=%d (expected=%d)", r_data, exp_data);
    end
    @(posedge clk);  // 先置 rd_en，再等时钟沿
    #1;
    rd_en = 0;

    // 中断2个周期
    repeat(2) @(posedge clk);

    // 继续读剩余4个（应该顺序正确）
    repeat(4) begin
        @(posedge clk);  // 先置 rd_en，再等时钟沿
        #1;
        rd_en = 1;
        exp_data = expected_data.pop_front();

        if(r_data !== exp_data) begin
            $display("FAIL: After pause, Expected=%d, Got=%d", exp_data, r_data);
            error_count++;
        end else begin
            $display("PASS: After pause, Read data=%d", r_data);
        end
    end
    @(posedge clk);  // 先置 rd_en，再等时钟沿
    #1;
    rd_en <= 0;
    #50;
    $display("\n========== Test 6: 同时读写测试 ==========");
    fork
        // 写入线程
        begin
            repeat(10) begin
                @(posedge clk);
                #1;
                wr_en = 1;
                w_data = w_data + 1;
                expected_data.push_back(w_data);
            end
            wr_en <= 0;
        end
        // 读取线程（延迟2个周期开始）
        begin
            repeat(4) @(posedge clk);
            repeat(10) begin
                #1;rd_en = 1;
                if(expected_data.size() > 0) begin
                    exp_data = expected_data.pop_front();
                    if(r_data !== exp_data) error_count++;
                end
                 @(posedge clk);  // 先置 rd_en，再等时钟沿
            end
            rd_en = 0;
            exp_data = expected_data.pop_front();
        end
    join

    #100;
    $display("\n========================================");
    $display("Test Complete!");
    $display("Total Errors: %0d", error_count);
    if(error_count == 0) $display("ALL TESTS PASSED!");
    else $display("SOME TESTS FAILED!");
    $display("========================================");

    $finish;
end


endmodule