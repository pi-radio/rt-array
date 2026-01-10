
addpath('../../');
addpath('../../helper');
isDebug = false;		% print debug messages

sdr1 = piradio.sdr.FullyDigital('ip', "192.168.137.43", ...
    'isDebug', isDebug, 'figNum', 100, 'name', 'sdr1');
%sdr2 = piradio.sdr.FullyDigital('ip', "192.168.137.44", ...
%    'isDebug', isDebug, 'figNum', 200, 'name', 'sdr2');

sdr1.fpga.configure('../../config/rfsoc_nyquist.cfg');
%sdr2.fpga.configure('../../config/rfsoc_nyquist.cfg');

clear isDebug;

%% Calibrate both radios
sdr1.calRxArray();
sdr1.calTxArray();

sdr2.calRxArray();
sdr2.calTxArray();