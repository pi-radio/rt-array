%
% Company:	New York University
%           Pi-Radio
%
% Engineer: Panagiotis Skrimponis
%           Aditya Dhananjay
%
% Description: This class creates a fully-digital SDR with 8-channels. This
% class establish a communication link between the host and the Pi-Radio
% TCP server running on the ARM. The server configures the RF front-end and
% the ADC flow control.
%
% Last update on Mar 23, 2023
%
% Copyright @ 2023
%
classdef FullyDigital < matlab.System
    properties
        ip;				% IP address
        socket;			% TCP socket to control the Pi-Radio platform
        fpga;			% FPGA object
        isDebug;		% if 'true' print debug messages
        
        nch = 8;		% number of channels
        figNum;         % Figure number to plot waveforms for this SDR (Start Number)
        fc = 3.25e9;     % carrier frequency of the SDR in Hz
        name;           % Unique name for this transceiver board

        % Cal Factors
        calTxDelay;
        calRxDelay;
        calTxPhase;
        calRxPhase;
        
        calTxGains;
        calRxGains;
        calNFFT;
        calSCMin;
        calSCMax;

        % correction parameters
        ntaps_fir0 = 51; % number of taps for fractional delay filter
        ntaps_fir1 = 51; % number of taps for gain correction filter        
    end
    
    methods
        function obj = FullyDigital(varargin)
            % Constructor
            
            % Set parameters from constructor arguments.
            if nargin >= 1
                obj.set(varargin{:});
            end
            
            % Establish connection with the Pi-Radio TCP Server.
            obj.connect();
            
            % Create the RFSoC object
            obj.fpga = piradio.fpga.RFSoC('ip', obj.ip, 'isDebug', obj.isDebug);
                        
            figure(obj.figNum);
            s = sprintf("%s: TX and RX Waveforms", obj.name);
            clf;
            sgtitle(s);
            

            obj.calTxDelay = zeros(1, obj.nch);
            obj.calRxDelay = zeros(1, obj.nch);
            obj.calTxPhase = zeros(1, obj.nch);
            obj.calRxPhase = zeros(1, obj.nch);

        end
        
        function delete(obj)
            % Destructor.
            clear obj.fpga;            
            
            % Close TCP connection.
            obj.disconnect();
        end

        function calRxArray(obj)
            % Pick a reference TX channel

            nFFT = 1024;
            nread = nFFT;
            nskip = 1024*3;	% skip ADC data
            ntimes = 50;	% num of batches to read
            
            obj.recv(nFFT, nskip, ntimes, 1); % Dummy read
            
            % Generate the TX waveform
            scMin = -100;
            scMax = 100;
            niter =  1;
            constellation = [1+1j 1-1j -1+1j -1-1j];
            
            % expType = 1: Make initial measurements of the fractional timing offset
            %
            % expType = 2: Correct the fractional offsets and see if the residual
            % errors are close to 0. Also measure the integer timing offsets. We do not
            % expect integer timing offsets with ~2GHz sampling rate. So we just
            % measure the integer timing offsets, make sure it's zero, but do not
            % present code to correct it (this would be extremely simple to do). Also,
            % measure the per-channel phase offset.
            %
            % expType = 3: Also correct the phase offsets, and make sure that the
            % errors are now close to 0.
            
            % How many unique fractional timing offsets are we going to search through?
            nto = 101;
            figure(obj.figNum+1); clf;
            s = sprintf("%s: RX Array Self-Calibration", obj.name);
            sgt = sgtitle(s);
            sgt.FontSize = 20;
            
            pdpStore = zeros(obj.nch, 3, niter, ntimes, nFFT);
            
            meanResidualTimingErrors = zeros(obj.nch, 1);
            meanResidualPhaseErrors = zeros(obj.nch, 1);
            
            for expType = 1:3
                expType
                
                maxPos = zeros(obj.nch, niter, ntimes);
                maxVal = zeros(obj.nch, niter, ntimes);
                intPos = zeros(obj.nch, niter, ntimes);
                pk     = zeros(obj.nch, niter, ntimes);
                    
                for iter = 1:niter
                    fprintf('\n');
                    txfd = zeros(nFFT, 1);
                    txtd = zeros(nFFT, obj.nch);
                    
                    for scIndex = scMin:scMax
                        if scIndex ~= 0
                            txfd(nFFT/2 + 1 + scIndex, 1) = constellation(randi(4));
                        end
                    end
            
                    txfd(:,1) = fftshift(txfd(:,1));
                    txtd(:,1) = ifft(txfd(:,1));
            
                    m = max(abs(txtd(:,1)));
                   
                    % Scale and send the signal
                    txtd = txtd/m*30000;
                    obj.send(txtd);
                    
                    % Receive the signal
                    rxtd = obj.recv(nread,nskip,ntimes, 1);
                    size(rxtd);
                    
                    for rxIndex=2:obj.nch % Ch 1 is used up for self-cal of the TX Array
                        fprintf('\n');
                        tos = linspace(-0.5, 0.5, nto);
                        for ito = 1:nto
                            to = tos(ito);
                            fprintf('.');
                            for itimes=1:ntimes
                                if (expType == 1)
                                    rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to, nFFT);
                                elseif (expType == 2)
                                    rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to + obj.calRxDelay(rxIndex), nFFT);
                                elseif (expType == 3)
                                    rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to + obj.calRxDelay(rxIndex), nFFT);
                                    rxtdShifted = rxtdShifted * exp(1i*obj.calRxPhase(rxIndex));
                                end
                                rxfd = fft(rxtdShifted);
                                corrfd = rxfd .* conj(txfd);
                                corrtd = ifft(corrfd);
                                
                                [~, pos] = max(abs(corrtd));
                                val = corrtd(pos);
                                if abs(val) > abs(maxVal(rxIndex, iter, itimes))
                                    % We have bound a "better" timing offset
                                    maxVal(rxIndex, iter, itimes) = abs(val);
                                    maxPos(rxIndex, iter, itimes) = tos(ito);
                                    intPos(rxIndex, iter, itimes) = pos;
                                    
                                    % Measure the phase at the "best" to
                                    pk(rxIndex, iter, itimes) = val;
                                    pdpStore(rxIndex, expType, iter, itimes, :) = corrtd;
                                    
                                end % if abs(val) > ...
                            end % itimes
                        end % ito
                    end % rxIndex        
                end % iter
                
                % Calculate the fractional and integer timing offsets
                cols = 'mrgbcykm'; % Colors for the plots
                %maxPos(1,:,:) = maxPos(1,:,:) - maxPos(1,:,:); % For rxIndex=1, everything should be 0
                figure(obj.figNum+1);
                for rxIndex=2:obj.nch
                    
                    % Fractional
                    l = maxPos(rxIndex, :, :); % - maxPos(2,:,:); % Ch 2 is the reference RX
                    l = reshape(l, 1, []);
                    l = (wrapToPi(l*2*pi))/(2*pi);
                    if (expType == 1)
                        figure(obj.figNum+1);
                        subplot(8,1,1);
                        plot(l, cols(rxIndex));
                        title('Pre-Cal: Fractional Timing Offsets');
                        xlabel('Iteration (Unsorted)');
                        hold on;
                        %ylim([-0.5 0.5]);
                        c = sum(exp(1j*2*pi*l));
                        c = angle(c);
                        c = c /(2*pi);
                        obj.calRxDelay(rxIndex) = (1)*c;
                    elseif (expType == 2)
                        figure(obj.figNum+1);
                        subplot(8,1,2);
                        plot(l, cols(rxIndex));
                        %ylim([-0.5 0.5])
                        title('Post-Cal: Fractional Timing Offsets')
                        xlabel('Iteration (Unsorted)');
                        hold on;
            
                        meanResidualTimingErrors(rxIndex) = mean(l);
                        %ylim([-0.5 0.5]);
                    end
                    
                    % Integer
                    l = intPos(rxIndex, :, :) - intPos(2, :, :); % Ch 2 is the reference RX
                    l = reshape(l, 1, []);
                    l = sort(l);
                    if (expType == 2)
                        figure(obj.figNum+1);
                        subplot(8,7,14+rxIndex-1);
                        plot(l, cols(rxIndex));
                        title('Pre-Cal: Integer Timing Off.');
                        hold on;
                        ylim([-10 10]); grid on;
                        medianIndex = length(l) / 2;
                        obj.calRxDelay(rxIndex) = obj.calRxDelay(rxIndex) + l(medianIndex);
                    elseif (expType == 3)
                        figure(obj.figNum+1);
                        subplot(8,7,21+rxIndex-1);
                        plot(l, cols(rxIndex));
                        title('Post-Cal: Integer Timing Off.');
                        hold on;
                        ylim([-10 10]); grid on;
                    end
                    
                    % Phase
                    lRx = pk(rxIndex, :, :);
                    lRx = reshape(lRx, 1, []);
                    
                    if (expType == 2)
                        subplot(8,1,5);
                        ph = wrapToPi(angle(lRx)); 
                        plot(rad2deg(ph), cols(rxIndex)); hold on;
                        %ylim([-180 180]);
                        title('Pre-Cal: LO Phase Offsets (Degree)');
                        l = angle(sum(exp(1j*ph)));
                        obj.calRxPhase(rxIndex) = (-1)*l;
                    elseif (expType == 3)
                        subplot(8,1,6);
                        ph = wrapToPi(angle(lRx));
                        plot(rad2deg(ph), cols(rxIndex)); hold on;
                        %ylim([-180 180]);
                        title('Post-Cal: LO Phase Offsets (Degree)');
            
                        % Print out the average phase error in degree
                        meanResidualPhaseErrors(rxIndex) = mean(rad2deg(ph));
                    end
                    
                end % rxIndex
            end % expType
            
            % How good was the timing and phase calibration? Here are the
            % residual errors printed out.
            meanResidualTimingErrors
            meanResidualPhaseErrors
            
            % Let's flatten the ADCs for a given reference DAC
            
            clearvars -except obj
            clc;
            nFFT = 1024;	% number of FFT points
            txPower = 30000; % Do not exceed 30000
            scMin = -100;
            scMax = 100;
            constellation = [1+1j 1-1j -1+1j -1-1j];
            
            obj.calNFFT = nFFT;
            obj.calSCMin = scMin;
            obj.calSCMax = scMax;
            
            txfd_single = zeros(nFFT, 1);
            
            for scIndex = scMin:scMax
                if scIndex == 0
                    continue;
                end
                txfd_single(nFFT/2 + 1 + scIndex) = constellation(randi(4));
            end
            txfd_single = fftshift(txfd_single); % In MATLAB order
            
            txChId = 1; % This is the reference TX Channel to calibrate the RX Array
            
            txtd = zeros(nFFT, obj.nch);       
            txtd(:, txChId) = ifft(txfd_single);
            txtd(:, txChId) = txPower*txtd(:, txChId)./max(abs(txtd(:, txChId)));
            obj.send(txtd);
                    
            nskip = 1024*3;	% skip ADC data
            nbatch = 500;	% num of batches
            nFFT = 1024;
            
            obj.calRxGains = zeros(obj.nch, nFFT);
            
            for expType = 4:5
            
                expType
                rxtd = obj.recv(nFFT, nskip, nbatch, 1);
            
                for rxChId = 2:8
            
                    fprintf('.');
                
                    rxfd = zeros(nFFT, 1);
                    for ibatch = 1:nbatch
                        rxtd_tmp = squeeze(rxtd(:, ibatch, rxChId));
                        rxfd = rxfd + fft(rxtd_tmp);
                    end
            
                    if (expType == 5)
                        % Apply the Corrections
                        rxfd = rxfd .* squeeze(obj.calRxGains(rxChId, :))';
                    end
            
                    txfd_single = fftshift(txfd_single); % Human
                    rxfd = fftshift(rxfd); % Human
            
                    h = zeros(nFFT, 1);
                    for scIndex = scMin:scMax
                        h(nFFT/2 + 1 + scIndex) = rxfd(nFFT/2 + 1 + scIndex) ./  txfd_single(nFFT/2 + 1 + scIndex);
                    end
            
                    txfd_single = fftshift(txfd_single); % MATLAB
            
                    figure(obj.figNum+1);
                    if expType == 4
                        subplot(8,7,42+rxChId - 1);
                        plot(mag2db(abs(h))); hold on;
                        ylim([125 140]); grid on;
                        title('Pre Cal: Gain Curve');
                    else
                        subplot(8,7,49+rxChId - 1);
                        plot(mag2db(abs(h))); hold on;
                        ylim([125 140]); grid on;
                        title('Post Cal: Gain Curve');
                    end

                    if (expType == 4)
                        for scIndex = scMin:scMax
                            obj.calRxGains(rxChId, nFFT/2 + 1 + scIndex) = 1/abs(h(nFFT/2 + 1 + scIndex));
                        end
                        obj.calRxGains(rxChId, :) = fftshift(obj.calRxGains(rxChId, :));
            
                        if (rxChId == 8)
                            % Scale
                            obj.calRxGains = obj.calRxGains .* max(abs(h));
                        end
                    end
                end % rxChId
                pause(1)
            end % expType
            
            
            % Stop Transmitting and do a Dummy read
            txtd = zeros(nFFT, obj.nch);
            obj.send(txtd);
            pause(0.1);
            obj.recv(nFFT,nskip,nbatch, 1);
            
            clearvars -except obj
            fprintf('\nRX Array Calibration Done!\n');

        end

        function calTxArray(obj)
            %% Calibrate of the TX array
            % This script calibrates the TX-side timing and phase offsets. The TX under
            % calibration is obj, and the reference RX is obj.
            
            % Configure the RX number of samples, etc
            nFFT = 1024;
            nread = nFFT; % read ADC data for 256 cc (4 samples per cc)
            nskip = nFFT*5;   % skip ADC data for this many cc
            ntimes = 50;    % Number of batches to receive
            % Generate the TX waveform
            scMin = -100;
            scMax = 100;
            niter =  1;
            constellation = [1+1j 1-1j -1+1j -1-1j];
            
            % expType = 1: Make initial measurements of the fractional timing offset
            %
            % expType = 2: Correct the fractional offsets and see if the residual
            % errors are close to 0. Also measure the integer timing offsets. We do not
            % expect integer timing offsets with ~1GHz sampling rate. Also,
            % measure the per-channel phase offset.
            %
            % expType = 3: Also correct the phase offsets, and make sure that the
            % errors are now close to 0.
            
            % How many unique fractional timing offsets are we going to search through?
            nto = 101; clc;
            tos = linspace(-0.5, 0.5, nto);
            figure(obj.figNum+2); clf;
            s = sprintf("%s: TX Array Self-Calibration", obj.name);
            sgt = sgtitle(s);
            sgt.FontSize = 20;
            refRxIndex = 1;
            refTxIndex = 2;
            
            txfd = zeros(nFFT, 1);
            txtd = zeros(nFFT, obj.nch);
            
            for scIndex = scMin:scMax
                if (scIndex == 0)
                    continue;
                end
                txfd(scIndex + nFFT/2 + 1) = constellation(randi(4)); % Human order
            end
            txfd = fftshift(txfd); % Machine order
            txtdSingle = ifft(txfd);
            
            m = max(abs(txtdSingle));
            txtdSingle = txtdSingle ./m*30000;
            
            maxFrac = zeros(obj.nch, niter, ntimes);
            maxVal = zeros(obj.nch, niter, ntimes);
            intPos = zeros(obj.nch, niter, ntimes);
            pk     = zeros(obj.nch, niter, ntimes);
            iter = 1;
            cols = 'mrgbcykr'; % Colors for the plots
            
            obj.calTxDelay = zeros(1, obj.nch);
            obj.calTxPhase = zeros(1, obj.nch);
            pdpStore = zeros(obj.nch, 3, niter, ntimes, nFFT);
            
            meanResidualTimingErrors = zeros(obj.nch, 1);
            meanResidualPhaseErrors = zeros(obj.nch, 1);
            
            
            for expType = 1:3
                fprintf('\n');
                maxFrac = zeros(obj.nch, niter, ntimes);
                maxVal = zeros(obj.nch, niter, ntimes);
                intPos = zeros(obj.nch, niter, ntimes);
                pk     = zeros(obj.nch, niter, ntimes);
            
                expType
                
                for txIndex = 2:obj.nch
                    fprintf('\n');
                    txtd = zeros(nFFT, obj.nch);
                    txtd(:, txIndex) = txtdSingle;
            
                    if ((expType == 1) || (expType == 2))
                        txtd(:,txIndex) = fracDelay(txtdSingle, obj.calTxDelay(txIndex), nFFT);
                    elseif (expType == 3)
                        txtd(:,txIndex) = exp(1j*obj.calTxPhase(txIndex)) * fracDelay(txtdSingle, obj.calTxDelay(txIndex), nFFT);
                    end
            
                    obj.send(txtd);
                    pause(0.1);
                    rxtd = obj.recv(nFFT, nskip, ntimes, 1);
            
                    for itimes = 1:ntimes
                        fprintf('.');
                        for ito = 1:nto
                            to = tos(ito);
                            rxtdShifted = fracDelay(rxtd(:,itimes,refRxIndex), to, nFFT);
            
                            rxfd = fft(rxtdShifted);
                            corrfd = zeros(nFFT, obj.nch);
                            corrtd = zeros(nFFT, obj.nch);
                            
                            corrfd(:,txIndex) = conj(txfd) .* (rxfd);
                            corrtd(:,txIndex) = ifft(corrfd(:,txIndex));
                            
                            [~, pos] = max(abs(corrtd(:,txIndex)));
                            val = corrtd(pos, txIndex);
                            if abs(val) >= abs(maxVal(txIndex, iter, itimes))
                                % We have bound a "better" timing offset
                                maxVal(txIndex, iter, itimes) = abs(val);
                                maxFrac(txIndex, iter, itimes) = tos(ito);
                                intPos(txIndex, iter, itimes) = pos;
            
                                pdpStore(txIndex, expType, iter, itimes, :) = corrtd(:,txIndex);
                                
                                % Save the complex max corr value, so that we can use
                                % its phase later.
                                pk(txIndex, iter, itimes) = val;
            
                            end % if abs(val) > ...
            
                        end % ito
                    end % itimes
            
                    % Fractional
                    l = maxFrac(txIndex, :, :);
                    l = reshape(l, 1, []);
            
                    if expType == 1           
                        figure(obj.figNum+2);
                        subplot(8,1,1);
                        plot(l, cols(txIndex));
                        title('Pre-Cal: Fractional Timing Offsets');
                        xlabel('Iteration (Unsorted)');
                        hold on;
                        %ylim([-1 1]);
                        c = sum(exp(1j*2*pi*l));
                        c = angle(c);
                        c = c /(2*pi);
                        obj.calTxDelay(txIndex) = c;
                    elseif expType == 2
                        figure(obj.figNum+2);
                        subplot(8,1,2);
                        plot(l, cols(txIndex)); grid on;
                        title('Post-Cal: Fractional Timing Offsets')
                        xlabel('Iteration (Unsorted)');
                        hold on;
                        %ylim([-1 1]);
            
                        meanResidualTimingErrors(txIndex) = mean(l);
                    end
            
                    % Integer
                    l = intPos(txIndex, :, :) - intPos(refTxIndex, :, :); % 2 is the reference TX index
                    l = reshape(l, 1, []);
                    l = sort(l);
                    if (expType == 2)
                        figure(obj.figNum+2);
                        subplot(8,7,14+txIndex-1);
                        plot(l, cols(txIndex)); grid on;
                        title('Pre-Cal: Integer Timing Offsets');
                        hold on;
                        medianIndex = length(l)/2;
                        obj.calTxDelay(txIndex) = obj.calTxDelay(txIndex) + l(medianIndex);
                    elseif expType == 3
                        figure(obj.figNum+2);
                        subplot(8,7,21+txIndex-1);
                        plot(l, cols(txIndex)); grid on;
                        title('Post-Cal: Integer Timing Offsets');
                        hold on;
                    end
            
                    % Phase
                    %lRef = pk(2, :, :); % 2 is the reference TX index
                    %lRef = reshape(lRef, 1, []);
                    lTx = pk(txIndex, :, :);
                    lTx = reshape(lTx, 1, []);
                    
                    if (expType == 2)
                        subplot(8,1,5);
                        ph = wrapToPi(angle(lTx)); % - angle(lRef));
                        plot(rad2deg(ph), cols(txIndex)); hold on;
                        %ylim([-180 180]);
                        title('Pre-Cal: LO Phase Offsets (Degree)');
                        l = angle(sum(exp(1j*ph)));
                        obj.calTxPhase(txIndex) = (-1)*l;
                    elseif (expType == 3)            
                        subplot(8,1,6);
                        ph = wrapToPi(angle(lTx)); % - angle(lRef));
                        plot(rad2deg(ph), cols(txIndex)); hold on;
                        %ylim([-180 180]);
                        title('Post-Cal: LO Phase Offsets (Degree)');
                        
                        % Print the mean post-cal per-channel phase error
                        meanResidualPhaseErrors(txIndex) = mean(rad2deg(ph)); 
                    end
                
                end % txIndex
            end % expType
            
            meanResidualTimingErrors
            meanResidualPhaseErrors
            
            txtd = zeros(nFFT, obj.nch);
            obj.send(txtd);
            pause(1);
            obj.recv(nread,nskip,ntimes, 1);
            
            % Clear workspace variables
            clear constellation expType iter nFFT niter rxtd scIndex;
            clear scMin scMax txfd txIndex txtd nread nskip nsamp ntimes;
            clear ans corrfd corrtd diff iiter itimes ito nto pos rxfd ;
            clear to tos cols diffMatrix resTimingErrors toff vec ;
            clear intPeakPos intpos c lRef lTx pk ar intPos l ph medianIndex;
            clear maxVal maxFrac val m rxtdShifted;
            clear refTxIndex refRxIndex sf txtdSingle val;
            %clear pdpStore
            
            % Flatten the per-channel TX Gain Curves
            nFFT = 1024;
            nskip = 1024*3;	% skip ADC data
            nbatch = 4000;	% num of batches
            scMin = -100;
            scMax = 100;
            constellation = [1+1j 1-1j -1+1j -1-1j];
            txPower = 10000;
            obj.calNFFT = nFFT;
            obj.calSCMin = scMin;
            obj.calSCMax = scMax;
            
            txfd_original = zeros(nFFT, 1);
            
            for scIndex = scMin:scMax
                if scIndex == 0
                    continue;
                end
                txfd_original(nFFT/2 + 1 + scIndex) = constellation(randi(4));
            end
            
            txfd_original = fftshift(txfd_original); % We are now in MATLAB order
            txtd_single_original = ifft(txfd_original); % Used only for scaling
            
            h_accum = zeros(obj.nch, nFFT);
            figure(obj.figNum+2);
            
            obj.calTxGains = zeros(obj.nch, nFFT);
            
            for expType = 4:5
                expType
                for txChId = 2:8
                    fprintf('.');
                    if (expType == 4)
                        txfd = txfd_original;
                    elseif (expType == 5)
                        % Apply the TX Cal
                        txfd = txfd_original .* squeeze(obj.calTxGains(txChId, :))';
                    end
            
                    txtd_single = ifft(txfd);
                    txtd_single = txPower*txtd_single./max(abs(txtd_single_original));
                    txtd = zeros(nFFT, obj.nch);
                    txtd(:, txChId) = txtd_single;
                    obj.send(txtd);
                    pause(0.1);
            
                    rxtd = obj.recv(nFFT, nskip, nbatch, 1);
                    rxfd = zeros(nFFT, 1);
                            
                    for ibatch = 1:nbatch
                        rxtd_tmp = squeeze(rxtd(:, ibatch, 1));
                        rxfd = rxfd + fft(rxtd_tmp);
                    end
                
                    h = rxfd ./ txfd_original;
                    h = fftshift(h); % MATLAB to Human

                    figure(obj.figNum+2);
                    if (expType == 4)
                        subplot(8,7, 42+txChId-1)
                        plot(mag2db(abs(h(nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)))); hold on;
                        title('Pre-Cal: TX Gain Curve');
                        ylim([130 150]);
                        grid on;
                    else
                        subplot(8,7, 49+txChId-1)
                        plot(mag2db(abs(h(nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)))); hold on;
                        title('Post-Cal: TX Gain Curve');
                        ylim([130 150]);
                        grid on;
                    end
            
                    if (expType == 4)
                        m = 0;
                        for scIndex = scMin:scMax
                            if scIndex == 0
                                continue;
                            end
                            % h is still in Human order
                            m = max(m, abs(h(nFFT/2 + 1 + scIndex)));
                            obj.calTxGains(txChId, nFFT/2 + 1 + scIndex) = 1/abs(h(nFFT/2 + 1 + scIndex));
                        end
                
                        obj.calTxGains(txChId, :) = fftshift(obj.calTxGains(txChId, :));
            
                        if (txChId == 8)
                            % Do the scaling here
                            obj.calTxGains = obj.calTxGains * m;
                        end
                    end % expType == 1
            
                end % txChId
                
            end % expType
            
            txtd = txtd*0;
            obj.send(txtd);
            obj.recv(nFFT, nskip, nbatch, 1);
            
            fprintf('\nTX Array Calibration Done!\n');
            
            clearvars -except obj
        end
        
        function data = recv(obj, nread, nskip, nbatch, toPlot)
            % Calculate the total number of samples to read:
            % (# of batch) * (samples per batch) * (# of channel) * (I/Q)
            nsamp = nbatch * nread * obj.nch * 2;
            
            write(obj.socket, sprintf("+ %d %d %d",  nread/2, nskip/2, nsamp*2));
            
            % Read data from the FPGA
            data = obj.fpga.recv(nsamp);
            
            % Process the data (i.e., calibration, flow control)
            data = reshape(data, nread, nbatch, obj.nch);
            
             % Remove DC Offsets
            for ich = 1:obj.nch
                for ibatch = 1:nbatch
                    data(:,ibatch,ich) = data(:,ibatch,ich) - mean(data(:,ibatch,ich));
                end
            end
            
            if (toPlot == 1)
                % Plot the RX waveform for the first batch
                figure(obj.figNum);
                for rxIndex=1:obj.nch
                    subplot(8, 4, rxIndex+16);
                    plot(real(data(:,1,rxIndex)), 'r'); hold on;
                    plot(imag(data(:,1,rxIndex)), 'b'); hold off;
                    ylim([-35000 35000]);
                    grid on;
                    s = sprintf("RX Ch %d: Time domain", rxIndex - 1);
                    if rxIndex == 1
                        s = s + " (Ref)";
                    end
                    title(s);
                    
                    n = size(data,1);
                    scs = linspace(-n/2, n/2-1, n);
                    subplot(8,4,rxIndex+24);
                    plot(scs, mag2db(abs(fftshift(fft(data(:,1,rxIndex))))));
                    ylim([40 160]);
                    grid on;
                    s = sprintf("RX Ch %d: Freq domain", rxIndex - 1);
                    if rxIndex == 1
                        s = s + " (Ref)";
                    end
                    title(s);
                end
            end
        end
        
        function send(obj, data)
            write(obj.socket, sprintf("- %d", size(data,1)));
            obj.fpga.send(data);
            
             % Plot the TX waveforms
            figure(obj.figNum);
            for txIndex=1:obj.nch
                subplot(8, 4, txIndex);
                plot(real(data(:,txIndex)), 'r'); hold on;
                plot(imag(data(:,txIndex)), 'b'); hold off;
                ylim([-35000 35000]);
                grid on;
                s = sprintf("TX Ch %d: Time domain", txIndex - 1);
                if txIndex == 1
                    s = s + " (Ref)";
                end
                title(s);
                
                n = size(data,1);
                scs = linspace(-n/2, n/2-1, n);
                subplot(8,4,txIndex+8);
                plot(scs, abs(fftshift(fft(data(:,txIndex)))));
                grid on;
                s = sprintf("TX Ch %d: Freq domain", txIndex - 1);
                if txIndex == 1
                    s = s + " (Ref)";
                end
                title(s);
            end
        end
        
        function set_leds(obj, led_string)
            write(obj.socket, sprintf("f00000%s", led_string));
        end

        function opBlob = fracDelay(obj, ipBlob,fracDelayVal,N)
            taps = zeros(0,0);
            for index=-100:100
                delay = index - fracDelayVal;
                taps = [taps sinc(delay)];
            end
            x = [ipBlob; ipBlob];
            x = x';
            y = conv(taps, x);
            opBlob = y(N/2 : N/2 + N - 1);
            opBlob = opBlob';
        end % fracDelay

        function blob = applyCalRxArray(obj, rxtd)
            blob = zeros(size(rxtd));
            for rxIndex=1:obj.nch
                for itimes=1:size(rxtd, 2)
                    td = rxtd(:, itimes, rxIndex);
                    %td = obj.fracDelay(td, obj.calRxDelay(rxIndex), size(td, 1));
                    td = td * exp(1j * obj.calRxPhase(rxIndex));
                    blob(:, itimes, rxIndex) = td;
                end % itimes
            end % rxIndex
        end % function applyCalRxArray
        
        function blob = applyCalTxArray(obj, txtd)
            blob = zeros(size(txtd));
            blob_fd = zeros(size(txtd));
            for txIndex=1:obj.nch
                td = txtd(:, txIndex);
                td = obj.fracDelay(td, obj.calTxDelay(txIndex), size(td, 1));
                td = td * exp(1j * obj.calTxPhase(txIndex));
                blob(:, txIndex) = td;

                blob_fd(:, txIndex) = fft(td);
                a = obj.calTxGains(txIndex, :); a = a';
                blob_fd(:, txIndex) = blob_fd(:, txIndex) .* a;
                blob(:, txIndex) = ifft(blob_fd(:, txIndex));
            end % txIndex
        end % function applyCalTxArray
        
        % The piradio app on PS supports two commands related to realtime beamformer
        % 1. FIRCOEFF <idx> <hex>     - Load FIR coeffs (idx 0-13) and trigger DMA
        % 2. RTCTRL <addr> <val>      - Write to RTCTRL registers. 
        %        addr 00: control word
        %        addr 04 - 1C: phase factors for ch1-ch7
        function status = disable_realtime(obj)
            % Disable realtime correction filters
            status = write(obj.socket, "00000000"); % calibration mode
        end

        function status = configure_realtime(obj, tx_rx_mode)
            % tx_rx_mode - 0: TX mode, 1: RX mode
            % status - 
            % Configure realtime correction filters and phase factors.
            % - FIR 0 (51 taps): fractional delay based on cal{Rx,Tx}Delay
            % - FIR 1 (51 taps, linear-phase): gain equalization from cal{Rx,Tx}Gains
            % - Complex phase multiply from cal{Rx,Tx}Phase

            status = -1;

            if tx_rx_mode == 1
                calDelay = obj.calRxDelay;
                calPhase = obj.calRxPhase;
                calGains = obj.calRxGains;
                ctrl_word = "01000101"; % fir reload + rx mode + correction mode
            else
                calDelay = obj.calTxDelay;
                calPhase = obj.calTxPhase;
                calGains = obj.calTxGains;
                ctrl_word = "01000001"; % fir reload + tx mode + correction mode
            end

            % this is written for odd number of taps for now
            
            % double check the indices
            for ch = 2:obj.nch % ch1 is used for self calib
                d = calDelay(ch);

                % fracDelay()
                taps = zeros(0,0);
                n0 = (obj.ntaps_fir0-1)/2;
                for index = -n0:n0;
                    delay = index + d;
                    taps = [taps sinc(delay)];
                end

                % normalize
                acc = sum(taps);
                if acc ~= 0
                    taps = taps / acc;
                end

                % Convert to Q1.15 and pack: reverse tap order, 8 hex chars/coeff
                q15 = int16(round(max(min(taps, 0.999969482421875), -1) * 2^15));
                
                blob = '';
                for idx = obj.ntaps_fir0-1:-1:0
                    word = uint32(typecast(q15(idx+1), 'uint16'));
                    blob = [blob, sprintf('%08X', word)];
                end

                fir_index = ch - 2; % 0 to 6
                write(obj.socket, sprintf("FIRCOEFF %d %s\n", fir_index, blob));
                pause(0.5);
            end

            % gain correction firs
            nfft = size(calGains, 2);
            for ch = 2:obj.nch % ch1 is used for self calib
                n1 = (obj.ntaps_fir1-1)/2;
                gain = squeeze(calGains(ch, :));
                % TODO: construct a filter from gain curve
                gain_coeffs = zeros(1, obj.ntaps_fir1);
                % Convert to Q1.15
                q15 = int16(round(max(min(gain_coeffs, 0.999969482421875), -1) * 2^15));
                
                % only write unique coefficients (center..0)
                % TODO: everything is written for odd ntaps
                n_unique = n1 + 1; % 26 for 51 taps                
                blob = '';
                for idx = n_unique-1:-1:0
                    word = uint32(typecast(q15(idx+1), 'uint16'));
                    blob = [blob, sprintf('%08X', word)];
                end

                fir_index = 7 + (ch - 2); % 7 to 13                
                write(obj.socket, sprintf("FIRCOEFF %d %s\n", fir_index, blob));
                pause(0.5);
            end

            % phase factors
            for ch = 2:obj.nch
                ph = calPhase(ch);
                
                re = cos(ph);
                im = sin(ph);
                
                % todo: sfi is more reliable in matlab
                re_q15 = int16(round(max(min(re, 0.999969482421875), -1) * 2^15));
                im_q15 = int16(round(max(min(im, 0.999969482421875), -1) * 2^15));
                
                re_hex = upper(dec2hex(typecast(re_q15,'uint16'),4));
                im_hex = upper(dec2hex(typecast(im_q15,'uint16'),4));
                                
                addr = 4*(ch - 2) + 4;
                write(obj.socket, sprintf("RTCTRL %s %s%s\n", dec2hex(addr), im_hex, re_hex));
                pause(0.1);
            end

            % reload fir and set mode (TX/RX + correction enable)
            write(obj.socket, sprintf("RTCTRL 0 %s\n", ctrl_word));
            
            % TODO: should probably check for response code from fpga. fpga responds 'Ok' on success.
            status = 0;
        end        
    end
    
    methods (Access = 'protected')
        function connect(obj)
            % Establish connection with the Pi-Radio TCP Server.
            if (isempty(obj.socket))
                obj.socket = tcpclient(obj.ip, 8083, "Timeout", 5);
            end
        end
        
        function disconnect(obj)
            % Close the Pi-Radio TCP socket
            if (~isempty(obj.socket))
                flush(obj.socket);
                write(obj.socket, 'disconnect');
                pause(0.1);
                clear obj.socket;
            end
        end
    end
end

