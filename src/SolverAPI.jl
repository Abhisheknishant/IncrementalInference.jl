## Various solver API's used in the past.  These functions are due to be standardized, and obsolete code / functions removed.



"""
    $SIGNATURES

Perform inference over the Bayes tree according to `opt::SolverParams`.

Notes
- Variety of options, including fixed-lag solving -- see `getSolverParams(fg)` for details.

Example
```julia
# without [or with] compute recycling
tree, smt, hist = solveTree!(fg [,tree])
```

Related

solveCliq!, wipeBuildNewTree!
"""
function solveTree!(dfgl::G,
                    oldtree::AbstractBayesTree=emptyBayesTree();
                    delaycliqs::Vector{Symbol}=Symbol[],
                    recordcliqs::Vector{Symbol}=Symbol[],
                    skipcliqids::Vector{Symbol}=Symbol[],
                    maxparallel::Int=50,
                    variableOrder::Union{Nothing, Vector{Symbol}}=nothing,
                    variableConstraints::Vector{Symbol}=Symbol[]  ) where G <: DFG.AbstractDFG
  #
  @info "Solving over the Bayes (Junction) tree."
  smtasks=Vector{Task}()
  hist = Dict{Int, Vector{Tuple{DateTime, Int, Function, CliqStateMachineContainer}}}()
  opt = DFG.getSolverParams(dfgl)

  if opt.isfixedlag
      @info "Quasi fixed-lag is enabled (a feature currently in testing)!"
      fifoFreeze!(dfgl)
  end

  orderMethod = 0 < length(variableConstraints) ? :ccolamd : :qr

  # current incremental solver builds a new tree and matches against old tree for recycling.
  tree = wipeBuildNewTree!(dfgl, variableOrder=variableOrder, drawpdf=opt.drawtree, show=opt.showtree, maxparallel=maxparallel, filepath=joinpath(getSolverParams(dfgl).logpath,"bt.pdf"), variableConstraints=variableConstraints, ordering=orderMethod)
  # setAllSolveFlags!(tree, false)

  @info "Do tree based init-inference on tree"
  if opt.async
    smtasks = asyncTreeInferUp!(dfgl, tree, oldtree=oldtree, N=opt.N, drawtree=opt.drawtree, recordcliqs=recordcliqs, limititers=opt.limititers, downsolve=opt.downsolve, incremental=opt.incremental, skipcliqids=skipcliqids, delaycliqs=delaycliqs )
  else
    smtasks, hist = initInferTreeUp!(dfgl, tree, oldtree=oldtree, N=opt.N, drawtree=opt.drawtree, recordcliqs=recordcliqs, limititers=opt.limititers, downsolve=opt.downsolve, incremental=opt.incremental, skipcliqids=skipcliqids, delaycliqs=delaycliqs )
  end
  @info "Finished tree based init-inference"

  # transfer new tree to outside parameter
  oldtree.bt = tree.bt
  oldtree.btid = tree.btid
  oldtree.cliques = tree.cliques #TODO JT kyk meer detail, this is a bit strange as its a copy of data in graph
  oldtree.frontals = tree.frontals
  oldtree.variableOrder = tree.variableOrder
  oldtree.buildTime = tree.buildTime

  return oldtree, smtasks, hist
end


"""
    $SIGNATURES

Perform inference over one clique in the Bayes tree according to `opt::SolverParams`.

Example
```julia
tree = wipeBuildNewTree!(fg)
smt, hist = solveCliq!(fg, tree, :x1 [,cliqHistories=hist] )
```

Related

solveTree!, wipeBuildNewTree!
"""
function solveCliq!(dfgl::G,
                    tree::AbstractBayesTree,
                    cliqid::Symbol;
                    recordcliq::Bool=false,
                    # cliqHistories = Dict{Int,Vector{Tuple{DateTime, Int, Function, CliqStateMachineContainer}}}(),
                    maxparallel::Int=50,
                    async::Bool=false  ) where G <: DFG.AbstractDFG
  #
  # hist = Vector{Tuple{DateTime, Int, Function, CliqStateMachineContainer}}()
  opt = DFG.getSolverParams(dfgl)

  if opt.isfixedlag
      @info "Quasi fixed-lag is enabled (a feature currently in testing)!"
      fifoFreeze!(dfgl)
  end

  # if !isTreeSolved(treel, skipinitialized=true)
  cliq = whichCliq(tree, cliqid)
  cliqtask = if async
    @async tryCliqStateMachineSolve!(dfgl, tree, cliq.index, drawtree=opt.drawtree, limititers=opt.limititers, downsolve=opt.downsolve,recordcliqs=(recordcliq ? [cliqid] : Symbol[]), incremental=opt.incremental)
  else
    tryCliqStateMachineSolve!(dfgl, tree, cliq.index, drawtree=opt.drawtree, limititers=opt.limititers, downsolve=opt.downsolve,recordcliqs=(recordcliq ? [cliqid] : Symbol[]), incremental=opt.incremental) # N=N
  end
  # end # if

  # post-hoc store possible state machine history in clique (without recursively saving earlier history inside state history)
  # assignTreeHistory!(tree, cliqHistories)

  # cliqHistories
  return cliqtask
end





## Experimental Parametric
"""
    $SIGNATURES

Perform parametric inference over the Bayes tree according to `opt::SolverParams`.

Example
```julia
tree, smt, hist = solveTree!(fg ,tree)
```
"""
function solveTreeParametric!(dfgl::DFG.AbstractDFG,
                    tree::AbstractBayesTree;
                    delaycliqs::Vector{Symbol}=Symbol[],
                    recordcliqs::Vector{Symbol}=Symbol[],
                    skipcliqids::Vector{Symbol}=Symbol[],
                    maxparallel::Int=50)
  #
  @error "Under development, do not use, see #539"
  @info "Solving over the Bayes (Junction) tree."
  smtasks=Vector{Task}()
  hist = Dict{Int, Vector{Tuple{DateTime, Int, Function, CliqStateMachineContainer}}}()
  opt = DFG.getSolverParams(dfgl)

  @info "Do tree based init-inference"
  # if opt.async
  smtasks, hist = taskSolveTreeParametric!(dfgl, tree, oldtree=tree, drawtree=opt.drawtree, recordcliqs=recordcliqs, limititers=opt.limititers, incremental=opt.incremental, skipcliqids=skipcliqids, delaycliqs=delaycliqs )

  @info "Finished tree based Parametric inference"


  return tree, smtasks, hist
end
