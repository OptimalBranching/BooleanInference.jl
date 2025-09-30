using BooleanInference
using Test
using BooleanInference: DEBUG_DETAILED, DEBUG_VERBOSE, DEBUG_BASIC, DEBUG_OFF

@testset "debug" begin
    set_debug_level!(DEBUG_DETAILED)
    @test BooleanInference.debug_enabled(DEBUG_DETAILED) == true
    @test BooleanInference.debug_enabled(DEBUG_VERBOSE) == false
    @test BooleanInference.debug_enabled(DEBUG_BASIC) == true
    @test BooleanInference.debug_enabled(DEBUG_OFF) == true
end