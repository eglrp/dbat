function Y=homogenous(X)
%HOMOGENOUS Convert Euclidean coordinates to homogenous.
%
%   HOMOGENOUS(X) converts the K-by-N array X with K-dimensional
%   Euclidean coordinates to a (K+1)-by-N array with the corresponding
%   homogenous coordinates. X can have multiple layers.
%
%See also: EUCLIDEAN.

% $Id$

% Append unity.
Y=X;
Y(end+1,:)=1;