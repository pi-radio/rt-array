# Pi-Radio MATLAB Realtime & Non-Realtime Drivers
This project is a direct extension of the non real-time drivers from the 8ch-if project.

## Dependencies
This project is tested on MATLAB R2023b.

## Real-time Driver Updates
The `FullyDigital` class has been updated with the following real-time control methods. They are used to configure the correction parameters, set operations mode in the RFSoC.

```m
function status = configure_realtime(obj, is_debug)
% is_debug = false:
%   Load the calibrated fractional-delay and phase-correction values.
%   The gain-correction FIR coefficients are intentionally left empty.
%
% is_debug = true:
%   Load unity filters and unity phase factors for datapath testing.
%
% The method configures both TX and RX, reloads the FIR filters, enables
% correction mode, and returns 0 after issuing the configuration commands.
end

function status = disable_realtime(obj)
% Return the FPGA datapath to calibration/bypass mode.
end
```

### Usage
```m
sdr1 = piradio.sdr.FullyDigital('ip', "192.168.137.43", ...
    'isDebug', isDebug, 'figNum', 100, 'name', 'sdr1');

sdr1.fpga.configure('../../config/rfsoc_nyquist.cfg');

sdr1.calRxArray();
sdr1.calTxArray();

% load calibrated coeffs and switch to correction mode
sdr1.configure_realtime(false);

% Switch back to calibration mode.
sdr1.disable_realtime();
```

The RFSoC always boots up with calibration mode as default. The host can switch to correction mode after the calibration by calling the `configure_realtime` method. 