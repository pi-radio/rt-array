%% Add the folder containing +piradio to the MATLAB path.
addpath('../../');

% Parameters
ip = "192.168.137.43";	% IP Address
isDebug = false;		% print debug messages

% Create a Fully Digital SDR
sdr0 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, ...
    'figNum', 100, 'name', 'v3-revB-0001');

% Configure the RFSoC. Use the file corresponding to the desired frequency
sdr0.fpga.configure('../../config/rfsoc_nyquist.cfg');


 %% Simple TX and RX test with a single channel

 % txChId = 1 refers to the TX channel that's used to self-cal the RX array
 % txChId = 2..8 refer to the regular TX channels
 % rxChId = 1 refers to the RX channel that's used to self-cal the TX array
 % rxChId = 2..8 refer to the regular RX channels


txChId = 1;

clc;
nFFT = 1024;	% number of FFT points
txPower = 30000; % Do not exceed 30000
scMin = 100;
scMax = 100;
constellation = [1+1j 1-1j -1+1j -1-1j];

txtd = zeros(nFFT, sdr1.nch);       
txfd = zeros(nFFT, sdr1.nch);

for scIndex = scMin:scMax
    if scIndex == 0
        continue;
    end
    txfd(nFFT/2 + 1 + scIndex, txChId) = constellation(randi(4));
end

txfd(:, txChId) = fftshift(txfd(:, txChId));
txtd(:, txChId) = ifft(txfd(:, txChId));
txtd(:, txChId) = txPower*txtd(:, txChId)./max(abs(txtd(:, txChId)));

        
% Send the data to the DACs
sdr1.send(txtd);

% Receive data
nskip = 1024*3;	% skip ADC data
nbatch = 100;	% num of batches
rxtd = sdr1.recv(nFFT, nskip, nbatch, 1);

