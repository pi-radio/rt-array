% This is a simple simulation to show the effect of phase imbalance on the
% BEAMs. Assume that we have nch TX channels. Each of them has a random
% error of -e/2 to +e/2 degrees.

nch = 8;
niter = 100;
nerror = 101;
e_vec = linspace(0, 40, nerror);
p = zeros(nerror, 1);

for ierror = 1:nerror

    for iter=1:niter    
        for ich = 1:nch
            s = cos(deg2rad(0 + (rand-0.5) * e_vec(ierror)));
            p(ierror) = p(ierror) + s;
        end
    end

end

p = p/niter;
p = mag2db(p);

plot(e_vec, p);
ylim([17.6 18.2]);

%%

% This is a simple simulation to show the effect of phase imbalance on the
% NULLs. Assume that we have nch TX channels. Each of them has a random
% error of -e/2 to +e/2 degrees.

nch = 8;
niter = 1000;
nerror = 101;
e_vec = linspace(0, 20, nerror);
p_accum_bf = zeros(nerror, 1);
p_accum_nf = zeros(nerror, 1);

for ierror = 1:nerror

    for iter=1:niter
        p = 0;
        n = 0;
        for ich = 1:nch
            % Gaussian, with stddev e_vec(ierror) and 0 mean
            s = cos(deg2rad(0 + e_vec(ierror) * randn(1) + 0));

            % For NULLforming, we have to invert every other channel
            if mod(ich, 2) == 1
                n = n - s;
            else
                n = n + s;
            end
            p = p + s;
        end
        p_accum_bf(ierror) = p_accum_bf(ierror) + abs(p);
        p_accum_nf(ierror) = p_accum_nf(ierror) + abs(n);
    end

end

p = abs(p_accum_bf/niter);
p = mag2db(p);

n = abs(p_accum_nf/niter);
n = mag2db(n);

clf;
plot(e_vec, p); hold on;
plot(e_vec, n);
grid on;


%%

% This is a simple simulation to show the effect of phase imbalance on the
% beams and NULLs. Assume that we have nch TX channels. Each of them has a
% random amplitude error

nch = 8;
niter = 10000;
nerror = 101;
e_vec = linspace(0, 3, nerror); % dB
p_accum_bf = zeros(nerror, 1);
p_accum_nf = zeros(nerror, 1);

for ierror = 1:nerror

    for iter=1:niter
        p = 0;
        n = 0;
        for ich = 1:nch
            % Gaussian, with stddev e_vec(ierror) and 0 mean
            m = db2mag(e_vec(ierror) * randn(1));
            s = m * cos(deg2rad(0));

            % For NULLforming, we have to invert every other channel
            if mod(ich, 2) == 1
                n = n - s;
            else
                n = n + s;
            end
            p = p + s;
        end
        p_accum_bf(ierror) = p_accum_bf(ierror) + abs(p);
        p_accum_nf(ierror) = p_accum_nf(ierror) + abs(n);
    end

end

p = abs(p_accum_bf/niter);
p = mag2db(p);

n = abs(p_accum_nf/niter);
n = mag2db(n);

clf;
plot(e_vec, p); hold on;
plot(e_vec, n);
grid on;

%%
% Simulate both phase and amplitude errors

nch = 8;
niter = 1000;
nerror = 101;
e_vec = linspace(0, 20, nerror);
p_accum_bf = zeros(nerror, 1);
p_accum_nf = zeros(nerror, 1);

for ierror = 1:nerror

    for iter=1:niter
        p = 0;
        n = 0;
        for ich = 1:nch
            % Gaussian, with stddev e_vec(ierror) and 0 mean
            s = cos(deg2rad(0 + e_vec(ierror) * randn(1) + 0));

            % For NULLforming, we have to invert every other channel
            if mod(ich, 2) == 1
                n = n - s;
            else
                n = n + s;
            end
            p = p + s;
        end
        p_accum_bf(ierror) = p_accum_bf(ierror) + abs(p);
        p_accum_nf(ierror) = p_accum_nf(ierror) + abs(n);
    end

end

p = abs(p_accum_bf/niter);
p = mag2db(p);

n = abs(p_accum_nf/niter);
n = mag2db(n);

clf;
plot(e_vec, p); hold on;
plot(e_vec, n);
grid on;


%%

% This is a simple simulation to show the effect of phase imbalance 
% and amplitude imbalance on the beams and NULLs. Assume that we have
% nch TX channels. Each of them has a random error.
clearvars -except sdr0;
nch = 8 ; % Must be an even number, otherwise the code breaks
niter = 200;
nerror_amp = 101; % Simulate 101 amplitude errors
nerror_phase = 101; % Simulate 101 phase errors
e_vec_amp = linspace(0, 1, nerror_amp); % dB
e_vec_phase = linspace(0, 20, nerror_phase); % degrees
p_accum_bf = zeros(nerror_amp, nerror_phase);
p_accum_nf = zeros(nerror_amp, nerror_phase);

for ierror = 1:nerror_amp % Amplitude
    for jerror = 1:nerror_phase % Phase

        for iter=1:niter

            p = 0;
            n = 0;
            
            for ich = 1:nch
                % Gaussian, with stddev e_vec(ierror) and 0 mean
                m = db2mag(e_vec_amp(ierror) * randn(1));
                s = m * cos(deg2rad(0 + e_vec_phase(jerror) * randn(1) + 0));
    
                % For NULLforming, we have to invert every other channel
                if mod(ich, 2) == 1
                    n = n - s;
                else
                    n = n + s;
                end
                p = p + s;
            end
            p_accum_bf(ierror, jerror) = p_accum_bf(ierror, jerror) + abs(p);
            p_accum_nf(ierror, jerror) = p_accum_nf(ierror, jerror) + abs(n);
        end
    
    end
end

p = abs(p_accum_bf/niter);
p = mag2db(p);

n = abs(p_accum_nf/niter);
n = mag2db(n);

clf;

a = p(1,1);
subplot(2,1,1);
colormap('default');
imagesc(e_vec_phase, e_vec_amp, p);
set(gca, 'YDir', 'normal');
ylabel("Amplitude Stddev (dB)");
xlabel("Phase Stddev (Degree)");
ax = gca;
ax.CLim = [a-1 a+1];
colorbar;
title("Beamforming Gain in Boresight (dB relative to single TX channel)");

threshold = 45;
a = p(1,1) - threshold; % What is the NULL threshold relative to the peak?

for ierror = 1:nerror_amp
    for jerror = 1:nerror_phase
        if n(ierror, jerror) < a
            n(ierror, jerror) = 0; % Pass
        else
            n(ierror, jerror) = 1; % Fail
        end
    end
end

subplot(2,1,2);
colormap('summer');
imagesc(e_vec_phase, e_vec_amp, n);
set(gca, 'YDir', 'normal');
ylabel("Amplitude Stddev (dB)");
xlabel("Phase Stddev (Degree)");
ax = gca;
s = sprintf("NULL Forming: %d dB below boresight (Green: Pass)", threshold);
title(s);


clearvars -except sdr0