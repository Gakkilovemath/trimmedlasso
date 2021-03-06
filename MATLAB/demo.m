%%%
% A demo of MATLAB implementation of algorithms from BCM17
% Written by Martin S. Copenhaver (www.mit.edu/~mcopen)
%%%

%% %%%%%%%%%%%%%%%%%%%
% Example parameters %
%%%%%%%%%%%%%%%%%%%%%%

n = 100;
p = 20;
k = 10;
SNR = 10.;
seed = 1;
egclass = 1;
mu = .01;
lambda = .01;
EPS = 1e-3;
bigM = 10.;


%% %%%%%%%%%%%%%%%%%%
% Construct example %
%%%%%%%%%%%%%%%%%%%%%

[y, X, beta0] = instance_creator(n,p,k,SNR,egclass);

%% %%%%%%%%%%%%%%%%%%%%%%%%%
% Ignore warning messages %
%%%%%%%%%%%%%%%%%%%%%%%%%%%

if true %%% remove various eigenvalue warnings
    warning('off','MATLAB:nargchk:deprecated');
    warning('off','MATLAB:eigs:TooManyRequestedEigsForRealSym');
    warning('off','MATLAB:eigs:TooManyRequestedEigsForComplexNonsym');
end

% set random seed for reproducibility

rng(1,'twister');


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Solve exact and heuristic models %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

beta_hat_exact = tl_exact_bigM(p,k,y,X,mu,lambda,bigM);

beta_hat_altmin = tl_apx_altmin(p,k,y,X,mu,lambda);

beta_hat_envelope = tl_apx_envelope(p,k,y,X,mu,lambda);


