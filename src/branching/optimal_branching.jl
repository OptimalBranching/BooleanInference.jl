# function apply_branch!(p::TNProblem, cl::Clause{INT}, variables::Vector{Int}) where {INT}
#     new_doms = copy(p.doms)
#     changed_indices = apply_clause!(cl.mask, variables, new_doms)
#     propagated_doms = propagate(p.static, new_doms, changed_indices, p.ws)
# end


