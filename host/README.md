# Pi-Radio MATLAB Realtime & Non-Realtime Drivers
This project is a direct extension of the non real-time drivers from the 8ch-if project.

## Dependencies
This project is tested on MATLAB R2023b.

## Real-time Driver Updates
The `FullyDigital` class has been updated with the following real-time control methods. They are used to configure the correction parameters, set operations mode in the RFSoC.

```m
function status = configure_realtime(obj, tx_rx_mode)
% writes fractional delay filter coeffs

% writes gain correction filter coeffs

% writes phase correction factors

% writes opmode, fir reload
end

function status = disable_realtime(obj)
% write opmode
end
```

### Usage
```m
sdr1 = piradio.sdr.FullyDigital('ip', "192.168.137.43", ...
    'isDebug', isDebug, 'figNum', 100, 'name', 'sdr1');

sdr1.fpga.configure('../../config/rfsoc_nyquist.cfg');

sdr1.calRxArray();
sdr1.calTxArray();

% TX mode
sdr1.configure_realtime(0);

% RX mode
sdr1.configure_realtime(1);

% switch back to calibration mode
sdr1.disable_realtime();
```

The RFSoC always boots up with calibration mode as default. The host can switch to correction mode after the calibration by calling the `configure_realtime` method. 