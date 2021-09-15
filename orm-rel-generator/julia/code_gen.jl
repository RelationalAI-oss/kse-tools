# Functions in this file generate rel code with integrity constraints
#   to implement ontologies that are modeled in ORM.
#
# At a high level, we treat certain diagrams in the ORM model as
#   designating central concepts and "constellations" of relations,
#   where the relations are inferred from names and uniqueness
#   constraints that pertain to roles of ORM fact types.
#

import Pkg

Pkg.activate((ENV["ORM_REL_GENERATOR"]))

using EzXML

include("./orm_api.jl")
include("./rel_ast.jl")

"""
Returns the Rel type of the object that plays the
  role identified by r_id
"""
function rel_type_of_role_player(r_id, M)::RelType

   etype = entity_that_plays(r_id, M)
   RelType( etype !== nothing ?
              name(etype) :
              data_type_of_player(r_id, M) .|>
                 ( dt_id ->
                     maps_to_rel_string(dt_id, M) ? "String" :
                     maps_to_rel_int(dt_id, M) ? "Int" :
                     maps_to_rel_date(dt_id, M) ? "Date" :
                     maps_to_rel_datetime(dt_id, M) ? "DateTime" :
                     "String" ) )
end

"""
Maps an ORM name to a Rel name using our naming conventions
"""
rel_name_of(orm_name::String) = pascal_to_snake_case(orm_name)

"""
Maps a role to the the name of the object that plays that role
  using Rel naming conventions
"""
rel_name_of_role_player(role, M) =
   rel_name_of(name(role_player_by_id(id(role), M)))

"""
Given an entity type etype, its preferred identifying uc,
   and the roles of the entity and its identifier in the
   identifying fact type, generate the refmode predicate
   (one that maps the entity to its identifier)
"""
function refmode_predicate(etype, uc, e_role, i_role, M)::Predicate

   function gen_refmode_pred_name()::String
      e_name = pascal_to_snake_case(name(etype))
      mode = refmode(etype)
      if mode != ""
         e_name * "_" * mode
      else
         v_name = rel_name_of_role_player(i_role, M)
         e_name * "_" * v_name
      end
   end

   i_role_name = name(i_role)
   pred_name = i_role_name != "" ? i_role_name : gen_refmode_pred_name()

   Predicate(pred_name, uc, id(e_role), id(i_role))
end

"""
Given an entity type etype, the uc that is *not* the preferred
   identifier but that applies to the identifying fact type,
   and the roles of the entity and its identifier from that
   fact type, generate the refmode inverse predicate (one that
   maps the identifier to the entity)
"""
function refmode_inverse_predicate(e, uc, e_role, i_role, M)::Predicate

   function gen_refmode_inverse_pred_name()::String
      e_name = pascal_to_snake_case(name(e))
      mode = refmode(e)
      if mode != ""
         return mode * "_to_" * e_name
      else
         v_name = rel_name_of_role_player(i_role, M)
         v_name * "_to_" * e_name
      end
   end

   e_role_name = name(e_role)
   pred_name = e_role_name != "" ? e_role_name : gen_refmode_inverse_pred_name()

   Predicate(pred_name, uc, id(i_role), id(e_role))
end

"""
Generate relations for ORM fact type ft using system generated
   relation names
"""
function system_named_relations_for(ft, M)::Vector{Predicate}
   rel_seq = Relation[]
   uc_ids = extract_uc_ids_of(ft)
   if size(uc_ids)[1] > 1
      println("[Warning]: Cannot generate relations for fact type '" *
              fact_name(ft) *
              "' because there is more than one UC and none of the roles are named.")
   else
      uc_id = uc_ids[1]
      uc = uc_by_id(uc_id, M)
      value_role_id_seq = roles_excluded_by_uc_in_fact_type(uc, ft, M)
      key_role_id_seq = extract_role_ids_from_simple(uc)
      push!(rel_seq,
            Predicate(pascal_to_snake_case(fact_name(ft)),
            uc_id,
            key_role_id_seq,
            value_role_id_seq))
   end
   return rel_seq
end

"""
Generate relations for ORM fact type ft using user-provided
   relation names. User preferences are provided by naming
   one or more of the roles of ft.
"""
function user_named_relations_for(ft, M)::Vector{Predicate}
   rel_seq = Relation[]
   # Look for relations designated by role names
   for role in extract_roles(ft)
      role_name = name(role)
      if length(role_name) == 0 continue
      else
         key_uc = uc_that_excludes_role_in_fact_type(role, ft, M)
         if key_uc === nothing
            # only print warning if it is not a unary fact type
            # in which case there is always a second implicit boolean role player
            rids = extract_role_ids(ft)
            if !is_implicit_boolean(rids[1], M) & !is_implicit_boolean(rids[2], M)
               println("[Warning]: Cannot generate relation for role with name " *
                     role_name *
                     " in fact type " * fact_name(ft) *
                     " because model lacks a non-spanning UC that excludes this role.")
            end
         else
            roles = extract_role_ids_from_simple(key_uc)
            rel = Predicate(role_name, id(key_uc), roles, id(role))
            push!(rel_seq, rel)
         end
      end
   end
   rel_seq
end

"""
Given a Rel predicate rel and a model M, construct a
   Rel type constraint for rel.
"""
function rel_type_constraint(rel::Predicate, M)::IC
   constraint_name = "$(rel.relname)_types"
   rseq = role_seq(rel)
   num_roles = size(rseq, 1)
   vars = fresh_variables(num_roles)
   conjuncts = zip( rseq .|> (r_id -> rel_type_of_role_player(r_id, M)),
                    vars ) .|> (t -> RelAtom(t[1], t[2]))

   IC(constraint_name, vars, Implication(RelAtom(rel, vars), Conjunction(conjuncts)))
end

"""
Given an ORM mandatory constraint id mc_id, a Rel predicate rel,
   and a model M, construct a Rel mandatory constraint.
"""
function rel_mandatory_constraint(mc_id, rel, M)::IC
   var = "v"
   mc = mc_by_id(mc_id, M)
   role_ids = extract_role_ids_from_simple(mc)
   role_id = first_occurrence_from(role_ids, rel)
   atom = bind_role_to(rel, role_id, var)

   role_player = rel_type_of_role_player(role_id, M)
   constraint_name = "$(lowercase(role_player.relname))_mandatory_in_$(rel.relname)"
   IC(constraint_name,
      [var],
      Implication(RelAtom(role_player, var), atom))
end

"""
Given an ORM unary fact ft, a Rel predicate rel,
   and a model M, construct a Rel subset constraint.
"""
function rel_subset_constraint(ft, rel, M)::Clause
   constraint_name = "$(rel.relname)_subset"
   r_id = extract_role_ids(ft)[1]
   IC(constraint_name, Implication(RelAtom(rel,"v"), RelAtom(rel_type_of_role_player(r_id, M),"v")))
end

"""
Given an ORM uniqueness constraint id uc_id, a Rel predicate rel,
   and a model M, construct a Rel many-to-one constraint.
"""
function rel_many_one_constraint(uc_id, rel, M)::Clause
   # If the uc refers to only key roles of rel, then we can
   #   implement the constraint by declaring rel to be functional
   if rel.uc_id == uc_id
      constraint_name = "$(rel.relname)_many_one"
      IC(constraint_name, IsFunctional(rel))
   else
      Unsupported("TBD: Many to one constraint for non-generating uniqueness constraint of relation " * rel.relname)
   end
end

"""
For each relation that is determined by some fact type,
   and for each ORM constraint that pertains to any of
   the roles of that relation, generate a Rel integrity
   constraint (IC)
"""
function rel_constraints_for(ft, M)::Vector{Clause}

   relations_for_non_refmode(ft, M) =
      has_named_roles(ft) ?
         user_named_relations_for(ft, M) :
         system_named_relations_for(ft, M)

   relations = Predicate[]
   constraints = Clause[]

   if is_refmode_fact_type(ft, M)
      e_role_id = i_role_id = "<undefined-role-id>"
      e_uc = i_uc = "<undefined-uc>"

      for uc_id in extract_uc_ids_of(ft)
         r_id = lone_role_of(uc_id, M)
         if entity_identified_by(uc_id, M) === nothing
            e_uc = uc_id
            e_role_id = r_id
         else
            i_uc = uc_id
            i_role_id = r_id
         end
      end

      e = entity_that_plays(e_role_id, M)
      e_role = extract_role_by_id(e_role_id, ft)
      i_role = extract_role_by_id(i_role_id, ft)

      refmode_pred = refmode_predicate(e, e_uc, e_role, i_role, M)
      refmode_inverse_pred = refmode_inverse_predicate(e, i_uc, e_role, i_role, M)

      push!(relations, refmode_pred)
      push!(constraints, rel_many_one_constraint(i_uc, refmode_inverse_pred, M))
      push!(relations, refmode_inverse_pred)
      push!(constraints, rel_many_one_constraint(e_uc, refmode_pred, M))
   else
      for rel in relations_for_non_refmode(ft, M)
         push!(relations, rel)
         # Separate if for unary facts
         if is_implicit_boolean(rel.value_role_seq[1], M) & size(rel.key_role_seq)[1] == 1 
            push!(constraints, rel_subset_constraint(ft, rel, M))
         elseif size(rel.value_role_seq)[1] + size(rel.key_role_seq)[1] > 0
            # Then there must be at least one non-spanning UC
            for uc_id in extract_uc_ids_of(ft)
               push!(constraints, rel_many_one_constraint(uc_id, rel, M))
            end
         end
      end
   end
   for rel in relations
      # Exclude unary facts
      if !(is_implicit_boolean(rel.value_role_seq[1], M) & size(rel.key_role_seq)[1] == 1)
         push!(constraints, rel_type_constraint(rel, M))
      end
      for mc_id in extract_mc_ids_of(ft)
         push!(constraints, rel_mandatory_constraint(mc_id, rel, M))
      end
   end
   constraints
end

"""
Generates a Rel type constraint for the top-level concept
"""
function rel_constraint_for_top_level_entity(concept)::Clause
   var = "v"
   etype_name = name(concept)
   constraint_name = "$(rel_name_of(etype_name))_is_entity"
   rel_entity_base_atom = RelAtom(RelType("Entity"), var)

   IC(constraint_name,
      var,
      Implication(RelAtom(RelType(etype_name), var),
                  rel_entity_base_atom))
end

"""
Generates a Rel type constraint for concept, when it is known
   to be a subtype of some supertype
"""
function rel_constraint_for_entity_subtype(concept, supertype)::Clause
   var = "v"
   sub_name = name(concept)
   super_name = name(supertype)
   constraint_name = "$(rel_name_of(sub_name))_is_subtype_of_$(rel_name_of(super_name))"

   IC(constraint_name,
      var,
      Implication(RelAtom(RelType(sub_name), var),
                  RelAtom(RelType(super_name), var)))
end

"""
Generates and adds to 'concepts' all Rel type constraints for
   concept and its subtypes that are drawn on diagram D,
"""
function rel_constraints_for_entity_types(concept, concepts, D, M)
   if is_drawn_on(concept, D)
      if is_top_level_concept(concept, M)
         push!( concepts, rel_constraint_for_top_level_entity(concept) )
      else
         for super_type in super_types_of(concept, M)
            push!( concepts, rel_constraint_for_entity_subtype(concept, super_type) )
         end
      end
   end
   for sub_concept in sub_types_of(concept, M)
      rel_constraints_for_entity_types(sub_concept, concepts, D, M)
   end
end

function generate(orm_model::String, output_folder::String)
   println("Generating schemas for: " * orm_model * " in " * output_folder)
   !isdir(output_folder) && mkpath(output_folder)

   doc = root(readxml(orm_model))
   M = findfirst("orm:ORMModel", doc)

   for D in findall("ormDiagram:ORMDiagram", doc)
      concept = central_concept(D, M)
      concept === nothing && continue

      filename = lowercase(name(concept)) * "_schema.rel"
      # Instead of opening a file for writing,
      # use the line below for debugging purposes from vscode
      let io = Base.stdout
      # open("$output_folder/$filename", "w") do io
         println(io)
         println(io, "// Constraints for the '" * name(concept) * "' concept and its subtypes")
         concept_constraints = Clause[]
         rel_constraints_for_entity_types(concept, concept_constraints, D, M)
         for constraint in concept_constraints
            println(io, emit(constraint))
         end
         fact_types = fact_types_in_diagram(D, M)
         if refmode(concept) != ""
            # Add the fact type that identifies the central concept,
            #   even though it is not displayed on the diagram
            ft = identifying_fact_type_for(concept, M)
            push!(fact_types, ft)
         end
         for ft in fact_types
            println(io)
            println(io, "// Constraints for relations modeled by the '" * fact_name(ft) * "' fact type")
            for ft_constraint in rel_constraints_for(ft, M)
               println(io, emit(ft_constraint))
            end
         end
      end
   end
end
