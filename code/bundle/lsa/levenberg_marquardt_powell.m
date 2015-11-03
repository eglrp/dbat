function [x,code,n,r,J,T,rr,deltas,rhos,steps]=levenberg_marquardt_powell(...
    resFun,vetoFun,x0,W,maxIter,convTol,doTrace,delta0,mu,eta)
%LEVENBERG_MARQUARDT_POWELL Levenberg-Marquardt algorithm with Powell dogleg.
%
%   [X,CODE,I]=LEVENBERG_MARQUARDT_POWELL(RES,VETO,X0,W,N,TOL,TRACE,D0,MU,ETA)
%   runs the trust-region verions of the Levenberg-Marquardt least
%   squares adjustment algorithm with weight matrix W and Powell
%   dogleg on the problem with residual function RES and with initial
%   values X0. A maximum of N iterations are allowed and the
%   convergence tolerance is TOL. The final estimate is returned in
%   X. The damping algorithm uses D0 as the initial delta value.  The
%   quality of each proposed step is determined by the constants 0 <
%   MU < ETA < 1. In addition, if supplied and non-empty, the VETO
%   function is called to verify that the suggested trial point is not
%   invalid. The number of iteration I and a success code (0 - OK, -1
%   - too many iterations) are also returned. If TRACE is true, output
%   sigma0 estimates at each iteration.
%
%   [X,CODE,I,F,J]=... also returns the final estimates of the residual
%   vector F and Jacobian matrix J.
%
%   [X,CODE,I,F,J,T,RR,DELTAS,RHOS,STEPS]=... returns the iteration trace as
%   successive columns in T, the successive estimates of sigma0 in RR, the
%   used damping values in DELTAS, the computed gain ratios in RHOS, and the
%   step types in STEPS. The step types are:
%     0 - Gauss-Newton,
%     2 - Cauchy (steepest descent),
%     1 - Interpolated between Gauss-Newton and Cauchy.
%
%   The function RES is assumed to return the residual function and its
%   jacobian when called [F,J]=feval(RES,X0).
%
%   References:
%     Börlin, Grussenmeyer (2013), "Bundle Adjustment With and Without
%       Damping". Photogrammetric Record 28(144), pp. 396-415. DOI
%       10.1111/phor.12037.
%     Nocedal, Wright (2006), "Numerical Optimization", 2nd ed.
%       Springer, Berlin, Germany. ISBN 978-0-387-40065-5.
%     Levenberg (1944), "A method for the solution of certain nonlinear
%       problems in least squares". Quarterly Journal of Applied
%       Mathematics, 2(2):164-168.
%     Marquardt (1963), "An algorithm for least squares estimation of
%       nonlinear parameters". SIAM Journal on Applied Mathematics,
%       11(2):431-441.
%     Powell (1970), "A Hybrid Method for Nonlinear Equations". In
%       "Numerical Methods for Nonlinear Algebraic Equations", (Ed.
%       Rabinowitz). Gordon and Breach Science, London UK:87-114.
%     Moré (1983), "Recent Developments in Algorithms and Software for
%       Trust Region Methods". In "Mathematical Programming - The State
%       of the Art" (Eds. Bachem, Grötschel, Korte), Springer, Berlin,
%       Germany: 258-287.
%
%See also: BUNDLE, GAUSS_MARKOV, GAUSS_NEWTON_ARMIJO, LEVENBERG_MARQUARDT.

% $Id$

% Initialize current estimate and iteration trace.
x=x0;

if nargout>5
    % Pre-allocate fixed block if trace is asked for.
    blockSize=50;
    T=nan(length(x),min(blockSize,maxIter+1));
    % Enter x0 as first column.
    T(:,1)=x0;
end

% Iteration counter.
n=0;

% OK until signalled otherwise.
code=0;

% Initialize the damping parameter.
delta=delta0;
deltas=[];

% Gain ratios.
rhos=[];

% Step types.
steps=[];

% Compute Cholesky factor of weight matrix.
R=chol(W);

% Handle to weighted residual function. Works for single-return
% call only. Used by linesearch.
wResFun=@(x)R*feval(resFun,x);

% Compute residual, Jacobian, and objective function value.
[s,K]=feval(resFun,x);
% Scale by Cholesky factor.
r=R*s;
J=R*K;
f=1/2*r'*r;

% Residual norm trace.
rr=[];

% Step type strings for trace output.
stepStr={'GN','IP','CP'};

while true
    % Find search direction using the Powell single dogleg algorithm.
    [p,pGN,step]=dogleg(r,J,delta);

    % Store current residual norm and used lambda value.
    rr(end+1)=sqrt(r'*r);
    deltas(end+1)=delta;
    steps(end+1)=step;
    
    JpGN=J*pGN;
    Jp=J*p;
    if step==0 && norm(J*pGN)<convTol*norm(r)
        % Only terminate with success if last step was without damping,
        % i.e. a full G-N step.
        break;
    end

    % Evalutate residual and objective function value in trial point.
    t=x+p;
    rt=feval(wResFun,t);
    ft=1/2*rt'*rt;
    if isempty(vetoFun)
        veto=false;
    else
        veto=feval(vetoFun,t);
    end

    % Compare actual vs. predicted reduction.
    predicted=-r'*Jp-1/2*Jp'*Jp;
    actual=f-ft;

    % Gain ratio.
    rho=actual/predicted;
    rhos(end+1)=rho;

    if doTrace
        fprintf(['Levenberg-Marquardt-Powell: iteration %d, ',...
                 'residual norm=%.2g, delta=%.2g, step=%s, rho=%.1f\n'],n,...
                rr(end),delta,stepStr{step+1},rho);
    end
    
    if veto || rho<=mu
        % Point failed veto test or reduction was too poor.

        % Discard trial point, i.e. x is unchanged.
        
        % Reduce trust region size to half.
        delta=delta/2;
        
        % If necessary, shrink delta below norm(pGN). Otherwise we would
        % calculate and discard the same trial points multiple times.
        if delta>norm(pGN)
            % This replaces a while loop.
            delta=delta/pow2(ceil(log2(delta/norm(pGN))));
        end
    else
        % Accept new point.
        x=t;
        
        % Calculate residual, Jacobian, and objective function value at
        % new point.
        [s,K]=feval(resFun,x);
        % Scale by Cholesky factor.
        r=R*s;
        J=R*K;
        f=1/2*r'*r;

        % Increase trust region size if reduction was good.
        if rho>=eta
            delta=delta*2;
        end
    end
    
    if nargout>5
        % Store iteration trace.
        if n+1>size(T,2)
            % Expand by blocksize if needed.
            T=[T,nan(length(x),blockSize)]; %#ok<AGROW>
        end
        T(:,n+1)=x;
    end

    % Update iteration count.
    n=n+1;
    
    if n>maxIter
        code=-1;
        break;
    end
end

if nargout>5
    % Store final point.
    T(:,n+1)=x;
end

% Trim unused trace columns.
if nargout>5
    T=T(:,1:n);
end

function [p,pGN,step]=dogleg(r,J,delta)
%DOGLEGLSQ Perform a double dogleg step in the Levenberg-Marquardt method.
%
%[p,pGN,step]=dogleglsq(r,J,delta)
%r     - residual at current point.
%J     - Jacobian at current point.
%delta - current size of region of trust.
%p     - double dogleg search direction, |p|<=delta.
%pGN   - Gauss-Newton search direction.
%step  - step type, 0 - Gauss-Newton step,
%                   1 - Interpolated step.
%                   2 - Cauchy (Steepest descent) step,

% Calculate Gauss-Newton direction.
H=J'*J; % This could be optimized by supplying a Cholesky factor of H instead.
g=J'*r;
pGN=H\(-g);

if norm(pGN)<=delta
    % Gauss-Newton direction is within region of trust. Accept it.
    p=pGN;
    step=0; % Signal GN step.
    return;
end

% Calculate the Cauchy Point.
Hg=H*g;
lambdaStar=g'*g/(g'*Hg);
CP=-lambdaStar*g;

if norm(CP)>delta
    % Cauchy Point outside region of trust. Use scaled negative gradient.
    p=-g/norm(g)*delta;
    step=2; % Signal Cauchy step.
    return;
end

% Find intersection of line CP-pGN and circle with radius delta, i.e.
% find k such that norm(CP+k*(pGN-CP))=delta.

% Coefficients for second order equation.
A=sum((CP-pGN).^2);
B=sum(2*CP.*(pGN-CP));
C=sum(CP.^2)-delta^2;

% Solve for positive root.
k=(-B+sqrt(B^2-4*A*C))/(2*A);

% Point on circle.
p=CP+k*(pGN-CP);

% Signal interpolated step.
step=1;
