# development testing for multithreaded convolution

using Distributions
using IncrementalInference
using Base: Test

import IncrementalInference: getSample



@testset "Basic ContinuousScalar example to ensure multithreaded convolutions work..." begin

@show Threads.nthreads()

N = 100

# Start with an empty factor graph
fg = emptyFactorGraph()

# add the first node
addNode!(fg, :x0, ContinuousScalar, N=N)

# this is unary (prior) factor and does not immediately trigger autoinit of :x0.
addFactor!(fg, [:x0], Prior(Normal(0,1)))


addNode!(fg, :x1, ContinuousScalar, N=N)
# P(Z | :x1 - :x0 ) where Z ~ Normal(10,1)
addFactor!(fg, [:x0, :x1], LinearConditional(Normal(10.0,1)), threadmodel=MultiThreaded)


pts = approxConv(fg, :x0x1f1, :x1, N=N)

@test 0.95*N <= sum(abs.(pts - 10.0) .< 5.0)

##

fc = getVert(fg, :x0x1f1, nt=:fct)
ccw = getData(fc).fnc
ccw.hypotheses
ccw.certainhypo


res = zeros(1)


ccw.cpt[2]

ccw(res)



fieldnames(ccw)


getData(fc).fnc.xDim

getData(fc).fnc.measurement


end


#
