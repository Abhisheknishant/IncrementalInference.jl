

"""
$(TYPEDEF)

Data structure for each clique in the Bayes (Junction) tree.
"""
mutable struct BayesTreeNodeData
  frontalIDs::Vector{Int}
  conditIDs::Vector{Int}
  inmsgIDs::Vector{Int}
  potIDs::Vector{Int} # this is likely redundant TODO -- remove
  potentials::Vector{Int}
  partialpotential::Vector{Bool}
  cliqAssocMat::Array{Bool,2}
  cliqMsgMat::Array{Bool,2}
  directvarIDs::Vector{Int}
  directFrtlMsgIDs::Vector{Int}
  msgskipIDs::Vector{Int}
  itervarIDs::Vector{Int}
  directPriorMsgIDs::Vector{Int}
  debug
  debugDwn
  upMsg::Dict{Symbol, BallTreeDensity}
  dwnMsg::Dict{Symbol, BallTreeDensity}
  upInitMsg::Dict{Int, Dict{Symbol, BallTreeDensity}}
  allmarginalized::Bool
  initialized::Symbol
  upsolved::Bool
  downsolved::Bool
  BayesTreeNodeData() = new()
  BayesTreeNodeData(x...) = new(x[1],x[2],x[3],x[4],x[5],x[6],x[7],x[8],x[9],x[10],
                                x[11],x[12],x[13],x[14],x[15],x[16],x[17],x[18],x[19],x[20],
                                x[21], x[22] )
end

# TODO -- this should be a constructor
function emptyBTNodeData()
  BayesTreeNodeData(Int[],Int[],Int[],
                    Int[],Int[],Bool[],
                    Array{Bool}(undef, 0,0),
                    Array{Bool}(undef, 0,0),
                    Int[],Int[],
                    Int[],Int[],Int[],
                    nothing, nothing,
                    Dict{Symbol, BallTreeDensity}(:null => AMP.manikde!(zeros(1,1), [1.0;], (:Euclid,))),
                    Dict{Symbol, BallTreeDensity}(:null => AMP.manikde!(zeros(1,1), [1.0;], (:Euclid,))),
                    Dict{Int, Dict{Symbol, BallTreeDensity}}(),
                    false, :null,
                    false, false  )
end

# BayesTree declarations
"""
$(TYPEDEF)

Data structure for the Bayes (Junction) tree, which is used for inference and constructed from a given `::FactorGraph`.
"""
mutable struct BayesTree
  bt
  btid::Int
  cliques::Dict{Int,Graphs.ExVertex}
  frontals::Dict{String,Int}
end

function emptyBayesTree()
    bt =   BayesTree(Graphs.inclist(Graphs.ExVertex,is_directed=true),
                     0,
                     Dict{Int,Graphs.ExVertex}(),
                     #[],
                     Dict{AbstractString, Int}())
    return bt
end


"""
$(TYPEDEF)
"""
mutable struct NBPMessage <: Singleton
  p::Dict{Int,EasyMessage}
end

"""
$(TYPEDEF)
"""
mutable struct PotProd
    Xi::Int
    prev::Array{Float64,2}
    product::Array{Float64,2}
    potentials::Array{BallTreeDensity,1}
    potentialfac::Vector{AbstractString}
end
"""
$(TYPEDEF)
"""
mutable struct CliqGibbsMC
    prods::Array{PotProd,1}
    lbls::Vector{Symbol}
    CliqGibbsMC() = new()
    CliqGibbsMC(a,b) = new(a,b)
end
"""
$(TYPEDEF)
"""
mutable struct DebugCliqMCMC
    mcmc::Union{Nothing, Array{CliqGibbsMC,1}}
    outmsg::NBPMessage
    outmsglbls::Dict{Symbol, Int}
    priorprods::Vector{CliqGibbsMC} #Union{Nothing, Dict{Symbol, Vector{EasyMessage}}}
    DebugCliqMCMC() = new()
    DebugCliqMCMC(a,b,c,d) = new(a,b,c,d)
end

"""
$(TYPEDEF)
"""
mutable struct UpReturnBPType
    upMsgs::NBPMessage
    dbgUp::DebugCliqMCMC
    IDvals::Dict{Int, EasyMessage} #Array{Float64,2}
    keepupmsgs::Dict{Symbol, BallTreeDensity} # TODO Why separate upMsgs?
    totalsolve::Bool
end

"""
$(TYPEDEF)
"""
mutable struct DownReturnBPType
    dwnMsg::NBPMessage
    dbgDwn::DebugCliqMCMC
    IDvals::Dict{Int,EasyMessage} #Array{Float64,2}
    keepdwnmsgs::Dict{Symbol, BallTreeDensity}
end

"""
$(TYPEDEF)
"""
mutable struct ExploreTreeType{T}
  fg::FactorGraph
  bt::BayesTree
  cliq::Graphs.ExVertex
  prnt::T
  sendmsgs::Array{NBPMessage,1}
end

function ExploreTreeType(fgl::FactorGraph,
                btl::BayesTree,
                vertl::Graphs.ExVertex,
                prt::T,
                msgs::Array{NBPMessage,1} ) where {T}
  #
  ExploreTreeType{T}(fgl, btl, vertl, prt, msgs)
end

"""
$(TYPEDEF)
"""
mutable struct MsgPassType
  fg::FactorGraph
  cliq::Graphs.ExVertex
  vid::Int
  msgs::Array{NBPMessage,1}
  N::Int
end
