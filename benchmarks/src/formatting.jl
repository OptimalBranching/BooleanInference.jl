function format_bytes(bytes::Number)
    if bytes < 1024
        return "$(Int(bytes))B"
    elseif bytes < 1024^2
        return "$(round(bytes/1024, digits=1))KB"
    elseif bytes < 1024^3
        return "$(round(bytes/1024^2, digits=1))MB"
    else
        return "$(round(bytes/1024^3, digits=1))GB"
    end
end

function format_time(seconds::Float64)
    if seconds < 1e-6
        return "$(round(seconds * 1e9, digits=1))ns"
    elseif seconds < 1e-3
        return "$(round(seconds * 1e6, digits=1))us"
    elseif seconds < 1
        return "$(round(seconds * 1e3, digits=1))ms"
    elseif seconds < 60
        return "$(round(seconds, digits=2))s"
    else
        minutes = floor(seconds / 60)
        secs = seconds - minutes * 60
        return "$(Int(minutes))m$(round(secs, digits=1))s"
    end
end

function print_benchmark_summary(results)
    println("\n" * repeat("=", 60))
    println("BENCHMARK SUMMARY")
    println(repeat("=", 60))
    
    successful = filter(r -> r["status"] == "success", results)
    
    if !isempty(successful)
        println("Successful benchmarks: $(length(successful))")
        println(repeat("+", 90))
        println("| Config      | Median Time | Instances |")
        println(repeat("-", 90))
        
        for result in successful
            config = result["config"]
            median_time = result["median_time"]
            instances = get(result, "instances_tested", 0)
            
            config_str = "$(config.m)x$(config.n)"
            time_str = format_time(median_time)

            println("| $(rpad(config_str, 11)) | $(rpad(time_str, 11)) | $(rpad(string(instances), 9)) |")
        end
        println(repeat("+", 90))
    end
    println(repeat("=", 60))
end

