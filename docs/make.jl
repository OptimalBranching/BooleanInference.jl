using BooleanInference
using Documenter

DocMeta.setdocmeta!(BooleanInference, :DocTestSetup, :(using BooleanInference); recursive=true)

makedocs(;
    modules=[BooleanInference],
    authors="Anonymous",
    sitename="BooleanInference.jl",
    format=Documenter.HTML(;
        canonical="https://anonymous.github.io/BooleanInference.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/anonymous/BooleanInference.jl",
    devbranch="main",
)
