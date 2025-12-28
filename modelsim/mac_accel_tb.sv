`timescale 1ps/1ps

/* Interface: Keeps Arrays for clean Verification Environment */
interface mult_if(input logic CLK, input logic reset_n);
	logic [3:0][15:0] mac_vectA;
	logic [3:0][15:0] mac_vectB;
	logic EN_mac, EN_blockRead;

	logic RDY_mac, VALID_memVal, RDY_blockRead;

	logic [33:0] memVal_data;

	logic [5:0]  writeMem_addr, readMem_addr;
	logic [33:0] writeMem_val, readMem_val;
	logic EN_writeMem, EN_readMem;
endinterface

/* Transaction objects */
class mult_item;
	rand bit [3:0][15:0] mac_vectA;
	rand bit [3:0][15:0] mac_vectB;
	bit EN_mac, EN_blockRead;
	bit RDY_mac, VALID_memVal;
	bit [33:0] memVal_data;

	/* Extra verification information */
	bit [33:0] expected;
	int cycle_issued;
	int cycle_written;
	logic [5:0] addr;

	bit is_read = 0;
	bit is_read_start = 0;

	function void print_write (string tag="");
		if (is_read) begin
			$display("T=%5t %s %s read", $time, tag, (is_read_start) ? "starting" : "driving");
		end else begin
			$display ("T=%5t %s A={%0d,%0d,%0d,%0d} B={%0d,%0d,%0d,%0d}",
				$time, tag,
				mac_vectA[0], mac_vectA[1], mac_vectA[2], mac_vectA[3],
				mac_vectB[0], mac_vectB[1], mac_vectB[2], mac_vectB[3]);
		end
	endfunction
endclass

/* Generator */
class generator;
	mailbox drv_mbx;
	event drv_done;
	int num = 64;
	virtual mult_if vif;

	bit rand_val = 0;
	bit last = 0;

	task run();
		$display ("T=%5t [Generator] Has Started", $time);

		/* First tests will assume back to back writes */
		simple_write();
		generate_read();
		simple_write();
		generate_read();

		 /* One more with a wait in between */
		$display ("T=%5t [Generator] Started Delayed Simple Test", $time);
		#2000;
		simple_write();
		#2000;
		generate_read();

		/* Randomized multiplicants test */
		 $display ("T=%5t [Generator] Started Simple Random Test", $time);
		random_write();
		generate_read();

		/* Last tests do not assume back to back writes */
		$display ("T=%5t [Generator] Started CRV Test", $time);
		random_write_complex();
		generate_read();

		$display ("T=%5t [Generator] Has Completed!!!!!!!", $time);
	endtask

	task simple_write();
		for (int i = 0; i < num; i++) begin
			mult_item item = new;
			// Simple predictable pattern
			foreach(item.mac_vectA[k]) item.mac_vectA[k] = i;
			foreach(item.mac_vectB[k]) item.mac_vectB[k] = 1;
			item.EN_mac = 1;
			$display ("T=%5t [Generator] Loop:%0d/%0d create next item", $time, i+1, num);
			drv_mbx.put(item);
			@(drv_done);
		end
		$display ("T=%5t [Generator] Done generation of %0d items", $time, num);
	endtask

	task random_write();
		for (int i = 0; i < num; i++) begin
			mult_item item = new;
			foreach(item.mac_vectA[k]) item.mac_vectA[k] = $urandom;
			foreach(item.mac_vectB[k]) item.mac_vectB[k] = $urandom;
			item.EN_mac = 1;
			$display ("T=%5t [Generator] Loop:%0d/%0d create next item", $time, i+1, num);
			drv_mbx.put(item);
			@(drv_done);
		end
		$display ("T=%5t [Generator] Done generation of %0d items", $time, num);
	endtask

	task random_write_complex();
		rand_val = 1;
		for (int i = 0; i < num; i+=last) begin
			mult_item item = new;
			last = rand_val;
			rand_val = $urandom;
			foreach(item.mac_vectA[k]) item.mac_vectA[k] = $urandom;
			foreach(item.mac_vectB[k]) item.mac_vectB[k] = $urandom;
			item.EN_mac = rand_val;
			if (last)
				$display ("T=%5t [Generator] Loop:%0d/%0d create next item", $time, i+1, num);
			else
				$display ("T=%5t [Generator] Loop:%0d/%0d created no write", $time, i+1, num);
			drv_mbx.put(item);
			@(drv_done);
		end
		$display ("T=%5t [Generator] Done generation of %0d items", $time, num);
	endtask

	task generate_read();
		mult_item item = new;
		item.EN_blockRead = 1'b1;
		item.is_read = 1'b1;
		item.is_read_start = 1'b1;
		@(vif.RDY_blockRead);
		$display ("T=%5t [Generator] Read Begin", $time);
		drv_mbx.put(item);
		@(drv_done);
		for (int i = 0; i < num; i++) begin
			mult_item item = new;
			item.is_read = 1'b1;
			item.EN_blockRead = 1'b0;
			drv_mbx.put(item);
			@(drv_done);
		end
		#2000;
	endtask
endclass

/* Driver */
class driver;
	virtual mult_if vif;
	event drv_done;
	mailbox drv_mbx;

	task run();
		$display ("T=%5t [Driver] starting ...", $time);
		@ (posedge vif.CLK);
		forever begin
			mult_item item;

			//$display ("T=%5t [Driver] waiting for item ...", $time);
			drv_mbx.get(item);

			#500;
			item.print_write("[Driver]");
			/* Drive after quarter clock cycle to simulate input delay*/
			vif.EN_mac <= item.EN_mac;
			vif.EN_blockRead <= item.EN_blockRead;
			// Driver assigns to interface arrays
			vif.mac_vectA 	<= item.mac_vectA;
			vif.mac_vectB 	<= item.mac_vectB;

			@ (posedge vif.CLK);
			->drv_done;
		end
	endtask
endclass

/* Monitor */
class monitor;
	virtual mult_if vif;
	mailbox scb_mbx;
	semaphore sema4;

	function new ();
		sema4 = new(1);
	endfunction

	int cycle_count_read = 0;
	int cycle_count_mult = 0;
	int cycle_count_req = 0;
	bit accepting;
	bit [1:0] last_val_read = 0;
	bit [5:0] actual_addr;

	task run();
		fork
			run_req();
			run_read();
			run_mult();
		join
	endtask

	/* Reads any requests, with half a clock cycle of input delay, requests are readable @posedge */
	task run_req();
		$display("T=%5t [Monitor] requests starting...", $time);
		forever begin
			@(posedge vif.CLK);
			cycle_count_req++;

			if (vif.EN_mac & vif.RDY_mac) begin
				mult_item req_evt = new;
				req_evt.mac_vectA = vif.mac_vectA;
				req_evt.mac_vectB = vif.mac_vectB;

				// Calculate Expected MAC
				req_evt.expected = (vif.mac_vectA[0] * vif.mac_vectB[0]) +
								   (vif.mac_vectA[1] * vif.mac_vectB[1]) +
								   (vif.mac_vectA[2] * vif.mac_vectB[2]) +
								   (vif.mac_vectA[3] * vif.mac_vectB[3]);

				req_evt.cycle_issued = cycle_count_req;
				req_evt.addr = 'x;
				req_evt.cycle_written = -1;
				sema4.get();
				scb_mbx.put(req_evt);
				sema4.put();
				$display("T=%5t [Monitor] captured MAC request. Exp Sum=%0d", $time, req_evt.expected);
			end
		end
	endtask

	/*Reads multiplicated values, waits for combinational delay, stable within 1/4 clock cycle so wait 1/2 clock cycle*/
	task run_mult();
		$display("T=%5t [Monitor] writes starting...", $time);
		forever begin
			@(posedge vif.CLK);
			#1900;
			cycle_count_mult++;
			if (vif.EN_writeMem) begin
				mult_item write_evt = new;
				write_evt.addr = vif.writeMem_addr;
				write_evt.expected = vif.writeMem_val;
				write_evt.cycle_written = cycle_count_mult;
				sema4.get();
				scb_mbx.put(write_evt);
				sema4.put();
				$display("T=%5t [Monitor] captured write @addr %0d, val=%0d", $time, vif.writeMem_addr, vif.writeMem_val);
			end
		end
	endtask

	/*Reads values back from memory, waits for combinational delay, stable within 1/4 clock cycle*/
	task run_read();
		$display("T=%5t [Monitor] read starting...", $time);
		forever begin
			@(posedge vif.CLK);
			#1900;
			cycle_count_read++;
			if (vif.VALID_memVal) begin
				mult_item read_evt = new;
				if (last_val_read) begin
					actual_addr = (last_val_read == 2) ? 'd62 : 'd63;
					last_val_read--;
				end else begin
					actual_addr = vif.readMem_addr - 2'd2;
					last_val_read = (vif.readMem_addr == 6'd63) ? 2 : 0;
				end

				read_evt.addr = actual_addr;
				read_evt.memVal_data = vif.memVal_data;
				read_evt.is_read = 1'b1;
				read_evt.RDY_mac = vif.RDY_mac;
				sema4.get();
				scb_mbx.put(read_evt);
				sema4.put();
				$display("T=%5t [Monitor] captured read @addr %0d, val=%0d", $time, actual_addr, vif.memVal_data);
			end
		end
	endtask
endclass

/* Scoreboard */
 class scoreboard;
 	mailbox scb_mbx;
 	int PIPELINE_DELAY = 6;

 	bit [33:0] expected_mem [0:63];
 	int time_saved [0:63];
 	bit [5:0] write_index = 0;
	bit [5:0] read_index = 0;
 	int pass_count = 0, fail_count = 0;

 	task run();
 		$display("T=%5t [Scoreboard] starting...", $time);
		forever begin
 			mult_item trans;
 			scb_mbx.get(trans);

 			if (trans.is_read) begin
				if (read_index === trans.addr)
 					pass_count++;
				else begin
 					$error("[Scoreboard] READ ADDR MISMATCH @addr %0d: exp=%0d, got=%0d", read_index, read_index, trans.addr);
 					fail_count++;
				end

				if (expected_mem[read_index] === trans.memVal_data)
 					pass_count++;
				else begin
 					$error("[Scoreboard] READ MISMATCH @addr %0d: exp=%0d, got=%0d", read_index, expected_mem[read_index], trans.memVal_data);
 					fail_count++;
				end

 				if (read_index == 6'd63) begin
					if (!trans.RDY_mac) begin
						$error("[Scoreboard] RDY AFTER READ MISTIME @addr %0d", read_index);
						fail_count ++;
					end
 				end else begin
					if (trans.RDY_mac) begin
						$error("[Scoreboard] RDY AFTER READ MISTIME @addr %0d", read_index);
						fail_count++;
					end
				end
				read_index++;
			end
 			/* When a new MAC is issued */
 			 else if (trans.cycle_written == -1) begin
 				expected_mem[write_index] = trans.expected;
				time_saved[write_index] = trans.cycle_issued;
 				write_index++;
 			end
 			/* When a MAC result is written to memory */
 			else if (trans.cycle_written >= 0 && trans.addr < 64) begin
 				bit [33:0] exp_val = expected_mem[trans.addr];
				int total_time = trans.cycle_written - time_saved[trans.addr] + 2;

				if (exp_val === trans.expected)
 					pass_count++;
				else begin
 					$error("[Scoreboard] WRITE MISMATCH @addr %0d: exp=%0d, got=%0d", trans.addr, exp_val, trans.expected);
 					fail_count++;
 				end

 				if (total_time === (PIPELINE_DELAY))
 					pass_count++;
				else begin
 					$error("[Scoreboard] WRITE TIME MISMATCH @addr %0d: written=%0d, issued=%0d", trans.addr, trans.cycle_written, time_saved[trans.addr]);
 					fail_count++;
 				end
 			end
 		end
 	endtask
 endclass

/* Environment */
class env;
	driver 		d0;
	monitor 	m0;
	generator	g0;
	scoreboard	s0;

	mailbox 	drv_mbx;
	mailbox 	scb_mbx;
	event 		drv_done;
	virtual mult_if vif;

	function new();
		d0 = new;
		m0 = new;
		g0 = new;
		s0 = new;
		drv_mbx = new();
		scb_mbx = new();

		d0.drv_mbx = drv_mbx;
		g0.drv_mbx = drv_mbx;
		m0.scb_mbx = scb_mbx;
		s0.scb_mbx = scb_mbx;

		d0.drv_done = drv_done;
		g0.drv_done = drv_done;
	endfunction

	virtual task run();
		d0.vif = vif;
		g0.vif = vif;
		m0.vif = vif;

		fork
			d0.run();
			m0.run();
			g0.run();
			s0.run();
		join_any
	endtask
endclass

module mac_accel_tb;

	logic CLK, reset_n;
	mult_if mult_vif(CLK, reset_n);

	initial begin
		CLK = 0;
		#5000;
		forever #1000 CLK = ~CLK;
	end
	wire [33:0] delayed_readMem_val;

	assign #500 delayed_readMem_val = mult_vif.readMem_val;	
	/* DUT Connection: Manually map Interface Arrays to DUT Discrete signals */
	mac_accel  mac_accel (
		.mac_vectA_0(mult_vif.mac_vectA[0]),
		.mac_vectB_0(mult_vif.mac_vectB[0]),
		.mac_vectA_1(mult_vif.mac_vectA[1]),
		.mac_vectB_1(mult_vif.mac_vectB[1]),
		.mac_vectA_2(mult_vif.mac_vectA[2]),
		.mac_vectB_2(mult_vif.mac_vectB[2]),
		.mac_vectA_3(mult_vif.mac_vectA[3]),
		.mac_vectB_3(mult_vif.mac_vectB[3]),

		.EN_mac(mult_vif.EN_mac),
		.EN_blockRead(mult_vif.EN_blockRead),
		.CLK(CLK),
		.RST_N(reset_n),
		.RDY_mac(mult_vif.RDY_mac),
		.VALID_memVal(mult_vif.VALID_memVal),
		.RDY_blockRead(mult_vif.RDY_blockRead),
		.memVal_data(mult_vif.memVal_data),
		.readMem_val(delayed_readMem_val),
		.EN_writeMem(mult_vif.EN_writeMem),
		.EN_readMem(mult_vif.EN_readMem),
		.writeMem_addr(mult_vif.writeMem_addr),
		.readMem_addr(mult_vif.readMem_addr),
		.writeMem_val(mult_vif.writeMem_val)
	);

	memory_wrapper_2port #( .WIDTH(34)) mem_wrap (
		.clkA(mult_vif.CLK),
		.aA(mult_vif.readMem_addr),
		.cenA(~mult_vif.EN_readMem),
		.q(mult_vif.readMem_val),
		.clkB(mult_vif.CLK),
		.aB(mult_vif.writeMem_addr),
		.cenB(~mult_vif.EN_writeMem),
		.d(mult_vif.writeMem_val)
	);

	env e0;

	initial begin
		reset_n = 1'b0;
		mult_vif.EN_mac = 1'b0;
		mult_vif.EN_blockRead = 1'b0;
		mult_vif.mac_vectA = '0;
		mult_vif.mac_vectB = '0;

		repeat(3) @(posedge CLK);
		#100; reset_n = 1'b0;
		repeat(3) @(posedge CLK);
		#100; reset_n = 1'b1;
		@(posedge CLK);
		e0 = new();
		e0.vif = mult_vif;
		e0.run();

		#10000;
		$display("RUNNING HAS COMPLETED. TESTS %s, %0d/%0d Failed", (e0.s0.fail_count) ? "FAILED :(" : "PASSED!", e0.s0.fail_count, e0.s0.fail_count + e0.s0.pass_count);
		$stop;
	end

endmodule
