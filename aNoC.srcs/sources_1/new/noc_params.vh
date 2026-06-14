`ifndef NoC_PARAM_VH
`define NoC_PARAM_VH
/*
Bit位置  |  字段        |  位宽  |  说明
---------|-------------|--------|------------------
[127:126]| FLIT_TYPE   | 2 bit  | 00=HEAD, 01=BODY, 10=TAIL, 11=HEAD_TAIL
[125:124]| DEST_X      | 2 bit  | 目标X坐标 (0-3)
[123:122]| DEST_Y      | 2 bit  | 目标Y坐标 (0-3)
[121:120]| SRC_X       | 2 bit  | 源X坐标 (0-3)
[119:118]| SRC_Y       | 2 bit  | 源Y坐标 (0-3)
[117:114]| PACKET_ID   | 4 bit  | 数据包ID (0-15)
[113:110]| FLIT_NUM    | 4 bit  | Flit数量 (1-16)
[109:96] | RESERVED    | 14 bit | 保留字段
[95:0]   | PAYLOAD     | 96 bit | 有效载荷 (12字节)
---------|-------------|--------|------------------
         总计           128 bit   16字节  
*/
// ========= 网络拓扑参数 ========
`define MESH_SIZE_X     4
`define MESH_SIZE_Y     4
`define COORD_WIDTH     2

`define FLIT_WIDTH      128
`define PAYLOAD_WIDTH   96
`define FLIT_TYPE_WIDTH  2
// ======== Flit字段位置 ========
`define FLIT_TYPE_RANGE   127:126
`define DEST_X_RANGE      125:124
`define DEST_Y_RANGE      123:122
`define SRC_X_RANGE       121:120
`define SRC_Y_RANGE       119:118
`define PACKET_ID_RANGE   117:114    //16个并发包，2^4[117:114]
`define FLIT_NUM_RANGE    113:110    //[113:110] 1-16个flit   
`define RESERVED_RANGE    109:96
`define PAYLOAD_RANGE     95 : 0    //[95:0] 12个字节 

// ======== Flit类型编码 =========
`define FLIT_TYPE_HEAD      2'b00
`define FLIT_TYPE_BODY      2'b01
`define FLIT_TYPE_TAIL      2'b10
`define FLIT_TYPE_HEAD_TAIL 2'b11

// ======== 端口定义 =========
`define NUM_PORTS           5

// 端口索引（用于数组索引）
`define PORT_LOCAL          0
`define PORT_EAST           1
`define PORT_WEST           2
`define PORT_NORTH          3
`define PORT_SOUTH          4

// 独热码编码（用于路由请求和授权信号）
`define ONEHOT_LOCAL        5'b00001
`define ONEHOT_EAST         5'b00010
`define ONEHOT_WEST         5'b00100
`define ONEHOT_NORTH        5'b01000
`define ONEHOT_SOUTH        5'b10000

`endif 