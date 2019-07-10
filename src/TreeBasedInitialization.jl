
"""
    $SIGNATURES

Based on a push model from child cliques that should have already completed their computation.
"""
getCliqInitUpMsgs(cliq::Graphs.ExVertex)::Dict{Int, Dict{Symbol, Tuple{BallTreeDensity, Vector{Bool}}}} = getData(cliq).upInitMsgs

function setCliqUpInitMsgs!(cliq::Graphs.ExVertex, childid::Int, msg::TempBeliefMsg)
  getData(cliq).upInitMsgs[childid] = msg
  # notify cliq condition that there was a change
  notify(getSolveCondition(cliq))
end

function isCliqInitialized(cliq::Graphs.ExVertex)::Bool
  return getData(cliq).initialized in [:initialized; :upsolved]
end

function isCliqUpSolved(cliq::Graphs.ExVertex)::Bool
  return getData(cliq).initialized == :upsolved
end



"""
    $SIGNATURES

Return the most likely  ordering for initializing factor (assuming up solve
sequence).

Notes:
- sorts id for increasing number of connected factors.
"""
function getCliqInitVarOrderUp(cliq::Graphs.ExVertex)
  # rules to explore dimension from one to the other?

  # get all variable ids and number of associated factors
  allids = getCliqAllVarIds(cliq)
  nfcts = getCliqNumAssocFactorsPerVar(cliq)

  # get priors and singleton message variables (without partials)
  prids = getCliqVarIdsPriors(cliq, getCliqAllVarIds(cliq), false)

  # get current up msgs in the init process (now have all singletons)
  upmsgs = getCliqInitUpMsgs(cliq)
  upmsgids = collect(keys(upmsgs))

  # all singleton variables
  singids = union(prids, upmsgids)

  # add msg marginal prior (singletons) to number of factors
  for msid in upmsgids
    nfcts[msid .== allids] .+= 1
  end

  # sort permutation order for increasing number of factor association
  nfctsp = sortperm(nfcts)
  sortedids = allids[nfctsp]

  # organize the prior variables separately with asceding factor count
  initorder = Symbol[]
  for id in sortedids
    if id in singids
      push!(initorder, id)
    end
  end
  # in ascending order of number of factors
  for id in sortedids
    if !(id in initorder)
      push!(initorder, id)
    end
  end
  return initorder
end

lockUpStatus!(cd::BayesTreeNodeData) = take!(cd.lockUpStatus)
unlockUpStatus!(cd::BayesTreeNodeData) = put!(cd.lockUpStatus, 1)

"""
    $SIGNATURES

Update clique status and notify of the change

Notes
- Assumes users will lock the status state before getting status until after decision whether to update status.
- If so, only unlock after status and condition has been updated.

Dev Notes
- Should be made an atomic transaction
"""
function notifyCliqUpInitStatus!(cliq::Graphs.ExVertex, status::Symbol)
  cd = getData(cliq)

  ## TODO only notify if not data structure is not locked by other user (can then remove the hack)
  # Wait until lock can be aquired
  lockUpStatus!(cd)

  cd.initialized = status
  if isready(cd.initUpChannel)
    tkst = take!(cd.initUpChannel)
    # @info "dumping stale cliq=$(cliq.index) status message $(tkst), replacing with $(status)"
  end
  put!(cd.initUpChannel, status)
  notify(getSolveCondition(cliq))
     # HACK to avoid a race condition  -- remove with atomic lock logic upgrade
     sleep(0.1)
     notify(getSolveCondition(cliq))

  # TODO unlock

  nothing
end

function notifyCliqDownInitStatus!(cliq::Graphs.ExVertex, status::Symbol)
  @info "$(current_task()) Clique $(cliq.index), notify down init status=$(status)"
  cd = getData(cliq)
  cd.initialized = status
  if isready(cd.initDownChannel)
    @info "dumping stale cliq=$(cliq.index) status message $(take!(cd.initDownChannel)), replacing with $(status)"
  end
  put!(cd.initDownChannel, status)
  notify(getSolveCondition(cliq))
  # HACK to avoid a race condition that seems to occur ~1/20 times
  sleep(0.1)
  notify(getSolveCondition(cliq))
  nothing
end

"""
    $SIGNATURES

Return true if clique has completed the local upward direction inference procedure.
"""
isUpInferenceComplete(cliq::Graphs.ExVertex) = getData(cliq).upsolved

function areCliqVariablesAllInitialized(dfg::G, cliq::Graphs.ExVertex) where {G <: AbstractDFG}
  allids = getCliqAllVarIds(cliq)
  isallinit = true
  for vid in allids
    var = DFG.getVariable(dfg, vid)
    isallinit &= isInitialized(var)
  end
  isallinit
end

"""
   $SIGNATURES

Determine if this `cliq` has been fully initialized and child cliques have completed their full upward inference.
"""
function isCliqReadyInferenceUp(fgl::FactorGraph, tree::BayesTree, cliq::Graphs.ExVertex)
  isallinit = areCliqVariablesAllInitialized(fgl, cliq)

  # check that all child cliques have also completed full up inference.
  for chl in getChildren(tree, cliq)
    isallinit &= isUpInferenceComplete(chl)
  end
  return isallinit
end

"""
    $SIGNATURES

Blocking call until `cliq` upInit processes has arrived at a result.
"""
function getCliqInitUpResultFromChannel(cliq::Graphs.ExVertex)
  status = take!(getData(cliq).initUpChannel)
  @info "$(current_task()) Clique $(cliq.index), dumping initUpChannel status, $status"
  return status
end

"""
    $SIGNATURES

Return `::Symbol` status a particular clique is in, with specific regard to solution
or numerical initialization status:
- :needdownmsg
- :upsolved
- :downsolved
- :initialized
- :marginalized
- :null

Notes:
- `:null` represents the first uninitialized state of a cliq.
"""
getCliqStatus(cliqdata::BayesTreeNodeData)::Symbol = cliqdata.initialized
getCliqStatus(cliq::Graphs.ExVertex)::Symbol = getCliqStatus(getData(cliq))
getCliqStatusUp(cliq::Graphs.ExVertex)::Symbol = getCliqStatus(cliq)

"""
    $SIGNATURES

Set up initialization or solve status of this `cliq`.
"""
function setCliqStatus!(cliq::Graphs.ExVertex, status::Symbol)
  getData(cliq).initialized = status
end




"""
    $SIGNATURES

Return true if all variables in clique are considered marginalized (and initialized).
"""
function areCliqVariablesAllMarginalized(subfg::G,
                                         cliq::Graphs.ExVertex) where G <: AbstractDFG
  for vsym in getCliqAllVarIds(cliq)
    vert = getVert(subfg, vsym)
    if !isMarginalized(vert) || !isInitialized(vert)
      return false
    end
  end
  return true
end


"""
    $SIGNATURES

Set all Bayes (Junction) tree cliques that have all marginalized and initialized variables.
"""
function setTreeCliquesMarginalized!(dfg::G,
                                     tree::BayesTree) where G <: AbstractDFG
  #
  for (cliid, cliq) in tree.cliques
    if areCliqVariablesAllMarginalized(dfg, cliq)
      # need to set the upward messages
      msgs = prepCliqInitMsgsUp(dfg, cliq)
      setUpMsg!(cliq, msgs)

      prnt = getParent(tree, cliq)
      if length(prnt) > 0
        # THIS IS FOR INIT PASSES ONLY
        setCliqUpInitMsgs!(prnt[1], cliq.index, msgs)
      end

      setCliqStatus!(cliq, :marginalized)
      setCliqDrawColor(cliq, "blue")
    end
  end
  nothing
end


function blockCliqUntilParentDownSolved(prnt::Graphs.ExVertex)::Nothing

  while fetch(getData(prnt).initDownChannel) != :downsolved
    wait(getSolveCondition(prnt))
  end

  return nothing
end



"""
    $SIGNATURES

Block the thread until child cliques of `prnt::Graphs.ExVertex` have finished
attempting upward initialization -- i.e. have status result.
Return `::Dict{Symbol}` indicating whether next action that should be taken
for each child clique.

Notes:
- See status options at `getCliqStatusUp(..)`.
- Can be called multiple times
"""
function blockCliqUntilChildrenHaveUpStatus(tree::BayesTree,
                                            prnt::Graphs.ExVertex  )::Dict{Int, Symbol}
  #
  ret = Dict{Int, Symbol}()
  chlr = getChildren(tree, prnt)
  for ch in chlr
    # either wait to fetch new result, or report or result
    chst = getCliqStatusUp(ch)
    @info "$(current_task()) Clique $(prnt.index), child $(ch.index) status is $(chst), isready(initUpCh)=$(isready(getData(ch).initUpChannel))."
    ret[ch.index] = fetch(getData(ch).initUpChannel)
  end
  return ret
end

"""
    $SIGNATURES

Wait here if all siblings and the parent status are `:needdownmsg`.
Return true when parent is `:initialized` after all were `:needdownmsg`

Notes
- used for regulating long need down message chains.
- exit strategy is parent becomes status `:initialized`.
"""
function blockCliqSiblingsParentNeedDown(tree::BayesTree,
                                         cliq::Graphs.ExVertex)
  #
  # ret = Dict{Int, Symbol}()
  prnt = getParent(tree, cliq)
  allneeddwn = true
  if length(prnt) > 0
    prstat = getCliqStatus(prnt[1])
    if prstat == :needdownmsg
      for ch in getChildren(tree, prnt[1])
        chst = getCliqStatusUp(ch)
        if chst != :needdownmsg
          allneeddwn = false
        end
      end
      if allneeddwn
        @warn "$(current_task()) Clique $(cliq.index), block since all siblings/parent needdownmsg."
        prtmsg = fetch(getData(prnt[1]).initDownChannel)
        @info "$(current_task()) Clique $(prnt[1].index), blockCliqSiblingsParentNeedDown -- after fetch $prstat, $prtmsg"
        if prtmsg == :initialized
          return true
        else
          @warn "$(current_task()) Clique $(prnt[1].index), maybe clear down init message $prtmsg"
          # take!(getData(prnt[1]).initDownChannel)
        end
      end
    end
  end
  return false
end

"""
    $SIGNATURES

Cycle through var order and initialize variables as possible in `subfg::FactorGraph`.
Return true if something was updated.

Notes:
- assumed `subfg` is a subgraph containing only the factors that can be used.
  - including the required up or down messages
- intended for both up and down initialization operations.
"""
function cycleInitByVarOrder!(subfg::G, varorder::Vector{Symbol};logger=SimpleLogger(stdout))::Bool where G <: AbstractDFG
  with_logger(logger) do
    @info "cycleInitByVarOrder! -- varorder=$(varorder)"
  end
  retval = false
  count = 1
  while count > 0
    count = 0
    for vsym in varorder
      var = DFG.getVariable(subfg, vsym)
      isinit = isInitialized(var)
      with_logger(logger) do
        @info "var.label=$(var.label) is initialized=$(isinit)"
      end
      doautoinit!(subfg, [var;])
      if isinit != isInitialized(var)
        count += 1
        retval = true
      end
    end
  end
  with_logger(logger) do
    @info "cycleInitByVarOrder!, retval=$(retval)"
  end
  flush(logger.stream)
  return retval
end

"""
    $SIGNATURES

Update `subfg<:AbstractDFG` according to internal computations for a full upsolve.
"""
function doCliqUpSolve!(subfg::G,
                        tree::BayesTree,
                        cliq::Graphs.ExVertex  )::Symbol where G <: AbstractDFG
  #
  csym = getCliqFrontalVarIds(cliq)[1]
  # csym = DFG.getVariable(subfg, getCliqFrontalVarIds(cliq)[1]).label # ??
  approxCliqMarginalUp!(subfg, tree, csym, false)
  getData(cliq).upsolved = true
  return :upsolved
end

"""
    $SIGNATURES

Prepare the upward inference messages from clique to parent and return as `Dict{Symbol}`.
"""
function prepCliqInitMsgsUp(subfg::G,
                            cliq::Graphs.ExVertex)::TempBeliefMsg  where G <: AbstractDFG
  #
  # construct init's up msg to place in parent from initialized separator variables
  msg = TempBeliefMsg()
  for vid in getCliqSeparatorVarIds(cliq)
    var = DFG.getVariable(subfg, vid)
    if isInitialized(var)
      msg[Symbol(var.label)] = (getKDE(var), Bool[getData(var).partialinit;])
    end
  end
  return msg
end

function prepCliqInitMsgsUp(subfg::G, tree::BayesTree, cliq::Graphs.ExVertex)::TempBeliefMsg  where G <: AbstractDFG
  @warn "deprecated, use prepCliqInitMsgsUp(subfg::FactorGraph, cliq::Graphs.ExVertex) instead"
  prepCliqInitMsgsUp(subfg, cliq)
end


function doCliqAutoInitUpPart1!(subfg::G,
                                tree::BayesTree,
                                cliq::Graphs.ExVertex;
                                up_solve_if_able::Bool=true,
                                multiprocess::Bool=true,
                                logger=SimpleLogger(stdout) ) where {G <: AbstractDFG}
  #

  # init up msg has special procedure for incomplete messages
  varorder = Int[]

  # get incoming clique up messages
  upmsgs = getCliqInitUpMsgs(cliq)

  # add incoming up messages as priors to subfg
  with_logger(logger) do
    @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUpPart1! -- adding up message factors"
  end
  msgfcts = addMsgFactors!(subfg, upmsgs)

  # attempt initialize if necessary
  if !areCliqVariablesAllInitialized(subfg, cliq)
    # structure for all up message densities computed during this initialization procedure.
    varorder = getCliqInitVarOrderUp(cliq)
    # do physical inits, ignore cycle return value
    with_logger(logger) do
      @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUpPart1! -- going for up cycle order"
    end

    cycleInitByVarOrder!(subfg, varorder, logger=logger)
    with_logger(logger) do
      @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUpPart1! -- finished with up cycle order"
    end
  end
  flush(logger.stream)

  return msgfcts
end

"""
    $SIGNATURES

Perform cliq initalization calculation based on current state of the tree and factor graph,
using upward message passing logic.

> NOTE WORK IN PROGRESS

Notes
- Return either of (:initialized, :upsolved, :needdownmsg, :badinit)
- must use factors in cliq only, ensured by using subgraph -- TODO general case.
"""
function doCliqAutoInitUpPart2!(subfg::G,
                                tree::BayesTree,
                                cliq::Graphs.ExVertex,
                                msgfcts;
                                up_solve_if_able::Bool=true,
                                multiprocess::Bool=true )::Symbol where {G <: AbstractDFG}
  #
  cliqst = getCliqStatus(cliq)
  status = (cliqst == :initialized || length(getParent(tree, cliq)) == 0) ? cliqst : :needdownmsg

  # print out the partial init status of all vars in clique
  varids = getCliqAllVarIds(cliq)
  initstatus = Vector{Bool}(undef, length(varids))
  initpartial = Vector{Bool}(undef, length(varids))
  for i in 1:length(varids)
    initstatus[i] = getData(getVariable(subfg, varids[i])).initialized
    initpartial[i] = getData(getVariable(subfg, varids[i])).partialinit
  end
  @info "$(current_task()) Clique $(cliq.index), PARINIT: $varids | $initstatus | $initpartial"

  # check if all cliq vars have been initialized so that full inference can occur on clique
  if areCliqVariablesAllInitialized(subfg, cliq)
    @info "$(current_task()) Clique $(cliq.index), doCliqUpSolvePart2!, clique status = $(status)"
    status = doCliqUpSolve!(subfg, tree, cliq)
  else
    @info "$(current_task()) Clique $(cliq.index), all variables not initialized, status = $(status)"
  end

  # construct init's up msg to place in parent from initialized separator variables
  @info "$(current_task()) Clique $(cliq.index), going to prepCliqInitMsgsUp"
  msg = prepCliqInitMsgsUp(subfg, cliq) # , tree

  # put the init result in the parent cliq.
  prnt = getParent(tree, cliq)
  @info "$(current_task()) Clique $(cliq.index), prnt = getParent(tree, cliq) = $(prnt)"
  if length(prnt) > 0
    # not a root clique
    @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUpPart2! -- putting upinitmsg in prnt=$(prnt[1].index), with msgs for $(collect(keys(msg)))"
    setCliqUpInitMsgs!(prnt[1], cliq.index, msg)
  end

  # remove msg factors that were added to the subfg
  @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUpPart2! -- removing up message factors, length=$(length(msgfcts))"
  deleteMsgFactors!(subfg, msgfcts)

  # @info "$(current_task()) Clique $(cliq.index), doCliqAutoInitUp! -- sending notification of up init status=$status"
  # notifyCliqUpInitStatus!(cliq, status)
  return status
end


"""
    $SIGNATURES

Initialization downward message passing is different from regular inference since
it is possible that none of the child cliq variables have been initialized.

Notes
- init msgs from child upward passes are individually stored in this `cliq`.
- fresh product of overlapping beliefs are calculated on each function call.
"""
function prepCliqInitMsgsDown!(fgl::G,
                               tree::BayesTree,
                               cliq::Graphs.ExVertex ) where G <: AbstractDFG
  #
  @info "$(current_task()) Clique $(cliq.index), prepCliqInitMsgsDown!"
  # get the current messages stored in the parent
  currmsgs = getCliqInitUpMsgs(cliq)
  @info "$(current_task()) Clique $(cliq.index), cliq ids::Int=$(collect(keys(currmsgs)))"

  # check if any msgs should be multiplied together for the same variable
  msgspervar = Dict{Symbol, Vector{Tuple{BallTreeDensity,Vector{Bool}}}}()
  for (cliqid, msgs) in currmsgs
    for (msgsym, msg) in msgs
      if !haskey(msgspervar, msgsym)
        msgspervar[msgsym] = Vector{Tuple{BallTreeDensity,Vector{Bool}}}()
      end
      push!(msgspervar[msgsym], msg)
    end
  end

  @info "$(current_task()) Clique $(cliq.index), vars fw/ down msgs=$(collect(keys(msgspervar)))"

  # reference to default allocated dict location
  products = getData(cliq).downInitMsg
  # multiply multiple messages together
  for (msgsym, msgsBo) in msgspervar
    # check if this particular down message requires msgsym
    if DFG.hasVariable(fgl, msgsym) #haskey(fgl.IDs, msgsym)
      if length(msgspervar[msgsym]) > 1
        msgs = getindex.(msgsBo, 1)
        haspars = Bool[]
        for mb in msgsBo, val in mb[2]
            push!(haspars, val)
        end
        products[msgsym] = (manifoldProduct(msgs, getManifolds(fgl, msgsym)), haspars)
      else
        @show typeof(msgsBo)
        products[msgsym] = (msgsBo[1][1], Bool[msgsBo[1][2];])
      end
    else
      # not required, therefore remove from message to avoid confusion
      if haskey(products, msgsym)
        delete!(products, msgsym)
      end
    end
  end

  @info "$(current_task()) Clique $(cliq.index), product keys=$(collect(keys(products)))"
  return products
end

"""
    $SIGNATURES

Special function to do initialization in downward direction, assuming that not all
variables can be initialized.  Relies on outside down messages.

Notes:
- assumed this `cliq` is being initialized from a previous `:needdownmsg` status.
- will use all possible local factors of cliquq in initilization process
- similar to upward initialization, but uses different message structure
  - first draft assumes upward messages will not be used,
  - full up solve still required which explicitly depends on upward messages.
- TODO replace with nested 'minimum degree' type variable ordering
"""
function getCliqInitVarOrderDown(dfg::G,
                                 cliq::Graphs.ExVertex,
                                 downmsgs::TempBeliefMsg )::Vector{Symbol} where G <: AbstractDFG
  #
  allsyms = getCliqAllVarIds(cliq)
  # convert input downmsg var symbols to integers (also assumed as prior beliefs)
  # make sure ids are in the clique set, since parent may have more variables.
  dwnmsgsym = intersect(collect(keys(downmsgs)), DFG.getVariableIds(dfg)) #dfg.IDs
  # dwnmsgids =  map(x -> dfg.IDs[x], dwnmsgsym )
  dwnvarids = intersect(allsyms, dwnmsgsym)

  # find any other prior factors (might have partials)
  prvarids = getCliqVarIdsPriors(cliq, allsyms, true)
  hassinglids = union(dwnvarids, prvarids)

  # Get all other variable factor counts
  nfcts = getCliqNumAssocFactorsPerVar(cliq)
  # add msg marginal prior (singletons) to number of factors
  for msid in dwnmsgsym
    nfcts[msid .== allsyms] .+= 1
  end

  # sort permutation order for increasing number of factor association
  nfctsp = sortperm(nfcts)
  sortedids = allsyms[nfctsp]

  # all singleton variables
  singids = union(prvarids, dwnvarids)

  # organize the prior variables separately with asceding factor count
  initorder = Symbol[] #zeros(Int, 0)
  for id in sortedids
    if id in singids
      push!(initorder, id)
    end
  end
  # sort remaining variables for increasing associated factors
  for id in sortedids
    if !(id in initorder)
      push!(initorder, id)
    end
  end

  # return variable order
  return initorder
end

"""
    $SIGNATURES

Modify the `subfg::FactorGraph` to include `msgs` as priors that are used
during clique inference.

Notes
- May be used initialization or inference, in both upward and downward directions.

Related

`deleteMsgFactors!`
"""
function addMsgFactors!(subfg::G,
                        msgs::TempBeliefMsg)::Vector{DFGFactor} where G <: AbstractDFG
  # add messages as priors to this sub factor graph
  msgfcts = DFGFactor[]
  svars = DFG.getVariableIds(subfg)
  # mvid = getMaxVertId(subfg)
  for (msym, dm) in msgs
    if msym in svars
      # @show "adding down msg $msym"
      # mvid += 1

      # losing dm[2] partial information here
      # TODO prior missing manifold information
      fc = addFactor!(subfg, [msym], Prior(dm[1]), autoinit=false)
      push!(msgfcts, fc)
    end
  end
  return msgfcts
end

function addMsgFactors!(subfg::G,
                        msgs::Dict{Symbol, Vector{Tuple{BallTreeDensity, Vector{Bool}}}})::Vector{DFGFactor} where G <: AbstractDFG
  # add messages as priors to this sub factor graph
  msgfcts = DFGFactor[]
  svars = ls(subfg)
  # mvid = getMaxVertId(subfg)
  # bpvids = ls(subfg, r"bpp") # belief prop prior
  # mvid = length(bpvids) == 0 ? 0 : parse(Int, string(sortVarNested(bpvids)[end])[4:end])
  @warn "using hardcoded offst for msgFactors"
  # # TODO fix hardcoded id offset
  # mvid = 99999999000
  for (msym, dms) in msgs
    for dm in dms
      if msym in svars
        # @show "adding down msg $msym"
        # mvid += 1
        # TODO should be on manifold prior, not just generic euclidean prior -- okay since variable on manifold, but not for long term
        fc = addFactor!(subfg, [msym], Prior(dm[1]), autoinit=false) # , uid=mvid
        push!(msgfcts, fc)
      end
    end
  end
  return msgfcts
end

function addMsgFactors!(subfg::G,
                        allmsgs::Dict{Int,Dict{Symbol, Tuple{BallTreeDensity, Vector{Bool}}}})::Vector{DFGFactor} where G <: AbstractDFG
  #
  allfcts = DFGFactor[]
  for (cliqid, msgs) in allmsgs
    # do each dict in array separately
    newfcts = addMsgFactors!(subfg, msgs)
    union!( allfcts, newfcts )
  end
  return allfcts
end

"""
    $SIGNATURES

Delete from the subgraph`::FactorGraph` prior belief `msgs` that could/would be used
during clique inference.

Related

`addMsgFactors!`
"""
function deleteMsgFactors!(subfg::G,
                           fcts::Vector{DFGFactor}) where G <: AbstractDFG
  #
  for fc in fcts
    deleteFactor!(subfg, fc.label)
  end
end


"""
    $SIGNATURES

Return true or false depending on whether child cliques are all up solved.
"""
function areCliqChildrenAllUpSolved(treel::BayesTree,
                                    prnt::Graphs.ExVertex)::Bool
  #
  for ch in getChildren(treel, prnt)
    if !isCliqUpSolved(ch)
      return false
    end
  end
  return true
end


"""
    $SIGNATURES

Initialization requires down message passing of more specialized down init msgs.
This function performs any possible initialization of variables and retriggers
children cliques that have not yet initialized.

Notes:
- Assumed this function is only called after status from child clique up inits completed.
- Assumes cliq has parent.
  - will fetch message from parent
- Will perform down initialization if status == `:needdownmsg`.
- might be necessary to pass furhter down messges to child cliques that also `:needdownmsg`.
- Will not complete cliq solve unless all children are `:upsolved` (upward is priority).
- `dwinmsgs` assumed to come from parent initialization process.
- assume `subfg` as a subgraph that can be modified by this function (add message factors)
  - should remove message prior factors from subgraph before returning.
- May modify `cliq` values.
  - `setCliqUpInitMsgs!(cliq, cliq.index, msg)`
  - `setCliqStatus!(cliq, status)`
  - `setCliqDrawColor(cliq, "sienna")`
  - `notifyCliqDownInitStatus!(cliq, status)`

Algorithm:
- determine which downward messages influence initialization order
- initialize from singletons to most connected non-singletons
- revert back to needdownmsg if cycleInit does nothing
- can only ever return :initialized or :needdownmsg status
"""
function doCliqInitDown!(subfg::G,
                         cliq::Graphs.ExVertex,
                         dwinmsgs::TempBeliefMsg ) where G <: AbstractDFG
  #
  @info "$(current_task()) Clique $(cliq.index), doCliqInitDown! -- 1, dwinmsgs=$(collect(keys(dwinmsgs)))"
  status = :needdownmsg #:badinit

  # get down variable initialization order
  initorder = getCliqInitVarOrderDown(subfg, cliq, dwinmsgs)
  @info "$(current_task()) Clique $(cliq.index), doCliqInitDown! -- 4, initorder=$(initorder))"

  # add messages as priors to this sub factor graph
  msgfcts = addMsgFactors!(subfg, dwinmsgs)

  # cycle through vars and attempt init
  @info "$(current_task()) Clique $(cliq.index), doCliqInitDown! -- 5, cycle through vars and attempt init"
  if cycleInitByVarOrder!(subfg, initorder)
    status = :initialized
  end

  @info "$(current_task()) Clique $(cliq.index), doCliqInitDown! -- 6, current status: $status"
  # remove msg factors previously added
  deleteMsgFactors!(subfg, msgfcts)

  @info "$(current_task()) Clique $(cliq.index), doCliqInitDown! -- 7, current status: $status"

  return status
end

function doCliqInitDown!(subfg::G,
                         tree::BayesTree,
                         cliq::Graphs.ExVertex  ) where G <: AbstractDFG
  #
  @warn "deprecated doCliqInitDown!(subfg, tree, cliq) use doCliqInitDown!(subfg, cliq, dwinmsgs) instead."
  prnt = getParent(tree, cliq)[1]
  dwinmsgs = prepCliqInitMsgsDown!(subfg, tree, prnt)
  status = doCliqInitDown!(subfg, cliq, dwinmsgs)

  return status
end


"""
    $SIGNATURES

Return `true` if any of the children cliques have status `:needdownmsg`.
"""
function areCliqChildrenNeedDownMsg(children::Vector{Graphs.ExVertex})::Bool
  for ch in children
    if getCliqStatus(ch) == :needdownmsg
      return true
    end
  end
  return false
end

function areCliqChildrenNeedDownMsg(tree::BayesTree, cliq::Graphs.ExVertex)::Bool
  areCliqChildrenNeedDownMsg( getChildren(tree, cliq) )
end


"""
    $SIGNATURES

Return true if has parent with status `:needdownmsg`.
"""
function isCliqParentNeedDownMsg(tree::BayesTree, cliq::Graphs.ExVertex)
  prnt = getParent(tree, cliq)
  if length(prnt) == 0
    return false
  end
  prstat = getCliqStatus(prnt[1])
  @info "$(current_task()) Clique $(cliq.index), isCliqParentNeedDownMsg -- parent status: $(prstat)"
  return prstat == :needdownmsg
end
