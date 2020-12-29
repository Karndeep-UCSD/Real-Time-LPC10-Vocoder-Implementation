% clear; clc; close all;
[data, fs] = audioread('C:\Users\19095\Documents\MUS270a\Project_LPC\data\josh\neutral_1-28_0023.wav');

% [data, fs] = audioread('C:\Users\19095\Documents\MUS270a\Project_LPC\data\sam\sleepiness_1-28_0006.wav');

% DOWNSAMPLE TO 8K for optimal LPC performance
down_factor = 2;
data = filter(gausswin(4),1,data);
data = 2*downsample(data,down_factor);
fs = fs/down_factor;

% get windowsize for desired time(s):
winSize = .025*fs;
nWins = floor(length(data)/winSize);

% Apply PreEmphasis Filter 
data = filter([1 -0.95],1,data);


% ~~~~~~~~~~Encoder~~~~~~~~~~
code = struct;
for i = 1:nWins

    % Segment input and apply window
    y = data( 1+(i-1)*winSize:i*winSize );
    y = hann(winSize).*y;
    
    % Determine if segment is Voiced/Unvoiced
    v = find_voiced(y,.25, 'ZeroCrossing');

    % Determine Pitch of voice
    f0 = find_fundemental(y,fs,v);

    % Calculate All-pole Coeffients
    A = find_coeff(y,1,10);

    % Measure gain of segment
    G = find_gain(y);
    
    % Save Parameters to structure
    code(i).Voiced = v;
    code(i).FundementalFrequency = f0;
    code(i).Gain = G;
    code(i).AllpoleFilter = A;
    
end


% ~~~~~~~~~~Decoder~~~~~~~~~~
recon = [];
% variables for interpolation
pPrev = 0;
lastInd = 0;
for i = 1:length(code)
    
    % Unpack Parameters
    v  = code(i).Voiced ;
    f0 = code(i).FundementalFrequency;
    G  = code(i).Gain;
    A  = code(i).AllpoleFilter;    
    
    % Excitation Signal 
    % voiced ~Periodic signal
    if v   
        E = zeros(size(y,1),1);
        P = round(fs/f0);
        if pPrev == 0
            ind = floor(P/2):P:size(E,1);
            E(ind,1) = 1;
        else
            % Linear Interpolation of pitch
            nstep = floor(winSize/(max(P,pPrev)));
            steps = linspace(max(pPrev-lastInd,1),P,nstep+1);
            ind = floor(cumsum(steps) - steps(1) + 1);
            ind = [ind(2:end-1),ind(end):P:size(E,1)];
            E(ind,1) = 1;

        end
        pPrev = P;
        lastInd = size(y,1)-ind(end);

    % unvoiced ~Random Noise 
    else        
        E = rand(size(y,1),1);
        pPrev =0;
        lastInd = 0;
    end
    
    % Sythesis
    out = filter(1,A,E);
    out = out;
    % DeEmphasis Filter - sounds worse?
    %out = filter(1,[1,-.9375],out);
    recon = [recon;out];

end

% Gain Envelope:
gains = cell2mat({code(:).Gain});
gainEnvelope = gains(1)*ones(1,winSize/2);
for i = 2:size(gains,2)
    interp = linspace(gains(i-1), gains(i), winSize);
    gainEnvelope = [gainEnvelope, interp];
end
interp = gains(end)*ones(1,winSize/2);
gainEnvelope = [gainEnvelope, interp];

recon = gainEnvelope'.*recon;

% Normalize Audio between -1 and 1
recon = (recon - min(recon)) / (max(recon)-min(recon));


% ~~~~~~~~~~Helper Functions~~~~~~~~~~
function f0 = find_fundemental(clip,fs,voiced)
% Search for the most prominent freqiency in a signal
% by analyzing the autocorrelation.
% frequencies are approximatly bounded by human speech.

    if voiced
        % Frequency cutoffs [Hz]
        fLo = 40; 
        fHi = 400;

        % Index range to search over for pitch
        indLo = fs/fLo;
        indHi = fs/fHi;

        % Calculate Autocorrolation
        corr = xcorr(clip);
        corr = corr(length(clip):end);

        % Find max index in range of human speach
        [~,I] = max(corr(indHi:indLo));
        I = I + indHi;

        % Convert index to pitch/fundemental frequency
        f0 = fs/I;

    else
        f0 = 0;
    end
    
end

function voiced = find_voiced(clip, threshold, method)
% Determines whether clip is voiced or unvoiced
% either uses Zero Crossing metric or Energy Metric

    % count number of zero crossing
    if strcmp(method, 'ZeroCrossing')
        % Default threshold
        if ~exist('threshold','var')
            threshold = .25;
        end

        binary = sign(clip);
        flips = abs(diff(binary)/2);
        cross_rate = mean(flips);
        if cross_rate >= threshold
            voiced = 0;
        else
            voiced = 1;
        end
        
    % estimate signal energy
    elseif strcmp(method, 'energy')
        % Default threshold
        if ~exist('threshold','var')
            threshold = 1.5;
        end

        % Calculate energy normalized to windSize
        norm_energy = sum(abs(clip));
        % Determine voiced via theshold
        if norm_energy >= threshold
            voiced = 1;
        else
            voiced = 0;
        end
    end
         
end

function rms = find_gain(clip)
% Approximate the gain/loudess of a sound with 
% room mean squared average.

    rms = sqrt(mean(clip.^2));
    
end

function A = find_coeff(clip,voiced,order)
% Estimates the lpc - allpole filter's coefficients
% Using the 'Autocorrelation' Method.

    % Default Order of points for LPC
    if ~exist('order','var')
        order = 10;
    end
    
    % only user order 4 for unvoiced
    if ~voiced
        order = 4;
    end
    
    % Autocorrelation
    corr = xcorr(clip,order);
    corr = corr(order+1:end);
    % Construct Yule-Walker Equations
    Rx = toeplitz(corr(1:end-1));
    r = corr(2:end);
    % Solve equation by left division
    A = [1;-Rx\r];
   
end
