% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (c) 2020 University of Southern California
% See full notice in LICENSE.md
% Omid G. Sani and Maryam M. Shanechi
% Shanechi Lab, University of Southern California
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PSIDPredict: Given a PSID model, predicts behavior z from neural data y
%   Inputs:
%     - (1) idSys: Identified model returned from running PSID
%     - (2) y: Observation signal (e.g. neural signal). 
%               Must be T x ny:
%               [y(1); y(2); y(3); ...; y(T)]
%     - (3) u: external input signal. 
%               Must be T x nu:
%               [u(1); u(2); u(3); ...; u(T)]
%   Outputs:
%     - (1) zPred: predicted behavior z using the provided observation y
%               Has dimensions T x nz
%               [zPred(1); zPred(2); zPred(3); ...; zPred(T)]
%               with z(i) the best prediction of z(i) using y(1),...,y(i-1)(and u(1),...,u(i))
%     - (2) yPred (optional): same as (1), for the observation y itself (and u)
%     - (3) xPred (optional): same as (1), for the latent states
%   Usage example:
%       idSys = PSID(yTrain, zTrain, nx, n1, i);
%       [zPred, ~, xPred] = PSIDPredict(idSys, yTest);

function [zPred, yPred, xPred] = PSIDPredict(idSys, y, u, settings)

    time_first = true; %% modify!!

    if nargin < 3, u = []; end
    if nargin < 4, settings = struct; end
    
    if iscell(y)
        zPred = cell(size(y));
        xPred = cell(size(y));
        yPred = cell(size(y));
        if isempty(u), u = cell(size(y)); end
        for yInd = 1:numel(y)
            [zPred{yInd}, yPred{yInd}, xPred{yInd}] = PSIDPredict(idSys, y{yInd}, u{yInd}, settings);
        end
        return
    end
    
    if ~isfield(idSys, 'Cz') || isempty(idSys.Cz) && isfield(idSys, 'T') && ~isempty(idSys.T) % For backwards compatibility
        idSys.Cz = idSys.T(2:end, :)';
    end
    
    % Run Kalman filter
    N = size(y, 1);
    
    A = fetchOneOfFieldValues(idSys, {'a', 'A'}, []);
    K = fetchOneOfFieldValues(idSys, {'k', 'K'}, []);
    Cy = fetchOneOfFieldValues(idSys, {'c', 'C', 'Cy'}, []);
    B = fetchOneOfFieldValues(idSys, {'b', 'B'}, []); 
    Dy = fetchOneOfFieldValues(idSys, {'d', 'D', 'Dy'}, []);
    Dz = fetchOneOfFieldValues(idSys, {'dz', 'Dz'}, []);
    
    nx = size(A, 1);
    Xp = zeros(nx, 1); % Initial state
    xPred = nan(N, nx);
    for i = 2:N
        xPred(i, :) = Xp; % X(i|i-1)
        yThis = y(i, :);
        if ~isempty(u), uThis = u(i-1, :); end
        if isfield(idSys, 'YPrepModel') && ~isempty(idSys.YPrepModel)
            yThis = idSys.YPrepModel.apply(yThis,1); % Apply any mean-removal/zscoring
            % if idSys.YPrepModel.remove_mean || idSys.YPrepModel.zscore
            %     yThis = yThis - idSys.YPrepModel.dataMean()
            % end
        end
        % Constructing: Xp = A * Xp  + K * (yThis' - Cy*Xp - Dy*uThis'); % Kalman prediction  
        innovThis = yThis' - Cy*Xp ;
        if ~isempty(u) && isfield(idSys, 'UPrepModel') && ~isempty(idSys.UPrepModel), uThis = idSys.UPrepModel.apply(uThis,time_first); end% Apply any mean-removal/zscoring
        if ~isempty(u) && ~isempty(Dy)
            innovThis = innovThis -  Dy*uThis';
        end
        Xp = A * Xp  + K * innovThis  ; % Kalman prediction
        if ~isempty(u) && ~isempty(B)
            Xp = Xp + B*uThis';
        end
    
    end
    
    yPred = (Cy * xPred.').';
    if ~isempty(idSys.Cz)
      zPred = (idSys.Cz * xPred.').';
    else
      zPred = [];
    end

    
    if ~isempty(u) && isfield(idSys, 'UPrepModel') && ~isempty(idSys.UPrepModel)
        u = idSys.UPrepModel.apply(u,time_first);
    end
    if ~isempty(Dy) && ~isempty(u) % Apply input if has feedthrough term
        yPred = yPred + (Dy * u.').';
    end
    if ~isempty(Dz) && ~isempty(u) % Apply input if has feedthrough term
        zPred = zPred + (Dz * u.').';
    end
        
    if isfield(idSys, 'YPrepModel') && ~isempty(idSys.YPrepModel)
        yPred = idSys.YPrepModel.apply_inverse(yPred,time_first); % Apply inverse of any mean-removal/zscoring
    end
    if isfield(idSys, 'ZPrepModel') && ~isempty(idSys.ZPrepModel) % Apply inverse of any mean-removal/zscoring
        zPred = idSys.ZPrepModel.apply_inverse(zPred,time_first);
    end
    
    end
    
    function val = fetchOneOfFieldValues(csys, fNames, defaultVal)
    
    val = defaultVal;
    
    for fi = 1:numel(fNames)
        if isfield(csys, fNames{fi})
            val = csys.(fNames{fi});
            break
        end
    end
    
    end