module HuntBadia2024SequentialTests

using SparseArrays
using GridapMHD: hunt

# Badia2024, with LU factorisation for u-j sub-block
solver = Dict(
  :solver         => :badia2024,
  :matrix_type    => SparseMatrixCSC{Float64,Int64},
  :vector_type    => Vector{Float64},
  :petsc_options  => "-ksp_error_if_not_converged true -ksp_converged_reason",
  :block_solvers  => [:julia,:cg_jacobi,:cg_jacobi],
)
hunt(
  nc=(6,6),
  np=(1,1),
  backend=:mpi,
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=solver,
  ζ=100.0,
  order = 2,
  order_j = 2,
  fluid_disc = :RT,
)

# Badia2024, with GMG solver for u-j sub-block
solver = Dict(
  :solver         => :badia2024,
  :matrix_type    => SparseMatrixCSC{Float64,Int64},
  :vector_type    => Vector{Float64},
  :petsc_options  => "-ksp_error_if_not_converged true -ksp_converged_reason",
  :block_solvers  => [:gmg,:cg_jacobi,:cg_jacobi],
)
hunt(
  nc=(6,6),
  np=(1,1),
  backend=:mpi,
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=solver,
  ζ=50.0,
  ranks_per_level=[1,1],
  BL_adapted=false,
)

end # module