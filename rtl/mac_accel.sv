module mac_accel #(parameter WIDTH = 34)(
	/* User Facing Input*/
	input logic [15:0] 			mac_vectA_0,
	input logic [15:0] 			mac_vectB_0,
	input logic [15:0] 			mac_vectA_1,
	input logic [15:0] 			mac_vectB_1,
	input logic [15:0] 			mac_vectA_2,
	input logic [15:0] 			mac_vectB_2,
	input logic [15:0] 			mac_vectA_3,
	input logic [15:0] 			mac_vectB_3,

	input logic 				EN_mac, EN_blockRead,
	input logic					CLK,
	input logic 				RST_N,

	/* User Facing Output */
	output logic 				RDY_mac, VALID_memVal, RDY_blockRead,
	output logic [WIDTH-1:0] 	memVal_data,

	/* Mem Facing Input */
	input logic [WIDTH-1:0] 	readMem_val,

	/* Mem Facing Output */
	output logic 				EN_writeMem, EN_readMem,
	output logic [5:0]			writeMem_addr, readMem_addr,
	output logic [WIDTH-1:0]	writeMem_val
);


	/* State Machine */
	enum {WAIT, WRITE, READ_WAIT, READ}	state;
	logic [5:0] 		read_addr_next, write_addr_next;
	logic 				handshake;
	logic 				fsm_read_valid;

	/* Pipeline Control */
	localparam PIPE_DEPTH = 6;
	logic [PIPE_DEPTH-3:0] 		write_delay_pipe;
	logic [PIPE_DEPTH-3:0][5:0] write_addr_pipe;

	always_ff @(posedge CLK or negedge RST_N) begin
		if(~RST_N) begin
			RDY_mac <= 1'b0;
			RDY_blockRead <= 1'b0;
			writeMem_addr <= 6'd0;
			readMem_addr <= 6'd0;
			EN_writeMem <= 1'b0;
			fsm_read_valid <= 1'b0;
			EN_readMem <= 1'b0;

			write_addr_pipe <= '0;
			write_delay_pipe <= '0;
			state <= WAIT;
		end else begin
			case(state)
				WAIT: begin
					RDY_mac <= 1'b1;
					EN_readMem <= 1'b0;
					fsm_read_valid <= 1'b0;
					/*Need to log the first handshake in the pipeline during transition*/
					write_delay_pipe <= 1'b1;
					write_addr_pipe <= 'd0;
					EN_writeMem <= 1'b0;
					if (EN_mac) state <= WRITE;
				end

				WRITE:  begin
					/* Control Pipeline Shift (could make modular)*/
					{writeMem_addr, write_addr_pipe[3], write_addr_pipe[2], write_addr_pipe[1], write_addr_pipe[0]}
						<= {write_addr_pipe[3], write_addr_pipe[2], write_addr_pipe[1], write_addr_pipe[0], write_addr_next};
					{EN_writeMem, write_delay_pipe[3], write_delay_pipe[2], write_delay_pipe[1], write_delay_pipe[0]}
						<= {write_delay_pipe[3], write_delay_pipe[2], write_delay_pipe[1], write_delay_pipe[0], handshake};

					if (&write_addr_next) begin
						RDY_mac <= 1'b0;
					end

					if (&writeMem_addr) begin
						writeMem_addr <= 6'd0;
						RDY_blockRead <= 1'b1;
						EN_readMem <= 1'b1;
						state <= (EN_blockRead) ? READ : READ_WAIT;
					end
				end

				READ_WAIT: begin
					if (EN_blockRead) state <= READ;
				end

				READ: begin
					fsm_read_valid <= 1'b1;
					readMem_addr <= read_addr_next;
					if (&readMem_addr) begin
						RDY_blockRead <= 1'b0;
						state <= WAIT;
					end
				end
			endcase
		end
	end
	/* Shepard memory block data sequentially to satisfy tight output constraints */
	always_ff @(posedge CLK or negedge RST_N) begin
		if (~RST_N) begin
			memVal_data  <= 'd0;
			VALID_memVal <= 1'b0;
		end else begin
			memVal_data  <= readMem_val;
			VALID_memVal <= fsm_read_valid;
		end
	end

	//assign EN_readMem = (state == READ);
	assign read_addr_next = readMem_addr + 1'b1;

	always_comb begin
		handshake = (EN_mac & RDY_mac);
		write_addr_next = write_addr_pipe[0] + handshake;
	end



	/* 6-Stage Data Pipeline */

	/* Internal Packing; Group discrete signals into arrays for cleaner pipeline logic, satisfies input delay constraint requirments*/
	logic [3:0][15:0] vectA_packed;
	logic [3:0][15:0] vectB_packed;

	always_comb begin
		vectA_packed[0] = mac_vectA_0; vectB_packed[0] = mac_vectB_0;
		vectA_packed[1] = mac_vectA_1; vectB_packed[1] = mac_vectB_1;
		vectA_packed[2] = mac_vectA_2; vectB_packed[2] = mac_vectB_2;
		vectA_packed[3] = mac_vectA_3; vectB_packed[3] = mac_vectB_3;
	end

/* ==========================================
	STAGE 1: Partial Multiplication
	========================================= */

	// 1. Combinational Logic
	logic [7:0] partials_4bmult [3:0][15:0];

	always_comb begin
		for (int i = 0; i < 4; i++) begin
			// Row 0 (vectA[3:0])
			partials_4bmult[i][0]  = vectA_packed[i][3:0]   * vectB_packed[i][3:0];
			partials_4bmult[i][1]  = vectA_packed[i][3:0]   * vectB_packed[i][7:4];
			partials_4bmult[i][2]  = vectA_packed[i][3:0]   * vectB_packed[i][11:8];
			partials_4bmult[i][3]  = vectA_packed[i][3:0]   * vectB_packed[i][15:12];

			// Row 1 (vectA[7:4])
			partials_4bmult[i][4]  = vectA_packed[i][7:4]   * vectB_packed[i][3:0];
			partials_4bmult[i][5]  = vectA_packed[i][7:4]   * vectB_packed[i][7:4];
			partials_4bmult[i][6]  = vectA_packed[i][7:4]   * vectB_packed[i][11:8];
			partials_4bmult[i][7]  = vectA_packed[i][7:4]   * vectB_packed[i][15:12];

			// Row 2 (vectA[11:8])
			partials_4bmult[i][8]  = vectA_packed[i][11:8]  * vectB_packed[i][3:0];
			partials_4bmult[i][9]  = vectA_packed[i][11:8]  * vectB_packed[i][7:4];
			partials_4bmult[i][10] = vectA_packed[i][11:8]  * vectB_packed[i][11:8];
			partials_4bmult[i][11] = vectA_packed[i][11:8]  * vectB_packed[i][15:12];

			// Row 3 (vectA[15:12])
			partials_4bmult[i][12] = vectA_packed[i][15:12] * vectB_packed[i][3:0];
			partials_4bmult[i][13] = vectA_packed[i][15:12] * vectB_packed[i][7:4];
			partials_4bmult[i][14] = vectA_packed[i][15:12] * vectB_packed[i][11:8];
			partials_4bmult[i][15] = vectA_packed[i][15:12] * vectB_packed[i][15:12];
		end
	end

	// 2. Sequential Logic

	logic [7:0] stage1_regs[3:0][15:0];

	always_ff @(posedge CLK) begin
		if (~RST_N) begin
			for (int i=0; i<4; i++) begin
				for (int y=0; y<16; y++) begin
					stage1_regs[i][y] <= 8'd0;
				end
			end
		end else begin
			for (int i=0; i<4; i++) begin
				for (int y=0; y<16; y++) begin
					stage1_regs[i][y] <= partials_4bmult[i][y];
				end
			end
		end
	end


	/* =========================================
	STAGE 2: First Summation (Shift & Add)
	========================================= */

	// 1. Combinational Logic
	logic [31:0] first_partial_sum [3:0][3:0];

	always_comb begin
		for (int i = 0; i < 4; i++) begin
			first_partial_sum[i][0] = {24'd0, stage1_regs[i][0]} +
									{20'd0, stage1_regs[i][1], 4'd0} +
									{16'd0, stage1_regs[i][2], 8'd0} +
									{12'd0, stage1_regs[i][3], 12'd0};

			first_partial_sum[i][1] = {20'd0, stage1_regs[i][4], 4'd0} +
									{16'd0, stage1_regs[i][5], 8'd0} +
									{12'd0, stage1_regs[i][6], 12'd0} +
									{8'd0,  stage1_regs[i][7], 16'd0};

			first_partial_sum[i][2] = {16'd0, stage1_regs[i][8], 8'd0} +
									{12'd0, stage1_regs[i][9], 12'd0} +
									{8'd0,  stage1_regs[i][10], 16'd0} +
									{4'd0,  stage1_regs[i][11], 20'd0};

			first_partial_sum[i][3] = {12'd0, stage1_regs[i][12], 12'd0} +
									{8'd0,  stage1_regs[i][13], 16'd0} +
									{4'd0,  stage1_regs[i][14], 20'd0} +
									{stage1_regs[i][15], 24'd0};
		end
	end

	// 2. Sequential Logic
	logic [31:0] stage2_regs[3:0][3:0];

	always_ff @(posedge CLK) begin
		if (~RST_N) begin
			for (int i=0; i<4; i++) begin
				for (int y=0; y<4; y++) begin
					stage2_regs[i][y] <= 32'd0;
				end
			end
		end else begin
			for (int i=0; i<4; i++) begin
				for (int y=0; y<4; y++) begin
					stage2_regs[i][y] <= first_partial_sum[i][y];
				end
			end
		end
	end


	/* =========================================
	STAGE 3: Second Summation (Reduce 4 to 1)
	========================================= */

	// 1. Combinational Logic
	logic [31:0] second_partial_sum[3:0];

	always_comb begin
		for (int i = 0; i < 4; i++) begin
			second_partial_sum[i] = stage2_regs[i][0] + stage2_regs[i][1] + stage2_regs[i][2] + stage2_regs[i][3];
		end
	end

	// 2. Sequential Logic
	logic [31:0] stage3_regs[3:0];

	always_ff @(posedge CLK) begin
		if (~RST_N) begin
			for (int i=0; i<4; i++) begin
				stage3_regs[i] <= 32'd0;
			end
		end else begin
			for (int i=0; i<4; i++) begin
				stage3_regs[i] <= second_partial_sum[i];
			end
		end
	end


	/* =========================================
	STAGE 4: Vector Reduction Part 1
	========================================= */

	// 1. Combinational Logic
	wire [32:0] third_partial_sum[1:0];

	assign third_partial_sum[0] = stage3_regs[0] + stage3_regs[1];
	assign third_partial_sum[1] = stage3_regs[2] + stage3_regs[3];

	// 2. Sequential Logic
	logic [32:0] stage4_regs[1:0];

	always_ff @(posedge CLK) begin
		if (~RST_N) begin
			{stage4_regs[1], stage4_regs[0]} <= 'd0;
		end else begin
			{stage4_regs[1], stage4_regs[0]} <= {third_partial_sum[1], third_partial_sum[0]};
		end
	end


	/* =========================================
	STAGE 5: Final Vector Reduction
	========================================= */

	// Sequential Logic
	logic [33:0] stage5_reg;

	always_ff @(posedge CLK) begin
		if (~RST_N) begin
			stage5_reg <= 34'd0;
		end else begin
			stage5_reg <= stage4_regs[0] + stage4_regs[1];
		end
	end

	/* Output */
	assign writeMem_val = stage5_reg;


endmodule
