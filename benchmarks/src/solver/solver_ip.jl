function findmin_ip(problem::CircuitSAT, tag::Bool; optimizer, env)
    cons = constraints(problem)
    nsc = ProblemReductions.num_variables(problem)
    maxN = maximum([length(c.variables) for c in cons])
    combs = [ProblemReductions.combinations(2,i) for i in 1:maxN]
    objs = objectives(problem)
    
    opt = isnothing(env) ? optimizer() : optimizer(env)
    model = JuMP.direct_model(opt)
    set_silent(model)
    set_string_names_on_creation(model, false)
    
    JuMP.@variable(model, 0 <= x[i = 1:nsc] <= 1, Int)
    
    for con in cons
        f_vec = findall(!,con.specification)
        num_vars = length(con.variables)
        for f in f_vec
            JuMP.@constraint(model, sum(j-> iszero(combs[num_vars][f][j]) ? (1 - x[con.variables[j]]) : x[con.variables[j]], 1:num_vars) <= num_vars -1)
        end
    end
    
    if isempty(objs)
        JuMP.@objective(model, Min, 0)
    else
        obj_sum = sum(objs) do obj
            (1-x[obj.variables[1]])*obj.specification[1] + x[obj.variables[1]]*obj.specification[2]
        end
        tag ? JuMP.@objective(model,  Min, obj_sum) : JuMP.@objective(model,  Max, obj_sum)
    end
    
    JuMP.optimize!(model)
    @assert JuMP.is_solved_and_feasible(model) "The problem is infeasible"
    return round.(Int, JuMP.value.(x))
end

function factoring_ip(m, n, N; solver::IPSolver)
    fact3 = Factoring(m, n, N)
    res3 = reduceto(CircuitSAT, fact3)
    problem = CircuitSAT(res3.circuit.circuit; use_constraints=true);
    vals = findmin_ip(problem, true; optimizer=solver.optimizer, env=solver.env)
    return ProblemReductions.read_solution(fact3, [vals[res3.p]...,vals[res3.q]...])
end

