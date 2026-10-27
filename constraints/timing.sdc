create_clock -name ref_clk -period 20 [get_ports clk]
derive_clocks
set_clock_uncertainty -setup 0.15 [all_clocks]
set_clock_uncertainty -hold 0.05 [all_clocks]
# Pixel and serializer clocks are RELATED and simultaneously active.
# Only first-stage synchronizers and held mailbox payloads cross async domains.
set_false_path -to [get_regs -nowarn {*u_fifo/rg1* *u_fifo/wg1* *req_sync* *ack_sync* *u_cache/req_sync*}]
set_false_path -from [get_regs -nowarn {*u_status/held* *u_rescan/held*}]
set_false_path -from [get_regs -nowarn {*frame_request* *display_slot* *fetch_enable*}] -to [get_regs -nowarn {*u_cache/read_base* *u_cache/read_slot* *u_cache/do_fetch*}]
# Asynchronous external switches/UART feed synchronizers. SD is sampled on generated SPI edges.
set_false_path -from [get_ports {rst_n key1 key2 key3 uart_rx}]
create_generated_clock -name sd_spi_clk -source [get_pins {u_sys_pll/pll_inst.clkc[1]}] -divide_by 4 [get_ports sd_dclk]
set_input_delay -clock sd_spi_clk -clock_fall -max 14 [get_ports sd_miso]
set_input_delay -clock sd_spi_clk -clock_fall -min 0 [get_ports sd_miso]
set_output_delay -clock sd_spi_clk -max 5 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock sd_spi_clk -min 0 [get_ports {sd_mosi sd_ncs}]
# SPI advances MOSI only on SCK falling edges and samples MISO two system
# cycles later on SCK rising edges (RUN_HALF=2; initialization is slower).
set_multicycle_path -setup 2 -from [get_ports sd_miso] -to [get_regs -hier -nowarn {*u_sd/u_spi/shift_rx*}]
set_multicycle_path -hold 1 -from [get_ports sd_miso] -to [get_regs -hier -nowarn {*u_sd/u_spi/shift_rx*}]
# Both SPI output flops use this source clock. Limit the exception to these
# two output ports; clock objects remain valid before and after IO packing.
set spi_output_clocks [get_clocks -nowarn -of [get_pins {u_sys_pll/pll_inst.clkc[1]}]]
if {[llength $spi_output_clocks]>0} {
 set_multicycle_path -setup 2 -start -from $spi_output_clocks -to [get_ports {sd_mosi sd_ncs}]
 set_multicycle_path -hold 2 -start -from $spi_output_clocks -to [get_ports {sd_mosi sd_ncs}]
}
# Raw power-on assertion is asynchronous. Functional release uses reset_sync;
# mapped DSP/reset pins that see raw assertion remain inactive until that release.
set raw_reset_pins [get_pins -hier -nowarn {*.sr}]
if {[llength $raw_reset_pins]>0} {
 set_false_path -from [get_regs -hier -nowarn {*power_count*}] -to $raw_reset_pins
}
# FIFO flush/reload asserts asynchronously into three-flop reset synchronizers.
# Only their asynchronous reset pins are exempt; the synchronizer outputs and
# the functional FIFO/register reset paths remain timed for synchronous release.
set fifo_reset_sync_pins [get_pins -hier -nowarn {*u_fifo_rd_rst/pipe*.sr *u_fifo_wr_rst/pipe*.sr}]
puts "FIFO_RESET_ASYNC_PIN_COUNT=[llength $fifo_reset_sync_pins]"
if {[llength $fifo_reset_sync_pins]>0} {
 set_false_path -to $fifo_reset_sync_pins
}
# Human-visible outputs and asynchronous UART have no synchronous receiver clock.
set_false_path -to [get_ports {uart_tx seg_data* seg_sel* led*}]
