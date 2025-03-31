function tropical_svd(C::Matrix{TropicalAndOr},k::Int;solver = IPSolver())
    # C = A * B
    # A: m x k, B: k x n
    # IP by JuMP

    m,n = size(C)
    model = Model(solver.optimizer)
    !solver.verbose && set_silent(model)

    @variable(model, 0 <= a[i = 1:m*k] <= 1, Int) # a[i,l] = a[(l-1)*m+i]
    @variable(model, 0 <= b[i = 1:k*n] <= 1, Int)   # b[l,j] = b[(j-1)*k+l]
    @variable(model, 0 <= d[i = 1:m*k*n] <= 1, Int) # d[i,l,j] = d[(j-1)*k*m+(l-1)*m+i]
    
    for i in 1:m
        for j in 1:n
            if C[i,j].n
                for l in 1:k
                    @constraint(model, d[(j-1)*k*m+(l-1)*m+i] <= a[(l-1)*m+i])
                    @constraint(model, d[(j-1)*k*m+(l-1)*m+i] <= b[(j-1)*k+l])
                end
                @constraint(model, sum(d[(j-1)*k*m+(l-1)*m+i] for l in 1:k) >= 1)
            else
                for l in 1:k
                    @constraint(model, d[(j-1)*k*m+(l-1)*m+i] + 1 >= a[(l-1)*m+i] + b[(j-1)*k+l])
                    @constraint(model, d[(j-1)*k*m+(l-1)*m+i] <= 0)
                end
            end
        end
    end
    @objective(model, Max, 1)
    
    optimize!(model)
    return  is_solved_and_feasible(model),reshape([TropicalAndOr(v ≈ 1.0) for v in value.(a)],m,k), reshape([TropicalAndOr(v ≈ 1.0) for v in value.(b)],k,n)
end