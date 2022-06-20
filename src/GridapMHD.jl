module GridapMHD

using Random
using SparseArrays
using SparseMatricesCSR
using PartitionedArrays
using Gridap
using Gridap.Helpers
using Gridap.Algebra
using Gridap.CellData
using Gridap.ReferenceFEs
using Gridap.Geometry
using GridapGmsh
using Gridap.FESpaces
using GridapDistributed
using GridapPETSc
using GridapPETSc.PETSC
using FileIO
using BSON
using GridapGmsh


include("Main.jl")

include("Hunt.jl")

include("expansion.jl")

include("FCI_entrance.jl")

end # module
