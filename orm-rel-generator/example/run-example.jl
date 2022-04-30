project_root = "$(@__DIR__)/.."

include("$project_root/julia/code_gen.jl")

function run_example()
    generate("/Users/mbur/git/ey-forms/modeling/1065-fed-2020.orm","/Users/mbur/temp/")

    # generate("$project_root/example/event_registration.orm",
            #  "$project_root/example/output")
end

run_example()
