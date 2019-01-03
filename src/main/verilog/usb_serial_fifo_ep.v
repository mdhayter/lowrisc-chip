module usb_serial_fifo_ep
(
  input        clk,
  input        rstn,
  input        us_tick,

  ////////////////////
  // out endpoint interface
  ////////////////////
  // data_avail is set when data is available
  // in response send a req (from all out_ep) to the arbiter
  //  if grant then send data_get (must be 1-hot across all out_ep)
  //  Data is there next edge of clock
  // 	along with internal out_data_valid

  output       out_ep_req,
  input        out_ep_grant,
  input        out_ep_data_avail,
  input        out_ep_setup,
  output       out_ep_data_get,
  input [7:0]  out_ep_data,
  output       out_ep_stall,
  input        out_ep_acked,


  ////////////////////
  // in endpoint interface
  ////////////////////
  // in_ep_data_free is set when data can be transferred
  // in response send a req (from all in_ep) to the arbiter
  //   if grant then send data with data_put (must be 1-hot across all in_ep)
  //   Note the grant is paired with the data mux switching
  // After 32 bytes or in_ep_data_done have to wait for paket to send
  // (Don't get any more in_ep_data_free)
  // in_ep_acked once packet is acked (but may not be needed)

  output reg   in_ep_req = 0,
  input        in_ep_grant,
  input        in_ep_data_free,
  output       in_ep_data_put,
  output [7:0] in_ep_data,
  output reg   in_ep_data_done = 0,
  output       in_ep_stall,
  input        in_ep_acked,


  ////////////////////
  // fifo interface
  ////////////////////
  input        tx_empty,
  input        rx_full,
  output reg   tx_read,
  output       rx_write,
  output reg   rx_err, // Also becomes bit 8 to the fifo
  output [7:0] rx_fifo_wdata,
  input [7:0]  tx_fifo_rdata
);


  assign out_ep_stall = 1'b0;
  assign in_ep_stall = 1'b0;

  ////////////////////////////////////////////////////////////////////////////
  // OUT endpoint (from usb to rx_fifo)
  ////////////////////////////////////////////////////////////////////////////
  assign out_ep_req = out_ep_data_avail;
  // always empty interface fifo, dropped data will give rx_err
  assign out_ep_data_get = out_ep_grant;
  // wire out_data_ready = out_ep_grant && out_ep_data_avail;
  reg out_data_valid = 0;
  always @(posedge clk) out_data_valid <= out_ep_data_get; // out_data_ready;

   assign rx_write = out_data_valid & ~rx_full;
   assign rx_fifo_wdata = out_ep_data;
   // rx_err indicates data loss prior to item it is attached to
   always @(posedge clk) rx_err = (out_data_valid & rx_full) |
				  (rx_err & ~rx_write);

  ////////////////////////////////////////////////////////////////////////////
  // IN endpoint (from tx_fifo to usb)
  ////////////////////////////////////////////////////////////////////////////
   reg [1:0] tx_done_delay;
   reg 	     tx_pend_done;

  assign in_ep_data = tx_fifo_rdata;
  assign in_ep_data_put = in_ep_grant;

  always @(posedge clk)
    if (~rstn)
      begin
	 tx_read <= 0;
	 in_ep_req <= 0;
	 in_ep_data_done <= 0;
	 tx_pend_done <= 0;
      end
    else
      begin
	 // limit to max every other cycle because of empty pipeline
	 // wouldn't need if change to assign and timing works
	 // but running at 4 times the USB bit clock, so it isn't a problem
	 tx_read <= ~tx_empty & in_ep_data_free &
		    ~tx_read & ~(in_ep_req & ~in_ep_grant);
	 in_ep_req <= tx_read | (in_ep_req & ~in_ep_grant);

	 // consider a 4Mb uart, about 0.5us per character
	 // if no character in 3-4us let the data go
	 // endpoint logic will release immediately on a full packet
	 if (in_ep_grant & tx_empty) begin
	    tx_done_delay <= 0;
	    tx_pend_done <= 1;
	 end
	 if (tx_pend_done & tx_empty & us_tick) begin
	    if (tx_done_delay == 2'b11) begin
	       tx_pend_done <= 0;
	       in_ep_data_done <= 1;
	    end else begin
	       tx_done_delay <= tx_done_delay + 1'b1;
	    end
	 end
	 if (in_ep_data_done == 1) begin in_ep_data_done <= 0; end

       end // else: !if(~rstn)

endmodule
