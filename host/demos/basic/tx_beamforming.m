% In this demo, we assume that sdr1 is open, and are fully
% calibrated. Look at the calibration demo to make sure this is done. In
% the minimum, the timing and phase offsets need to be calibrated.

nFFT = 1024;
nread = nFFT;
nskip = nFFT*5;
ntimes = 50;
txfd = zeros(nFFT, 1);
constellation = [1+1j 1-1j -1+1j -1-1j];

scMin = -20; scMax = 20;

for scIndex = scMin:scMax
    txfd(nFFT/2 + 1 + scIndex) = constellation(randi(4));
end
txfd = fftshift(txfd);
txtd = ifft(txfd);
m = max(abs(txtd));
txtd = txtd / m * 25000;

freq = 3.25e9;
c = physconst('LightSpeed');
lam = c/freq;
nch = 7;
pos = (0:nch-1)*0.5;
%%

% Direction of the desired Beam, in degrees
thetad = 25;
wd = steervec(pos, thetad);
% Direction of the desired NULL, in degrees
thetan = 0;
wn = steervec(pos, thetan);
rn = wn'*wd/(wn'*wn);
% Sidelobe canceler - remove the response at null direction
w = wd-wn*rn;
%w = wd;

w = [0; w]; % 

txtdMod = txtd * w';
txtdMod = sdr1.applyCalTxArray(txtdMod);
sdr1.send(txtdMod);
%%
nFFT = 1024;
txtd = zeros(nFFT, sdr1.nch);
sdr1.send(txtd);

% Clear workspace variables
clearvars -except sdr1 sdr2