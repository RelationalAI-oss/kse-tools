# ORM-Rel-Generator

A code generator for Rel that automates translating ORM models to code.

## Configuration

To get started, clone this repository, and set the environment variable `ORM_REL_GENERATOR` to point to the folder where this REAMDE file is located in:
```bash
$ export ORM_REL_GENERATOR=/Users/Alice/git/kse-tools/orm-rel-generator
```

## Usage

You can access the code generator from Julia REPL by including the file _julia/code_gen.jl_ as follows:

```julia
julia> include("./julia/code_gen.jl")
```

To use the code generator, call the Julia function `generate()` from the REPL with two parameters:

```julia
julia> generate("example/event_registration.orm","example/output/")
```

## Example

In the _example_ folder, you can find an ORM model with the script _run_example.jl_ that you can use to test the capabilities of the generator. The results will be placed under _example/output_.
