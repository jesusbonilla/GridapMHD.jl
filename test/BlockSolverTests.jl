
using Gridap, GridapDistributed, GridapSolvers
using Gridap.MultiField
using Gridap.Algebra

using LinearAlgebra, BlockArrays

using GridapSolvers.LinearSolvers: allocate_col_vector, allocate_row_vector

using GridapMHD: _hunt, add_default_params, _fluid_mesh, weak_form, _find_backend, p_conformity, _interior

function Gridap.Algebra._check_convergence(nls,b,m0)
  m = Gridap.Algebra._inf_norm(b)
  println(">>>>>>>>>>>>>>>>>>>> Nonlinear Abs Error = $m")
  m < nls.tol * m0
end
function Gridap.Algebra._check_convergence(nls,b)
  m0 = Gridap.Algebra._inf_norm(b)
  println(">>>>>>>>>>>>>>>>>>>> Starting nonlinear solver")
  println(">>>>>>>>>>>>>>>>>>>> Nonlinear Abs Error = $m0")
  (false, m0)  
end

"""
  This preconditioner is based on [(Li,2019)](https://doi.org/10.1137/19M1260372)
"""
struct MHDBlockPreconditioner <: Gridap.Algebra.LinearSolver
  Dj_solver
  Fk_solver
  Δp_solver
  Ip_solver
  Iφ_solver
  Dj
  Δp
  Ip
  Ij
  Iφ
  params
end

struct MHDBlockPreconditionerSS <: Gridap.Algebra.SymbolicSetup
  solver
end

function Gridap.Algebra.symbolic_setup(solver::MHDBlockPreconditioner, A::AbstractMatrix)
  return MHDBlockPreconditionerSS(solver)
end

mutable struct MHDBlockPreconditionerNS <: Gridap.Algebra.NumericalSetup
  solver
  Dj_ns
  Fk_ns
  Δp_ns
  Ip_ns
  Iφ_ns
  sysmat
  caches
end

function allocate_preconditioner_caches(solver,A::BlockMatrix)
  du = allocate_col_vector(A[Block(1,1)])
  dp = allocate_col_vector(A[Block(2,2)])
  dj = allocate_col_vector(A[Block(3,3)])
  dφ = allocate_col_vector(A[Block(4,4)])
  return du, dp, dj, dφ
end

function Gridap.Algebra.numerical_setup(ss::MHDBlockPreconditionerSS, A::BlockMatrix)
  solver = ss.solver

  Fu = A[Block(1,1)]; K = A[Block(3,1)]; Kᵗ = A[Block(1,3)]; κ = solver.params[:fluid][:γ]
  Fk = Fu - (1.0/κ^2) * Kᵗ * K

  Dj_ns = numerical_setup(symbolic_setup(solver.Dj_solver,solver.Dj),solver.Dj)
  Fk_ns = numerical_setup(symbolic_setup(solver.Fk_solver,Fk),Fk)
  Δp_ns = numerical_setup(symbolic_setup(solver.Δp_solver,solver.Δp),solver.Δp)
  Ip_ns = numerical_setup(symbolic_setup(solver.Δp_solver,solver.Ip),solver.Ip)
  Iφ_ns = numerical_setup(symbolic_setup(solver.Iφ_solver,solver.Iφ),solver.Iφ)
  caches = allocate_preconditioner_caches(solver,A)
  return MHDBlockPreconditionerNS(ss.solver,Dj_ns,Fk_ns,Δp_ns,Ip_ns,Iφ_ns,A,caches)
end

function Gridap.Algebra.numerical_setup!(ns::MHDBlockPreconditionerNS, A::BlockMatrix)
  solver = ns.solver

  #! Pattern of matrix changes, so we need to recompute everything.
  # This will get fixed when we are using iterative solvers for Fk
  Fu = A[Block(1,1)]; K = A[Block(3,1)]; Kᵗ = A[Block(1,3)]; κ = solver.params[:fluid][:γ]
  Fk = Fu - (1.0/κ^2) * Kᵗ * K
  # numerical_setup!(ns.Fk_ns,Fk)

  ns.Fk_ns  = numerical_setup(symbolic_setup(solver.Fk_solver,Fk),Fk)
  ns.sysmat = A

  return ns
end

# Follows Algorithm 4.1 in (Li,2019)
function Gridap.Algebra.solve!(x::BlockVector,ns::MHDBlockPreconditionerNS,b::BlockVector)
  sysmat, caches, params = ns.sysmat, ns.caches, ns.solver.params
  fluid = params[:fluid]; ζ = params[:ζ]; iRe = fluid[:β]
  κ = fluid[:γ]; α1 = ζ + iRe;

  bu, bp, bj, bφ = blocks(b)
  u, p, j, φ = blocks(x)
  du, dp, dj, dφ = caches

  # Solve for p
  solve!(p,ns.Δp_ns,bp)
  solve!(dp,ns.Ip_ns,bp)
  p .= -α1 .* dp .- p

  #  Solve for φ
  #dφ .= -bφ
  solve!(φ,ns.Iφ_ns,bφ)

  # Solve for u
  copy!(du,bu); mul!(du,sysmat[Block(1,2)],p,-1.0,1.0) # du = bu - Aup * p
  solve!(u,ns.Fk_ns,du) # u = Fu \ (bu - Aup * p)

  # Solve for j
  copy!(dj,bj)
  mul!(dj,sysmat[Block(3,1)],u,-2.0,1.0) # dj = bj - 2.0 * Aju * u
  mul!(dj,sysmat[Block(3,4)],φ,-2.0,1.0) # dj = bj - 2.0 * Aju * u - 2.0 * Ajφ * φ
  solve!(j,ns.Dj_ns,dj) # j = Dj \ (bj - 2.0 * Aju * u - 2.0 * Ajφ * φ)

  return x
end

function hunt(;
  backend = nothing,
  np      = nothing,
  title   = "hunt",
  nruns   = 1,
  path    = ".",
  kwargs...)

  for ir in 1:nruns
    _title = title*"_r$ir"
    if isa(backend,Nothing)
      @assert isa(np,Nothing)
      return _hunt(;title=_title,path=path,kwargs...)
    else
      @assert backend ∈ [:sequential,:mpi]
      @assert !isa(np,Nothing)
      if backend == :sequential
        return with_debug() do distribute
          _hunt(;distribute=distribute,rank_partition=np,title=_title,path=path,kwargs...)
        end
      else
        return with_mpi() do distribute
          _hunt(;distribute=distribute,rank_partition=np,title=_title,path=path,kwargs...)
        end
      end
    end
end

_params = hunt(
  nc=(4,4),
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=false,
  solver=:block_gmres,
)

mfs = BlockMultiFieldStyle()
params = add_default_params(_params)

# ReferenceFEs
k = params[:k]
T = Float64
model = params[:model]
D = num_cell_dims(model)
reffe_u = ReferenceFE(lagrangian,VectorValue{D,T},k)
reffe_p = ReferenceFE(lagrangian,T,k-1;space=:P)
reffe_j = ReferenceFE(raviart_thomas,T,k-1)
reffe_φ = ReferenceFE(lagrangian,T,k-1)

# Test spaces
Ωf  = _fluid_mesh(model,params[:fluid][:domain])
V_u = TestFESpace(Ωf,reffe_u;dirichlet_tags=params[:bcs][:u][:tags])
V_p = TestFESpace(Ωf,reffe_p;conformity=p_conformity(Ωf))
V_j = TestFESpace(model,reffe_j;dirichlet_tags=params[:bcs][:j][:tags])
V_φ = TestFESpace(model,reffe_φ;conformity=:L2)
V   = MultiFieldFESpace([V_u,V_p,V_j,V_φ];style=mfs)

# Trial spaces
z = zero(VectorValue{D,Float64})
u_bc = params[:bcs][:u][:values]
j_bc = params[:bcs][:j][:values]
U_u  = u_bc == z ? V_u : TrialFESpace(V_u,u_bc)
U_j  = j_bc == z ? V_j : TrialFESpace(V_j,j_bc)
U_p  = TrialFESpace(V_p)
U_φ  = TrialFESpace(V_φ)
U = MultiFieldFESpace([U_u,U_p,U_j,U_φ];style=mfs)

# Weak form
#! ζ adds an Augmented-Lagragian term to both the preconditioner and teh weak form. 
#! Set to zero if not needed.
params[:ζ] = 100.0
res, jac = weak_form(params,k)
Tm = params[:matrix_type]
Tv = params[:vector_type]
assem = SparseMatrixAssembler(Tm,Tv,U,V)
op    = FEOperator(res,jac,U,V,assem)
al_op = Gridap.FESpaces.get_algebraic_operator(op)

# Preconditioner
γ = params[:fluid][:γ]

Ω = Triangulation(model)
Γ = Boundary(model)
Λ = Skeleton(model)

dΩ = Measure(Ω,2*k)
dΓ = Measure(Γ,2*k)
dΛ = Measure(Λ,2*k)

n_Γ = get_normal_vector(Γ)
n_Λ = get_normal_vector(Λ)

h_e_Λ = CellField(get_array(∫(1)dΛ),Λ)
h_e_Γ = CellField(get_array(∫(1)dΓ),Γ)

β = 100.0
aΛ(u,v) = ∫(-jump(u⋅n_Λ)⋅mean(∇(v)) - mean(∇(u))⋅jump(v⋅n_Λ))*dΛ + ∫(β/h_e_Λ*jump(u⋅n_Λ)⋅jump(v⋅n_Λ))*dΛ
aΓ(u,v) = ∫(-(∇(u)⋅n_Γ)⋅v - u⋅(∇(v)⋅n_Γ))*dΓ + ∫(β/h_e_Γ*(u⋅n_Γ)⋅(v⋅n_Γ))*dΓ

ap(p,v_p) = ∫(∇(p)⋅∇(v_p))*dΩ + aΛ(p,v_p) + aΓ(p,v_p)

Dj = assemble_matrix((j,v_j) -> ∫(γ*j⋅v_j + γ*(∇⋅j)⋅(∇⋅v_j))*dΩ ,U_j,V_j)
Ij = assemble_matrix((j,v_j) -> ∫(j⋅v_j)*dΩ ,U_j,V_j)
Δp = assemble_matrix(ap ,U_p,V_p)
Ip = assemble_matrix((p,v_p) -> ∫(p*v_p)*dΩ,V_p,V_p)
Iφ = assemble_matrix((φ,v_φ) -> ∫(-γ*φ*v_φ)*dΩ ,U_φ,V_φ)

Dj_solver = LUSolver()
Fk_solver = LUSolver()
Δp_solver = LUSolver()
Ip_solver = LUSolver()
Iφ_solver = LUSolver()

block_solvers = [Dj_solver,Fk_solver,Δp_solver,Ip_solver,Iφ_solver]
block_mats = [Dj,Δp,Ip,Ij,Iφ]
P = MHDBlockPreconditioner(block_solvers...,block_mats...,params)

sysmat_solver = GMRESSolver(300,P,1e-8)

# Gridap's Newton-Raphson solver
xh = zero(U)
sysvec = residual(op,xh)
sysmat = jacobian(op,xh)
sysmat_ns = numerical_setup(symbolic_setup(sysmat_solver,sysmat),sysmat)

x  = allocate_col_vector(sysmat)
dx = allocate_col_vector(sysmat)
b  = allocate_col_vector(sysmat)

# copy!(b,sysvec)
# b0 = norm(b)

# rmul!(b,-1.0)
# solve!(dx,sysmat_ns,b)
# x .+= dx

# residual!(b,al_op,x)
# norm(b)

A = allocate_jacobian(al_op,x)
nlsolver = NewtonRaphsonSolver(sysmat_solver,1e-5,10)
nlsolver_cache = Gridap.Algebra.NewtonRaphsonCache(A,b,dx,sysmat_ns)
solve!(x,nlsolver,al_op,nlsolver_cache)