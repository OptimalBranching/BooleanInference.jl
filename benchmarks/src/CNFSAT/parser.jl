# DIMACS CNF file parser

"""
    parse_cnf_file(filepath::String) -> CNFSATInstance

Parse a CNF file in DIMACS format and return a CNFSATInstance.

DIMACS CNF format:
- Comment lines start with 'c'
- Problem line: "p cnf <num_vars> <num_clauses>"
- Clause lines: space-separated integers, terminated by 0
  - Positive integers represent positive literals
  - Negative integers represent negative literals
  - Example: "1 -2 3 0" means (x1 ∨ ¬x2 ∨ x3)
"""
function parse_cnf_file(filepath::String)
    isfile(filepath) || error("File not found: $filepath")

    name = basename(filepath)
    # Remove extension if present
    if endswith(name, ".cnf")
        name = name[1:end-4]
    end

    num_vars = 0
    num_clauses = 0
    clauses = Vector{Vector{Int}}()
    header_found = false

    open(filepath, "r") do io
        for line in eachline(io)
            line = strip(line)

            # Skip empty lines
            isempty(line) && continue

            # Skip comment lines
            startswith(line, 'c') && continue

            # Parse problem line
            if startswith(line, 'p')
                header_found = true
                parts = split(line)
                length(parts) >= 4 || error("Invalid problem line: $line")
                parts[2] == "cnf" || error("Expected 'cnf' format, got: $(parts[2])")

                num_vars = parse(Int, parts[3])
                num_clauses = parse(Int, parts[4])
                continue
            end

            # Parse clause line
            if header_found
                literals = Int[]
                for token in split(line)
                    token = strip(token)
                    isempty(token) && continue

                    lit = parse(Int, token)
                    if lit == 0
                        # End of clause
                        if !isempty(literals)
                            push!(clauses, literals)
                            literals = Int[]
                        end
                    else
                        push!(literals, lit)
                    end
                end

                # Handle clause that doesn't end with explicit 0 on same line
                if !isempty(literals)
                    push!(clauses, literals)
                end
            end
        end
    end

    header_found || error("No problem header found in file: $filepath")

    # Verify that the number of clauses matches the header
    if length(clauses) != num_clauses
        @warn "Number of clauses ($(length(clauses))) doesn't match header ($num_clauses) in $filepath"
    end

    return CNFSATInstance(name, num_vars, num_clauses, clauses, filepath)
end

"""
    cnf_instantiation(instance::CNFSATInstance)

Convert a CNFSATInstance to a ProblemReductions.CNF problem.
"""
function cnf_instantiation(instance::CNFSATInstance)
    # Create boolean variables for each variable in the CNF
    # Variables are numbered 1 to num_vars
    var_symbols = [Symbol("x$i") for i in 1:instance.num_vars]

    # Convert clauses to CNFClause objects
    cnf_clauses = map(instance.clauses) do clause_literals
        bool_vars = map(clause_literals) do lit
            var_idx = abs(lit)
            is_negated = lit < 0
            BoolVar(var_symbols[var_idx], is_negated)
        end
        CNFClause(bool_vars)
    end
    return CNF(cnf_clauses)
end
