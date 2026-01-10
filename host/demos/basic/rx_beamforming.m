% In this demo, we assume that sdr0 is open, and is fully
% calibrated. Look at the calibration demo to make sure this is done. In
% the minimum, the timing and phase offsets need to be calibrated.

% Transmit a wideband signal from a remote source. On the RX, capture
% samples, and apply the calibrations. Then, apply BF vectors for a set of
% AoA values. Plot them out.

nread = 1024;
nFFT = nread;
nskip = nread * 3;
ntimes = 10;
scMin = -20;
scMax = 20;


for iter = 1:1

rxtd = sdr2.recv(nread, nskip, ntimes, 1);
rxtd = sdr2.applyCalRxArray(rxtd);

naoa = 201;
aoas = linspace(-1, 1, naoa);
pArray = zeros(1, naoa);

for iaoa = 1:naoa
    p = 0;
    aoa = aoas(iaoa);
    for itimes = 1:ntimes
        tdbf = zeros(nFFT, 1);
        for rxIndex=1:sdr2.nch
            td = rxtd(:,itimes,rxIndex);
            tdbf = tdbf + td * exp(1j*rxIndex*pi*sin(aoa)); % Apply BF Vec
        end % rxIndex
        fd = fftshift(fft(tdbf));
        p = p + sum(abs(fd( nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)));
    end %itimes
    pArray(iaoa) = p;
end % iaoa

% Plot
%pArray = pArray / max(pArray);
figure(3);
plot(rad2deg(aoas), mag2db(pArray), 'LineWidth', 5); hold on;
xlabel('Angle of Arrival (Deg)');
ylabel('Power (dB)');
set(gca, 'FontSize', 30);
grid on; grid minor;
%ylim([-15 0])
end

% Clear workspace variables
clear aoa aoas fd iaoa naoa p pArray refTxIndex td tdbf txtdMod;
clear ans itimes m nFFT nread nskip ntimes rxIndex rxtd;
clear scIndex txfd constellation scMax scMin;
