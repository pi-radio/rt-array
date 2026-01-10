
# 1024-point FFT, can be used for ifft as well with FWD_INV bit
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name fft_1024
set_property -dict [list \
  CONFIG.aresetn {true} \
  CONFIG.number_of_stages_using_block_ram_for_data_and_phase_factors {3} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.target_data_throughput {250} \
  CONFIG.throttle_scheme {nonrealtime} \
] [get_ips fft_1024]

generate_target all [get_files */fft_1024.xci]

create_ip -name fir_compiler -vendor xilinx.com -library ip -version 7.2 -module_name fracDelayFIR
set_property -dict [list \
  CONFIG.Clock_Frequency {250} \
  CONFIG.CoefficientSource {COE_File} \
  CONFIG.Coefficient_File {fracdelay.coe} \
  CONFIG.Coefficient_Fractional_Bits {0} \
  CONFIG.Coefficient_Sets {1} \
  CONFIG.Coefficient_Sign {Signed} \
  CONFIG.Coefficient_Structure {Inferred} \
  CONFIG.Coefficient_Width {18} \
  CONFIG.ColumnConfig {48,48,48,57} \
  CONFIG.DATA_Has_TLAST {Packet_Framing} \
  CONFIG.Data_Width {16} \
  CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
  CONFIG.Has_ARESETn {true} \
  CONFIG.Output_Rounding_Mode {Full_Precision} \
  CONFIG.Output_Width {42} \
  CONFIG.Quantization {Integer_Coefficients} \
  CONFIG.Sample_Frequency {250} \
  CONFIG.M_DATA_Has_TREADY {true} \
  CONFIG.Coefficient_Reload {true} \
] [get_ips fracDelayFIR]

generate_target all [get_files */fracDelayFIR.xci]
