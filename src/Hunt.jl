

function hunt(;nx::Int=3, ny::Int=3, Re::Float64 = 10.0, Ha::Float64 = 10.0,
    U0::Float64 = Re, B0::Float64 = Ha, L::Float64 = 1.0, resultsfile = nothing)

  reset_timer!()

  @timeit "model" begin
  N = Ha^2/Re
  K = Ha / (1-0.95598*Ha^(-1/2)-Ha^(-1))
  ∂p∂z = -L^3 * K / Re

  f_u(x) = VectorValue(0.0,0.0, -∂p∂z) * L/U0^2
  g_u = VectorValue(0.0,0.0,0.0)
  g_j = VectorValue(0.0,0.0,0.0)
  g_φ = 0.0
  B = VectorValue(0.0,Ha,0.0)/B0

  # Discretization
  order = 2
  domain = (-1.0,1.0,-1.0,1.0,0.0,0.1)
  map(x) = VectorValue(sign(x[1])*(abs(x[1])*0.5)^0.5,
                       sign(x[2])*(abs(x[2])*0.5)^0.5,  x[3])*2/sqrt(2)


  dirichlet_tags_u = append!(collect(1:20),[23,24,25,26])
  dirichlet_tags_j = append!(collect(1:20),[25,26])

  partition=(nx,ny,3)
  model = CartesianDiscreteModel(domain,partition;
    isperiodic=(false,false,true), map=map)

  labels = get_face_labeling(model)
  add_tag_from_tags!(labels,"dirichlet_u",dirichlet_tags_u)
  add_tag_from_tags!(labels,"dirichlet_j",dirichlet_tags_j)
  end
  @timeit "FE spaces" begin
  Vu = FESpace(
    reffe=:Lagrangian, order=order, valuetype=VectorValue{3,Float64},
    conformity=:H1, model=model, dirichlet_tags="dirichlet_u")

  Vp = FESpace(
    reffe=:PLagrangian, order=order-1, valuetype=Float64,
    conformity=:L2, model=model)

  Vj = FESpace(
    reffe=:RaviartThomas, order=order-1, valuetype=VectorValue{3,Float64},
    conformity=:Hdiv, model=model, dirichlet_tags="dirichlet_j")

  Vφ = FESpace(
    reffe=:QLagrangian, order=order-1, valuetype=Float64,
    conformity=:L2, model=model)

  U = TrialFESpace(Vu,g_u)
  P = TrialFESpace(Vp)
  J = TrialFESpace(Vj,g_j)
  Φ = TrialFESpace(Vφ)

  Y = MultiFieldFESpace([Vu, Vp, Vj, Vφ])
  X = MultiFieldFESpace([U, P, J, Φ])
  end

  @timeit "Integration" begin
  # Integration
  trian = Triangulation(model)
  degree = 2*(order)
  quad = CellQuadrature(trian,degree)

  res(x,y) = InductionlessMHD.dimensionless_residual(x, y, Re, N, B, f_u)
  jac(x,dx,y) = InductionlessMHD.dimensionless_jacobian(x, dx, y, Re, N, B)

  t_Ω = FETerm(res,jac,trian,quad)
  op  = FEOperator(X,Y,t_Ω)
  end

  @timeit "Setup solver" begin
  # Solver
  nls = NLSolver(GmresSolver(preconditioner=ilu,τ=1e-6);
    show_trace=true, method=:newton, linesearch=BackTracking())
  solver = FESolver(nls)
  end

  @timeit "solve" xh = solve(solver,op)

  print_timer()
  println()

  if resultsfile != nothing
    uh, ph, jh, φh = xh
    writevtk(trian, resultsfile,
      cellfields=["uh"=>uh, "ph"=>ph, "jh"=>jh, "φh"=>φh])
  end
  (xh, trian, quad)
end


function analytical_hunt_u(a::Float64,       # semi-length of side walls
                           b::Float64,       # semi-length of Hartmann walls
                           μ::Float64,       # fluid viscosity
                           grad_pz::Float64, # presure gradient
                           Ha::Float64,      # Hartmann number
                           n::Int,           # number of sumands included in Fourier series
                           x)                # evaluation point
  l = b/a
  ξ = x[1]/a
  η = x[2]/a

  V = 0.0; V0=0.0;
  for k in 0:n
    α_k = (k + 0.5)*π/l
    N = (Ha^2 + 4*α_k^2)^(0.5)
    r1_k = 0.5*( Ha + N)
    r2_k = 0.5*(-Ha + N)

    num = exp(-r1_k*(1-η))+exp(-r1_k*(1+η))
    den = 1+exp(-2*r1_k)
    V2 = (r2_k/N)*(num/den)

    num = exp(-r2_k*(1-η))+exp(-r2_k*(1+η))
    den = 1+exp(-2*r2_k)
    V3 = (r1_k/N)*(num/den)


    V += 2*(-1)^k*cos(α_k * ξ)/(l*α_k^3) * (1-V2-V3)
  end
  u_z = V/μ * (-grad_pz) * a^2

  return VectorValue(0.0*u_z,0.0*u_z,u_z)
end


function analytical_hunt_j(a::Float64,       # semi-length of side walls
                           b::Float64,       # semi-length of Hartmann walls
                           σ::Float64,       # fluid conductivity
                           μ::Float64,       # fluid viscosity
                           grad_pz::Float64, # presure gradient
                           Ha::Float64,      # Hartmann number
                           n::Int,           # number of sumands included in Fourier series
                           x)                # evaluation point
  l = b/a
  ξ = x[1]/a
  η = x[2]/a

  H_dx = 0.0; H_dy = 0.0
  for k in 0:n
    α_k = (k + 0.5)*π/l
    N = sqrt(Ha^2 + 4*α_k^2)
    r1_k = 0.5*( Ha + N)
    r2_k = 0.5*(-Ha + N)

    num = exp(-r1_k*(1-η)) - exp(-r1_k*(1+η))
    num_dy = exp(-r1_k*(1-η))*(r1_k/a) + exp(-r1_k*(1+η))*(r1_k/a)
    den = 1+exp(-2*r1_k)
    H2 = (r2_k/N)*(num/den)
    H2_dy = (r2_k/N)*(num_dy/den)

    num = exp(-r2_k*(1-η)) - exp(-r2_k*(1+η))
    num_dy = exp(-r2_k*(1-η))*(r2_k/a) + exp(-r2_k*(1+η))*(r2_k/a)
    den = 1+exp(-2*r2_k)
    H3 = (r1_k/N)*(num/den)
    H3_dy = (r1_k/N)*(num_dy/den)

    H_dx += -2*(-1)^k * sin(α_k * ξ)/(a*l*α_k^2) * (H2 - H3)
    H_dy += 2*(-1)^k * cos(α_k * ξ)/(l*α_k^3) * (H2_dy - H3_dy)
  end
  j_x = a^2*σ^0.5 / μ^0.5 * (-grad_pz) * H_dy
  j_y = a^2*σ^0.5 / μ^0.5 * (-grad_pz) * (-H_dx)

  return VectorValue(j_x,j_y,0.0)
end