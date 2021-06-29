abstract type Clause end
abstract type Formula end
abstract type Relation end

struct RelType <: Relation
   relname::String
end

struct Predicate <: Relation
   relname::String
   uc_id::String
   key_role_seq::Vector{String}
   value_role_seq::Vector{String}

   Predicate(r::String, uc::String, key::String, value::String) =
      new(r, uc, [key], [value])
   Predicate(r::String, uc::String, kseq::Vector{String}, value::String) =
      new(r, uc, kseq, [value])
   Predicate(r::String, uc::String, kseq::Vector{String}, vseq::Vector{String}) =
      new(r, uc, kseq, vseq)
end

role_seq(r::Predicate) = vcat( r.key_role_seq , r.value_role_seq )

struct IsFunctional <: Formula
   rel::Relation
end

struct RelAtom <: Formula
   rel::Relation
   params::Vector{String}

   RelAtom(r::Relation, p::String) = new(r, [p])
   RelAtom(r::Relation, p::Vector{String}) = new(r, p)
end

struct Conjunction <: Formula
   conjuncts::Vector{Formula}
end

struct Implication <: Formula
   antecedent::Formula
   consequent::Formula
end

struct IC <: Clause
   name::String
   head::Vector{String}
   body::Formula

   IC(n::String, b::Formula) = new(n, Vector{String}(), b)
   IC(n::String, var::String, b::Formula) = new(n, [var], b)
   IC(n::String, vars::Vector{String}, b::Formula) = new(n, vars, b)
end

struct Unsupported <: Clause
   error_message::String
end

conjunction(xs...)::String = join(xs, " and ")

emit(a::RelAtom) = "$(a.rel.relname)($(paramSeq(a.params)))"
emit(i::Implication) = emit(i.antecedent) * " implies " * emit(i.consequent)
emit(c::Conjunction) = conjunction((c.conjuncts .|> f -> emit(f))...)
emit(f::IsFunctional) = "function($(f.rel.relname))"

function emit(ic::IC)
   name = size(ic.head)[1] > 0 ? "$(ic.name)($(paramSeq(ic.head)))" : "$(ic.name)"
   "ic $name { $(emit(ic.body)) }"
end

emit(un::Unsupported) = "// Error: " * un.error_message

function paramSeq(params::Vector{String})
   @assert(size(params,1) > 0, "Cannot currently emit code for relations with no columns")
   reduce(spliceWithComma, params .|> string)
end

spliceWith(x::String, y::String, c::String)::String = x * c * y
spliceWithComma(x::String, y::String)::String = spliceWith(x, y, ", ")

"""
   Generates a sequence of variable names
"""
fresh_variables(num) = 1:num .|>  (n -> "v$(n)")

"""
Creates an atom that binds only the given role of Predicate rel
   with the given variable, existentially quantifying over all
   other roles
"""
function bind_role_to(rel::Predicate, role_id::String, var::String)::RelAtom
   key_bindings = rel.key_role_seq .|> r -> r == role_id ? var : "_"
   val_bindings = rel.value_role_seq .|> r -> r == role_id ? var : "_"
   RelAtom(rel, vcat(key_bindings, val_bindings))
end

"""
Finds first occurrence of any role from role_set in the
   role sequence of Predicate rel
"""
function first_occurrence_from(role_set::Vector{String}, rel::Predicate)
   for role_id in role_seq(rel)
      if findfirst((id -> id === role_id), role_set) !== nothing
         return role_id
      end
   end
end

pascal_case_pattern = r"(?<word>^[A-Z][^A-Z]*)"

function pascal_to_snake_case(s)::String
   word_match = match(pascal_case_pattern, s)
   if word_match === nothing
      println("[Error] Expected string '" * s * "' to be in PascalCase")
      return nothing
   else
      word = lowercase(word_match[:word])
      remainder = SubString(s, length(word) + 1, length(s))
      if remainder != ""
         return word * "_" * pascal_to_snake_case(remainder)
      else
         return word
      end
   end
end
