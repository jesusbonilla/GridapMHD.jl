module HuntTestsSequential

using GridapMHD: hunt

hunt(
  nc=(4,4),
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=:block_gmres_li2019,
)

hunt(
  nc=(4,4),
  L=1.0,
  B=(0.,50.,0.),
  debug=true,
  vtk=true,
  title="hunt",
  solver=:julia,
 )

hunt(
  nc=(4,4),
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=:julia,
 )

hunt(
  nc=(4,4),
  np=(1,1),
  backend=:mpi,
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=:julia,
 )

hunt(
  nc=(4,4),
  np=(2,2),
  backend=:sequential,
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=:julia,
 )

hunt(
  nc=(4,4),
  np=(2,2),
  backend=:sequential,
  L=1.0,
  B=(0.,50.,0.),
  debug=false,
  vtk=true,
  title="hunt",
  solver=:petsc,
)

end # module

