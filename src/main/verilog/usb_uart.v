module usb_uart (
  input        clk_48mhz,
  input        rstn,

  // USB lines.  Split into input vs. output and oe control signal to maintain
  // highest level of compatibility with synthesis tools.
  output       usb_p_tx,
  output       usb_n_tx,

  input        usb_p_rx,
  input        usb_n_rx,

  output       usb_tx_en,

  // bootloader indicator light, pulses on and off when bootloader is active
  output       led,

  // Fifo used to communicate with system
  input        tx_empty,
  input        rx_full,
  output       tx_read,
  output       rx_write,
  output       rx_err, // Also becomes bit 8 to the fifo
  output [7:0] rx_fifo_wdata,
  input [7:0]  tx_fifo_rdata,
		 // Status
  output [31:0] usb_status
);
  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////
  ////////
  //////// bootloader LED
  ////////
  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////
  reg [7:0] led_pwm = 0;
  reg [7:0] pwm_cnt = 0;

  reg [5:0] ns_cnt = 0;
  wire ns_rst = (ns_cnt == 48);
  always @(posedge clk_48mhz) begin
    if (ns_rst) begin
      ns_cnt <= 0;
    end else begin
      ns_cnt <= ns_cnt + 1'b1;
    end
  end

  reg [9:0] us_cnt = 0;
  wire us_rst = (us_cnt == 1000);
  always @(posedge clk_48mhz) begin
    if (us_rst) begin
      us_cnt <= 0;
    end else if (ns_rst) begin
      us_cnt <= us_cnt + 1'b1;
    end
  end

  reg count_down = 0;
  always @(posedge clk_48mhz) begin
    if (us_rst) begin
      if (count_down) begin
        if (led_pwm == 0) begin
          count_down <= 0;
        end else begin
          led_pwm <= led_pwm - 1'b1;
        end
      end else begin
        if (led_pwm == 255) begin
          count_down <= 1;
        end else begin
          led_pwm <= led_pwm + 1'b1;
        end
      end
    end
  end
  always @(posedge clk_48mhz) pwm_cnt <= pwm_cnt + 1'b1;
  assign led = led_pwm > pwm_cnt;



  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////
  ////////
  //////// usb engine
  ////////
  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////

  wire [6:0] dev_addr;
  wire [7:0] out_ep_data;

  wire ctrl_out_ep_req;
  wire ctrl_out_ep_grant;
  wire ctrl_out_ep_data_avail;
  wire ctrl_out_ep_setup;
  wire ctrl_out_ep_data_get;
  wire ctrl_out_ep_stall;
  wire ctrl_out_ep_acked;

  wire ctrl_in_ep_req;
  wire ctrl_in_ep_grant;
  wire ctrl_in_ep_data_free;
  wire ctrl_in_ep_data_put;
  wire [7:0] ctrl_in_ep_data;
  wire ctrl_in_ep_data_done;
  wire ctrl_in_ep_stall;
  wire ctrl_in_ep_acked;


  wire serial_out_ep_req;
  wire serial_out_ep_grant;
  wire serial_out_ep_data_avail;
  wire serial_out_ep_setup;
  wire serial_out_ep_data_get;
  wire serial_out_ep_stall;
  wire serial_out_ep_acked;

  wire serial_in_ep_req;
  wire serial_in_ep_grant;
  wire serial_in_ep_data_free;
  wire serial_in_ep_data_put;
  wire [7:0] serial_in_ep_data;
  wire serial_in_ep_data_done;
  wire serial_in_ep_stall;
  wire serial_in_ep_acked;

  wire sof_valid;
  wire [10:0] frame_index;

  reg [31:0] host_presence_timer = 0;
  reg host_presence_timeout = 0;
  reg seen_sof = 0;

   assign usb_status = {9'b0, dev_addr,
			seen_sof, host_presence_timeout, 3'b0, frame_index};

  usb_serial_ctrl_ep ctrl_ep_inst (
    .clk(clk_48mhz),
    .reset(~rstn),
    .dev_addr(dev_addr),

    // out endpoint interface
    .out_ep_req(ctrl_out_ep_req),
    .out_ep_grant(ctrl_out_ep_grant),
    .out_ep_data_avail(ctrl_out_ep_data_avail),
    .out_ep_setup(ctrl_out_ep_setup),
    .out_ep_data_get(ctrl_out_ep_data_get),
    .out_ep_data(out_ep_data),
    .out_ep_stall(ctrl_out_ep_stall),
    .out_ep_acked(ctrl_out_ep_acked),


    // in endpoint interface
    .in_ep_req(ctrl_in_ep_req),
    .in_ep_grant(ctrl_in_ep_grant),
    .in_ep_data_free(ctrl_in_ep_data_free),
    .in_ep_data_put(ctrl_in_ep_data_put),
    .in_ep_data(ctrl_in_ep_data),
    .in_ep_data_done(ctrl_in_ep_data_done),
    .in_ep_stall(ctrl_in_ep_stall),
    .in_ep_acked(ctrl_in_ep_acked)
  );

  usb_serial_fifo_ep usb_uart_fifo_ep_inst (
    .clk(clk_48mhz),
    .rstn(rstn),
    .us_tick(ns_rst),
    // out endpoint interface
    .out_ep_req(serial_out_ep_req),
    .out_ep_grant(serial_out_ep_grant),
    .out_ep_data_avail(serial_out_ep_data_avail),
    .out_ep_setup(serial_out_ep_setup),
    .out_ep_data_get(serial_out_ep_data_get),
    .out_ep_data(out_ep_data),
    .out_ep_stall(serial_out_ep_stall),
    .out_ep_acked(serial_out_ep_acked),

    // in endpoint interface
    .in_ep_req(serial_in_ep_req),
    .in_ep_grant(serial_in_ep_grant),
    .in_ep_data_free(serial_in_ep_data_free),
    .in_ep_data_put(serial_in_ep_data_put),
    .in_ep_data(serial_in_ep_data),
    .in_ep_data_done(serial_in_ep_data_done),
    .in_ep_stall(serial_in_ep_stall),
    .in_ep_acked(serial_in_ep_acked),

    // fifo interface
    .tx_empty(tx_empty),
    .rx_full(rx_full),
    .tx_read(tx_read),
    .rx_write(rx_write),
    .rx_err(rx_err), // Also becomes bit 8 to the fifo
    .rx_fifo_wdata(rx_fifo_wdata),
    .tx_fifo_rdata(tx_fifo_rdata)
  );

  wire nak_in_ep_grant;
  wire nak_in_ep_data_free;
  wire nak_in_ep_acked;

  usb_fs_pe #(
    .NUM_OUT_EPS(5'd2),
    .NUM_IN_EPS(5'd3)
  ) usb_fs_pe_inst (
    .clk(clk_48mhz),
    .reset(~rstn),

    .usb_p_tx(usb_p_tx),
    .usb_n_tx(usb_n_tx),
    .usb_p_rx(usb_p_rx),
    .usb_n_rx(usb_n_rx),
    .usb_tx_en(usb_tx_en),

    .dev_addr(dev_addr),

    // out endpoint interfaces
    .out_ep_req({serial_out_ep_req, ctrl_out_ep_req}),
    .out_ep_grant({serial_out_ep_grant, ctrl_out_ep_grant}),
    .out_ep_data_avail({serial_out_ep_data_avail, ctrl_out_ep_data_avail}),
    .out_ep_setup({serial_out_ep_setup, ctrl_out_ep_setup}),
    .out_ep_data_get({serial_out_ep_data_get, ctrl_out_ep_data_get}),
    .out_ep_data(out_ep_data),
    .out_ep_stall({serial_out_ep_stall, ctrl_out_ep_stall}),
    .out_ep_acked({serial_out_ep_acked, ctrl_out_ep_acked}),

    // in endpoint interfaces
    .in_ep_req({1'b0, serial_in_ep_req, ctrl_in_ep_req}),
    .in_ep_grant({nak_in_ep_grant, serial_in_ep_grant, ctrl_in_ep_grant}),
    .in_ep_data_free({nak_in_ep_data_free, serial_in_ep_data_free, ctrl_in_ep_data_free}),
    .in_ep_data_put({1'b0, serial_in_ep_data_put, ctrl_in_ep_data_put}),
    .in_ep_data({8'b0, serial_in_ep_data[7:0], ctrl_in_ep_data[7:0]}),
    .in_ep_data_done({1'b0, serial_in_ep_data_done, ctrl_in_ep_data_done}),
    .in_ep_stall({1'b0, serial_in_ep_stall, ctrl_in_ep_stall}),
    .in_ep_acked({nak_in_ep_acked, serial_in_ep_acked, ctrl_in_ep_acked}),

    // sof interface
    .sof_valid(sof_valid),
    .frame_index(frame_index)
  );



  ////////////////////////////////////////////////////////////////////////////////
  // host presence detection
  ////////////////////////////////////////////////////////////////////////////////

  always @(posedge clk_48mhz) begin
     if (~rstn) begin
	seen_sof <= 0;
     end
    if (sof_valid) begin
      host_presence_timer <= 0;
      host_presence_timeout <= 0;
       seen_sof <= 1;
    end else begin
      host_presence_timer <= host_presence_timer + 1;
    end

    if (host_presence_timer > 48000000) begin
      host_presence_timeout <= 1;
    end
  end
endmodule
