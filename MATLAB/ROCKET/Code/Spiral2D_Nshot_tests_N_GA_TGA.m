%% Create a 2D spiral sequence and export for execution
%  This file would serve Marina's project for whole body rapid
%  imaging/multiple spiral projects 
% The |Sequence| class provides functionality to create magnetic
% resonance sequences (MRI or NMR) from basic building blocks.
%
% This provides an implementation of the open file format for MR sequences
% described here: http://pulseq.github.io/specification.pdf
%
% This example performs the following steps:
% 
% # Create slice selective RF pulse for imaging.
% # Create readout gradients in both directions 
% # Loop through number of  projections
% # Write the sequence to an open file format suitable for execution on a
% scanner.
% Author: Sairam Geethanath
% Modified by : Pavan Poojar
% Modification: Included the Golden Angle

%% Instantiation and gradient limits
% The system gradient limits can be specified in various units _mT/m_,
% _Hz/cm_, or _Hz/m_. However the limits will be stored internally in units
% of _Hz/m_ for amplitude and _Hz/m/s_ for slew. Unspecificied hardware
% parameters will be assignced default values.
 Pulseq_dir = uigetdir('','Pick the sequences directory');
addpath(genpath('.'));
addpath(genpath(Pulseq_dir));
% system = mr.opts('MaxGrad',32,'GradUnit','mT/m',...
%     'MaxSlew',130,'SlewUnit','T/m/s');
gamma =  42576000; % in Hz  %Determined from Pulseq - do not change
Gmax = 32; %mT/m
SRmax = 130;%T/m/s
system = mr.opts('MaxGrad',Gmax,'GradUnit','mT/m',...
    'MaxSlew',SRmax,'SlewUnit','T/m/s', 'gradRasterTime', 10e-6);


%%
% A new sequence object is created by calling the class constructor.
seq=mr.Sequence(system);
%% Sequence events
% Some sequence parameters are defined using standard MATLAB variables
fov=256e-3;   %One parameter to test
Nx=256; Ny=256;
sliceThickness=5e-3;
TR = 50e-3;
TE = 5e-3;%minimum 
dx = fov/Nx;
dy  =dx;
Nshots = 16;
alpha = 3; %Arch - resolution vs Rapid - VDS CS
%% Determining the angle
disp('---------')
disp('1. Normal.')
disp('2. Golden angle.')
disp('3. Tiny golden angle.');
disp('---------')
use_case=input ('Enter the type of angle: ');
switch use_case
    
    case 1
            phiNd=360/Nshots;
            X = ['Normal angle','=',num2str(phiNd),' deg.'];
            disp(X);
            phiN=0;
           
    case 2
            N=1; %Determines the golden angle (111.24 deg)
            tau=(1+sqrt(5))/2; % [ Refer: Stefan Wundrak et.al., "Golden Ratio Sparse MRI Using Tiny Golden Angles", MRM-2016
            phiN=pi/(tau+N-1); % [ Refer: Stefan Wundrak et.al., "Golden Ratio Sparse MRI Using Tiny Golden Angles", MRM-2016
            phiNd=rad2deg(phiN);% Degree
            X = ['Golden angle','=',num2str(phiNd),' deg.'];
            disp(X);
    case 3
            N=3; % Tiny golden angle (49.75 deg)
            tau=(1+sqrt(5))/2;
            phiN=pi/(tau+N-1); % Radians
            phiNd=rad2deg(phiN);% Degree
            X = ['Tiny Golden angle','=',num2str(phiNd),' deg.'];
            disp(X);
end

%% trajectory specific code - design/grad waveforms
% [ktraj, G] = get_spiral_waveforms();
[ktraj,G,lambda]= vds2D_pulseq_v1_N_GA_TGA(fov,Nx,Nshots,alpha,system,phiN);

ktraj = ktraj.*1e-3; %for trajectory to fit into GPI +/-0.5
ktrajs = zeros(size(ktraj,1), size(ktraj,2), 2); 
ktrajs(:,:,1) = real(ktraj);
ktrajs(:,:,2) = imag(ktraj);

%% Slice selection
% Key concepts in the sequence description are *blocks* and *events*.
% Blocks describe a group of events that are executed simultaneously. This
% hierarchical structure means that one event can be used in multiple
% blocks, a common occurrence in MR sequences, particularly in imaging
% sequences. 
%
% First, a slice selective RF pulse (and corresponding slice gradient) can
% be generated using the |makeSincPulse| function.
%
flip=15*pi/180;
[rf, gz] = mr.makeSincPulse(flip,system,'Duration',1.5e-3,...
    'SliceThickness',sliceThickness,'apodization',0.5,'timeBwProduct',4);
adc = mr.makeAdc(length(G),system,'Dwell',system.gradRasterTime);

%% Need to determine multi-slice frequency offsets

%% Spoilers
% To move the $k$-space trajectory away from 0 prior to the readout a
% prephasing gradient must be used.
preTime=8e-4; %Need to figure this one out later!
gzReph = mr.makeTrapezoid('z',system,'Area',-gz.area/2,'Duration',1e-3);
gzSpoil = mr.makeTrapezoid('z',system,'Area',gz.area*2,'Duration',3*preTime);
gx = mr.makeArbitraryGrad('x', squeeze(real(G(:,1))),system);
%% Calculate timing
delayTE=TE - mr.calcDuration(gzReph) - (mr.calcDuration(rf)/2);
% delayTR=TR - mr.calcDuration(gzReph) - mr.calcDuration(rf) ...
%     - mr.calcDuration(gx) - mr.calcDuration(gzSpoil) - delayTE;
delayTR=TR - mr.calcDuration(gzReph) - mr.calcDuration(rf) ...
    - mr.calcDuration(gx) - mr.calcDuration(gzSpoil);
delay1 = mr.makeDelay(delayTE);
delay2 = mr.makeDelay(delayTR);

%% Define sequence blocks
% Next, the blocks are put together to form the sequence

for ns=1:Nshots
            seq.addBlock(rf,gz);
            seq.addBlock(gzReph);
       
             gx = mr.makeArbitraryGrad('x', squeeze(real(G(:,ns))),system);
             gy = mr.makeArbitraryGrad('y', squeeze(imag(G(:,ns))),system);
           
            seq.addBlock(delay1);
            seq.addBlock(gx,gy,adc);
            seq.addBlock(gzSpoil);
            seq.addBlock(delay2);
end

%% Display the sequence 
% ktraj = ktraj./max(abs(ktraj(:)))./2;

figure(1002);
seq.plot('TimeRange',[TR 2*TR]);
%seq.plot();
fname = ['Spiral_2D_',num2str(Nshots),'_',num2str(alpha),'_',num2str(system.maxSlew/gamma),'_',num2str(Gmax),'_',num2str(phiNd),'deg'];
 %save(fname, 'ktrajs' );
save([fname,'.mat'], 'ktrajs' );
%% Write to file
% The sequence is written to file in compressed form according to the file
% format specification using the |write| method.
% fname = ['Spiral_2D_', num2str(Nshots),'_',num2str(TE), '.seq'];
seq.write([fname,'.seq']);

