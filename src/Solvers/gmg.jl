
function get_block_solver(::Val{:gmg},params)
  vars = Tuple(params[:multigrid][:variables])
  gmg_solver(Val(vars),params)
end

function gmg_solver(::Val{(1,3)},params)
  mh = params[:multigrid][:mh]

  trials = MultiFieldFESpace(map(s -> s, params[:multigrid][:trials][[1,3]]))
  tests  = MultiFieldFESpace(map(s -> s, params[:multigrid][:tests][[1,3]]))
  tests_u, tests_j = params[:multigrid][:tests][1], params[:multigrid][:tests][3]
  
  nlevs = num_levels(mh)
  k = params[:fespaces][:k]
  qdegree = map(lev -> 2*k+1,1:nlevs)
  
  function jacobian_uj(model)
    _, dΩf, α, β, γ, σf, f, B, ζ = retrieve_fluid_params(model,params,k)
    _, dΩs, σs = retrieve_solid_params(model,params,k)
    _, params_thin_wall, _, _ = retrieve_bcs_params(model,params,k)
    Πp = params[:fespaces][:Πp]
    function a(x,dx,y)
      u, j = x
      du, dj = dx
      v_u, v_j = y
      r = a_mhd_u_u(du,v_u,β,dΩf) + a_mhd_u_j(dj,v_u,γ,B,dΩf) + a_mhd_j_u(du,v_j,σf,B,dΩf) + a_mhd_j_j(dj,v_j,dΩf)
      r = r + dc_mhd_u_u(u,du,v_u,α,dΩf)
      for p in params_thin_wall
        r = r + a_thin_wall_j_j(dj,v_j,p...)
      end
      if !isnothing(dΩs)
        r = r + a_solid_j_j(dj,v_j,dΩs)
      end
      if abs(ζ) > eps(typeof(ζ))
        r = r + a_al_u_u(du,v_u,ζ,Πp,dΩf) + a_al_j_j(dj,v_j,ζ,dΩf)
      end
      return r
    end
    return a
  end

  function jacobian_u(model)
    _, dΩf, α, β, γ, σf, f, B, ζ = retrieve_fluid_params(model,params,k)
    Πp = params[:fespaces][:Πp]
    function a(u,du,v_u)
      r = a_mhd_u_u(du,v_u,β,dΩf) + dc_mhd_u_u(u,du,v_u,α,dΩf)
      if abs(ζ) > eps(typeof(ζ))
        r = r + a_al_u_u(du,v_u,ζ,Πp,dΩf)
      end
      return r
    end
    return a
  end

  function projection_rhs(model)
    _, dΩf, α, β, γ, σf, f, B, ζ = retrieve_fluid_params(model,params,k)
    Πp = params[:fespaces][:Πp]
    l(du,v_u) = a_al_u_u(du,v_u,ζ,Πp,dΩf)
    return l
  end

  patch_decompositions = PatchDecomposition(mh)
  smatrices = gmg_matrices(mh,trials,tests,jacobian_uj)
  smoothers = gmg_patch_smoothers(mh,patch_decompositions,trials,jacobian_uj)

  restrictions = setup_restriction_operators(tests,qdegree;mode=:residual,solver=LUSolver())
  prolongations_u = gmg_patch_prolongations(tests_u,patch_decompositions,jacobian_u,projection_rhs)
  prolongations_j = setup_prolongation_operators(tests_j,qdegree)
  prolongations = MultiFieldTransferOperator(tests,[prolongations_u,prolongations_j])
  transfer_ops = restrictions, prolongations

  return gmg_solver(mh,transfer_ops,smoothers,smatrices)
end

function gmg_solver(mh,transfer_ops,smoothers,smatrices)
  ranks = get_level_parts(mh,1)
  restrictions, prolongations = transfer_ops

  cranks = get_level_parts(mh,num_levels(mh))
  coarsest_solver = (length(cranks) == 1) ? LUSolver() : PETScLinearSolver(petsc_mumps_setup)

  gmg = GMGLinearSolver(mh,smatrices,prolongations,restrictions,
                        pre_smoothers=smoothers,
                        post_smoothers=smoothers,
                        coarsest_solver=coarsest_solver,
                        maxiter=3,verbose=true,mode=:preconditioner)
  gmg.log.depth += 4
  solver = FGMRESSolver(10,gmg;m_add=5,maxiter=30,rtol=1.0e-6,verbose=i_am_main(ranks),name="UJ Block - FGMRES+GMG")
  solver.log.depth += 3 # For printing purposes
  return solver
end

function gmg_matrices(mh,trials,tests,weakform)
  nlevs = num_levels(trials)

  mats = Vector{PSparseMatrix}(undef,nlevs)
  for lev in 1:nlevs
    parts = get_level_parts(mh,lev)
    if i_am_in(parts)
      model = GridapSolvers.get_model(mh,lev)
      U = GridapSolvers.get_fe_space(trials,lev)
      V = GridapSolvers.get_fe_space(tests,lev)
      u0 = zero(U)
      jac = weakform(model)
      a(u,v) = jac(u0,u,v)
      mats[lev] = assemble_matrix(a,U,V)
    end
  end
  return mats
end

function gmg_patch_smoothers(mh,patch_decompositions,tests,weakform)
  patch_spaces = PatchFESpace(tests,patch_decompositions)

  nlevs = num_levels(mh)
  smoothers = Vector{RichardsonSmoother}(undef,nlevs-1)
  for lev in 1:nlevs-1
    parts = get_level_parts(mh,lev)
    if i_am_in(parts)
      PD = patch_decompositions[lev]
      Ph = GridapSolvers.get_fe_space(patch_spaces,lev)
      Vh = GridapSolvers.get_fe_space(tests,lev)
      a = weakform(PD)
      patch_smoother = PatchBasedLinearSolver(a,Ph,Vh,is_nonlinear=true)
      smoothers[lev] = RichardsonSmoother(patch_smoother,10,0.2)
    end
  end
  return smoothers
end

function gmg_patch_prolongations(tests,patch_decompositions,lhs,rhs)
  mh = tests.mh
  nlevs = num_levels(mh)
  prolongations = Vector{PatchProlongationOperator}(undef,nlevs-1)
  for lev in 1:nlevs-1
    parts = get_level_parts(mh,lev)
    if i_am_in(parts)
      qdegree = 1 # Does not matter, it is not used... TODO
      Vh = GridapSolvers.get_fe_space(tests,lev)
      PD = patch_decompositions[lev]
      u0 = zero(Vh)
      lhs_i(u,v) = lhs(PD)(u0,u,v)
      rhs_i = rhs(PD)
      prolongations[lev] = PatchProlongationOperator(lev,tests,PD,lhs_i,rhs_i,qdegree)
    end
  end
  return prolongations
end
