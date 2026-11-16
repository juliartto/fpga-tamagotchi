# ModelSim / Questa: dentro da pasta sim, execute "do run.do"
vlib work
vcom -93 ../src/pet_pkg.vhd
vcom -93 ../src/pet_core.vhd
vcom -93 tb_pet_core.vhd
vsim work.tb_pet_core
add wave -divider Entradas
add wave /tb_pet_core/clk /tb_pet_core/rst /tb_pet_core/tick
add wave /tb_pet_core/btn_feed /tb_pet_core/btn_play /tb_pet_core/btn_sleep /tb_pet_core/btn_med
add wave -divider Jogo
add wave /tb_pet_core/state /tb_pet_core/mood /tb_pet_core/alert
add wave /tb_pet_core/stage
add wave -radix unsigned /tb_pet_core/stats /tb_pet_core/age
run -all
wave zoom full
