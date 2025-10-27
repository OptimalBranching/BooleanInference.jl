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
    failed = filter(r -> r["status"] == "failed", results)
    
    if !isempty(successful)
        println("Successful benchmarks: $(length(successful))")
        println(repeat("+", 90))
        println("| Config      | Median Time | Memory      | Instances | Correct | Accuracy | Timed |")
        println(repeat("-", 90))
        
        for result in successful
            config = result["config"]
            median_time = result["median_time"]
            median_memory = result["median_memory"]
            instances = get(result, "instances_tested", 0)
            correct = get(result, "correct_runs", 0)
            accuracy = get(result, "accuracy_rate", 0.0)
            timed = get(result, "successful_runs", 0)
            
            config_str = "$(config.m)x$(config.n)"
            time_str = format_time(median_time)
            memory_str = format_bytes(median_memory)
            accuracy_str = "$(round(accuracy * 100, digits=1))%"
            
            println("| $(rpad(config_str, 11)) | $(rpad(time_str, 11)) | $(rpad(memory_str, 11)) | $(rpad(string(instances), 9)) | $(rpad(string(correct), 7)) | $(rpad(accuracy_str, 8)) | $(rpad(string(timed), 5)) |")
        end
        println(repeat("+", 90))
    end
    
    if !isempty(failed)
        println("\nFailed benchmarks: $(length(failed))")
        for result in failed
            config = result["config"]
            reason = result["reason"]
            println("  - $(config): $reason")
        end
    end
    println(repeat("=", 60))
end

