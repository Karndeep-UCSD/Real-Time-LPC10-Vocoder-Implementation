fs = 8000;
SamplesPerFrame = 8000*.025;
LPCorder = 40 ;

keyboard;
 
 
micReader = audioDeviceReader(fs, 'SamplesPerFrame', SamplesPerFrame);
speakerWriter = audioDeviceWriter(fs);
% spectAnalyzer = dsp.SpectrumAnalyzer(fs);

preEmphasisFilter = dsp.FIRFilter('Numerator', [1 -0.95]);

% Excitation shift tracking
lastInd = 1;

tic;
while (toc<100)
    audio = micReader();

    % ~~~~~~~~~~Encoder~~~~~~~~~~
        % Pre-Emphasis
        audio = preEmphasisFilter(audio);
        
        % apply window
        audio = hann(SamplesPerFrame).*audio;

        % Determine if segment is Voiced/Unvoiced
        v = find_voiced(audio,.26, 'ZeroCrossing');

        % Determine Pitch of voice
        f0 = find_fundemental(audio,fs,v);

        % Calculate All-pole Coeffients
        A = find_coeff(audio,1,LPCorder);

        % Measure gain of segment
        G = find_gain(audio);

    % ~~~~~~~~~~Decoder~~~~~~~~~~
        % Excitation Signal 
        % voiced ~Periodic signal
        if v   
            E = zeros(SamplesPerFrame,1);
            P = round(fs/f0);
            ind = lastInd:P:SamplesPerFrame;
            E(ind,1) = 1;
            lastInd = SamplesPerFrame - ind(end) + 1;

        % unvoiced ~Random Noise 
        else        
            E = rand(size(audio,1),1);
            lastInd = 1;
        end

        % Sythesis
        recon = filter(1,A,E);
        recon = G*recon/max(recon);
        
        % Output to speakers
        speakerWriter(5*recon);

end


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
