module PeriodicPoissonTests

include("../src/GridapMHD.jl")
using .GridapMHD
# using GridapMHD

using Gridap
using Test


# topology triangulations for a 2x2 mesh with periodic bc in x
cell_to_vertices = [[1 2 3 4]
                    [2 1 4 3]
                    [3 4 5 6]
                    [4 3 6 5]];
cell_to_faces = [[1  2 3 4]
                 [5  6 4 3]
                 [2  7 8 9]
                 [6 10 9 8]];

faces_to_verties = [[1 2]
                    [3 4]
                    [1 3]
                    [2 4]
                    [1 2]  # <=
                    [3 4]  # <=
                    [5 6]
                    [3 5]
                    [4 6]
                    [5 6]]; # <=

function main()
  model = CartesianDiscreteModel((0,1,0,1),(3,3),[1])
end

model = main()


@show model.grid_topology.n_m_to_nface_to_mfaces[3,1]
@show model.grid_topology.n_m_to_nface_to_mfaces[3,2]
@show model.grid_topology.n_m_to_nface_to_mfaces[2,1]



# using Gridap
# using Gridap.Arrays: CompressedArray
# using Gridap.Geometry: get_cell_type
# using Test
#
#
# model = CartesianDiscreteModel((0,1,0,1),(3,3),[2])
#
# labels = get_face_labeling(model)
# add_tag_from_tags!(labels,"dirichlet",[1,2,3,4,5,6])
#
# trian = get_triangulation(model)
#
# itrian = SkeletonTriangulation(model)
#
# nb = get_normal_vector(itrian)
#
# s = CompressedArray([Point{1,Float64}[(0,)]],get_cell_type(itrian))
#
# normals = evaluate(nb,s)
#
# for (i,normal) in enumerate(normals)
#     @show itrian.left.face_trian.cell_to_oldcell[i], normal
# end
#
# btrian = BoundaryTriangulation(model)
#
# nb = get_normal_vector(btrian)
#
# s = CompressedArray([Point{1,Float64}[(0,)]],get_cell_type(btrian))
#
# normals = evaluate(nb,s)
#
# for (i,normal) in enumerate(normals)
#     @show btrian.face_trian.cell_to_oldcell[i], normal
# end
#
# order = 1
# V = FESpace(
#      reffe=:RaviartThomas, order=order, valuetype=VectorValue{2,Float64},
#      conformity=:Hdiv, model=model)
#
# u(x) = VectorValue(1.0,1.0)
# uh = interpolate(V,u)
#
# writevtk(trian,"test",cellfields=["u"=>uh])
#
# end #module

# 3 1
# [[1, 2, 4, 5], [2, 3, 5, 6], [3, 1, 6, 4], [4, 5, 7, 8], [5, 6, 8, 9], [6, 4, 9, 7], [7, 8, 10, 11], [8, 9, 11, 12], [9, 7, 12, 10]]

# 3 2
# [[1, 2, 3, 4], [5, 6, 4, 7], [8, 9, 7, 3], [2, 10, 11, 12], [6, 13, 12, 14], [9, 15, 14, 11], [10, 16, 17, 18], [13, 19, 18, 20], [15, 21, 20, 17]]

# 2 1
# [[1, 2], [4, 5], [1, 4], [2, 5], [2, 3], [5, 6], [3, 6], [3, 1], [6, 4], [7, 8], [4, 7], [5, 8], [8, 9], [6, 9], [9, 7], [10, 11], [7, 10], [8, 11], [11, 12], [9, 12], [12, 10]]


# 1 2
#  [1, 3, 8]
#  [1, 4, 5]
#  [5, 7, 8]
#  [2, 3, 9, 11]
#  [2, 4, 6, 12]
#  [6, 7, 9, 14]
#  [10, 11, 15, 17]
#  [10, 12, 13, 18]
#  [13, 14, 15, 20]
#  [16, 17, 21]
#  [16, 18, 19]
#  [19, 20, 21]


# 1 3
#  [1, 3]
#  [1, 2]
#  [2, 3]
#  [1, 3, 4, 6]
#  [1, 2, 4, 5]
#  [2, 3, 5, 6]
#  [4, 6, 7, 9]
#  [4, 5, 7, 8]
#  [5, 6, 8, 9]
#  [7, 9]
#  [7, 8]
#  [8, 9]

# 2,3
# [[1], [1, 4], [1, 3], [1, 2], [2], [2, 5], [2, 3], [3], [3, 6], [4, 7], [4, 6], [4, 5], [5, 8], [5, 6], [6, 9], [7], [7, 9], [7, 8], [8], [8, 9], [9]]
end #module
