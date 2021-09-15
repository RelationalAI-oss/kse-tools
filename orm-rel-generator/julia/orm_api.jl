# This file defines an API that allows clients to access an ORM
# model without scattering XPath strings throughout the code.
#
# Generally speaking:
#  - extract_X operations extract nodes that descend from a model
#      element with no additional context
#  - operations that lookup various kinds of information from
#      some id or model element. Note that these differ from extract
#      operations in that lookups must query the entire model for
#      for context and often do significant calculation.
#  - predicates of various names (all return Booleans) that query
#      whether model elements (or ids of model elements) satisfy
#      some property
#

fact_name(f) = f["_Name"]
id(r) = r["id"]
name(o) = o["Name"]
ref(r) = r["ref"]
refmode(e) = e["_ReferenceMode"]

by_id(i, path, element) = findfirst(path * "[@id='$i']", element)
by_name(n, path, element) = findfirst(path * "[@Name='$n']", element)
by_ref(r, path, element) = findfirst(path * "[@ref='$r']", element)

ref_of(path, element) = element !== nothing ? ref(findfirst(path, element)) : nothing
refs_of(path, element) = findall(path, element) .|> ref

plays_role_path(r_id) = "/orm:PlayedRoles/orm:Role[@ref='$r_id']/../.."


# Functions that extract information from an ORM model element node
#
extract_conceptual_data_type_id(vt) = ref_of("orm:ConceptualDataType", vt)

extract_preferred_id_uc(etype) = ref_of("orm:PreferredIdentifier", etype)

extract_role_by_id(r_id, ft) = by_id(r_id, "orm:FactRoles/orm:Role", ft)
extract_role_ids(ft) = extract_roles(ft) .|> id

"""
Extracts an array of role ids from the lone role sequence of
  any ORM constraint that ranges over a lone role sequence
  (e.g., UC, mandatory)
"""
extract_role_ids_from_simple(c) = refs_of("orm:RoleSequence/orm:Role", c)
extract_roles(ft) = findall("orm:FactRoles/orm:Role", ft)

extract_uc_ids_of(ft) = refs_of("orm:InternalConstraints/orm:UniquenessConstraint", ft)
extract_mc_ids_of(ft) = refs_of("orm:InternalConstraints/orm:MandatoryConstraint", ft)

# Functions that consult the ORM model to lookup information of various
# kinds about ORM model elements or ids
#

"""
Given a diagram D that should depict a central concept
   and its constellation and model M, verify correct
   applicaiton of the pattern and return the entity type
   that defines the concept

   NOTE: We designate a schema subgraph centered by some concept
   with a constellation of relations that are keyed by that
   concept using ORM Diagrams that are named according to the
   convention "X:concept" where X is the name of the entity
   type that represents the central concept (e.g.,
   "Location:concept" or "Subscription:concept").
"""
function central_concept(D, M)

   concept_name_pattern = Regex("^(?<concept>[^(:| )]+)(?:.*):concept")

   concept_match = match(concept_name_pattern, name(D))
   if concept_match !== nothing
      concept_name = concept_match[:concept]
      etype = entity_by_name(concept_name, M)
      if is_drawn_on(etype, D) return etype end
   end
   return nothing
end

constraint_by_id(c_id, M) = by_id(c_id, "orm:Constraints/*", M)

data_type_of_player(r_id, M) =
   extract_conceptual_data_type_id(
      findfirst("orm:Objects/orm:ValueType" * plays_role_path(r_id), M))

entity_by_name(n, M) = by_name(n, "orm:Objects/orm:EntityType", M)

"""
Find the entity for which uc_id is the preferred identifier, or nothing
"""
function entity_identified_by(uc_id, M)
   uc = uc_by_id(uc_id, M)
   uc === nothing && return nothing
   reft = findfirst("orm:PreferredIdentifierFor", uc)
   reft === nothing ? nothing : by_id(ref(reft), "orm:Objects/orm:EntityType", M)
end

entity_that_plays(r_id, M) =
   findfirst("orm:Objects/orm:EntityType" * plays_role_path(r_id), M)

fact_type_with_role(role_id, M) =
   findfirst("orm:Facts/orm:Fact[orm:FactRoles/orm:Role[@id='$role_id']]", M)

"""
Create sequence of ORM fact types that are drawn on diagram D
"""
function fact_types_in_diagram(D, M)
   drawn_fact_type_path = "ormDiagram:Shapes/ormDiagram:FactTypeShape/ormDiagram:Subject"
   global_relations = findfirst("orm:Facts", M)
   # outputs = EzXML.Node[]
   outputs = []
   for shape in findall(drawn_fact_type_path, D)
      ft = by_id(ref(shape), "orm:Fact", global_relations)
      if ft !== nothing
         push!(outputs, ft)
      end
   end
   outputs
end

"""
Given an entity type, looks up the fact type that identifies
  instances of that entity type, if it exists, or nothing
"""
function identifying_fact_type_for(etype, M)
   uc_id = extract_preferred_id_uc(etype)
   uc = uc_by_id(uc_id, M)
   role_ids = extract_role_ids_from_simple(uc)
   if size(role_ids)[1] == 1
      return fact_type_with_role(role_ids[1], M)
   else
      return nothing
   end
end

"""
Retrieves the lone role spanned by the constraint identified by
   c_id, or nothing if the c_id is invalid or if it spans more
   than one role
"""
function lone_role_of(c_id, M)
   c = constraint_by_id(c_id, M)
   c !== nothing || return nothing

   rid_seq = extract_role_ids_from_simple(c)
   size(rid_seq)[1] == 1 ? rid_seq[1] : nothing
end

mc_by_id(mc_id, M) = by_id(mc_id, "orm:Constraints/orm:MandatoryConstraint", M)

role_player_by_id(r_id, M) = findfirst("orm:Objects/*" * plays_role_path(r_id), M)

"""
This function picks out that role id of a fact type that is not covered
   by the given uc. We return an array that will be empty if the uc
   is spanning and will contain exactly one element otherwise
"""
function roles_excluded_by_uc_in_fact_type(uc, ft, M)
   role_seq = String[]
   key_role_id_seq = extract_role_ids_from_simple(uc)
   for role_id in extract_role_ids(ft)
      if findfirst((r_id -> r_id === role_id), key_role_id_seq) !== nothing
         continue
      else
         push!(role_seq, role_id)
      end
   end
   return role_seq
end

"""
Returns the sequence of entity supertypes of etype in M
"""
function super_types_of(etype, M)
   path_prefix = "orm:Facts/orm:SubtypeFact/orm:FactRoles"
   path_suffix = "/orm:SupertypeMetaRole/orm:RolePlayer"
   refs_of("orm:PlayedRoles/orm:SubtypeMetaRole", etype) .|>
      (oid -> findfirst(path_prefix *
                          "[orm:SubtypeMetaRole[@id='$oid']]" *
                          path_suffix,
                        M)) .|>
      ref .|>
      (reft -> by_id(reft, "orm:Objects/orm:EntityType", M))
end

"""
Returns the sequence of entity subtypes of etype in M
"""
function sub_types_of(etype, M)
   path_prefix = "orm:Facts/orm:SubtypeFact/orm:FactRoles"
   path_suffix = "/orm:SubtypeMetaRole/orm:RolePlayer"
   refs_of("orm:PlayedRoles/orm:SupertypeMetaRole", etype) .|>
      (oid -> findfirst(path_prefix *
                          "[orm:SupertypeMetaRole[@id='$oid']]" *
                          path_suffix,
                        M)) .|>
      ref .|>
      (reft -> by_id(reft, "orm:Objects/orm:EntityType", M))
end

uc_by_id(uc_id, M) = by_id(uc_id, "orm:Constraints/orm:UniquenessConstraint", M)

#
# An ORM fact type often gives rise to multiple Rel relations because
#   roles are unordered in a fact type and may be ordered differently
#   to support different readings, while in Rel the ordering of
#   roles in a relation is fixed. We use the internal uniqueness
#   constraints declared over the roles of a fact type to generate
#   relations with definite column orderings. When a fact type contains
#   non-spanning UCs, we often need to associate a UC with the role
#   that it does not span and vice versa.
#

"""
This function extracts that UC of a fact type that does not cover
   the given role.
"""
function uc_that_excludes_role_in_fact_type(role, ft, M)
   role_id = id(role)
   for uc_id in extract_uc_ids_of(ft)
      uc = by_id(uc_id, "orm:Constraints/orm:UniquenessConstraint", M)
      occurrence = by_ref(role_id, "orm:RoleSequence/orm:Role", uc)
      if occurrence === nothing return uc end
   end
   return nothing
end

#
# ORM model element or id predicates
#

function has_named_roles(ft)::Bool
   for role in extract_roles(ft)
      if name(role) != ""
         return true
      end
   end
   return false
end

"""
Check whether the role is played by an implicit boolean value type, which is
used in the case of unary fact types
"""
function is_implicit_boolean(r_id, M)
   player = role_player_by_id(r_id,M)
   key = "IsImplicitBooleanValue"
   if haskey(player, key)
      return player[key] == "true"
   end
   return false
end

"""
Check whether the model element is drawn on diagram D
"""
function is_drawn_on(elem, D)::Bool
   elem === nothing && return false

   shape_subject = "ormDiagram:Shapes/*/ormDiagram:Subject"
   by_ref(id(elem), "$shape_subject", D) !== nothing
end


"""
Check whether a fact type is used to provide the preferred identifier
  for some entity type
"""
function is_refmode_fact_type(ft, M)::Bool
   role_ids = extract_role_ids(ft)
   if size(role_ids)[1] == 2
      uc_ids = extract_uc_ids_of(ft)
      if size(uc_ids)[1] == 2
         for uc_id in uc_ids
            # Choose the UC that is the preferred identifier for some
            # entity type, and note that in a well-formed refmode
            # pattern, that UC spans the role that is *not* played
            # by that entity type
            etype = entity_identified_by(uc_id, M)
            if etype !== nothing
               # Find the role spanned by that UC
               identifying_role_id = lone_role_of(uc_id, M)
               identifying_role_id !== nothing || continue

               # Verify that the other role is played by etype and is mandatory
               for rid in role_ids
                  if rid != identifying_role_id
                     rid_player = entity_that_plays(rid, M)
                     if id(rid_player) == id(etype)
                        for mc_id in extract_mc_ids_of(ft)
                           if rid == lone_role_of(mc_id, M)
                              return true
                           end
                        end
                     end
                  end
               end
            end
         end
      end
   end
   return false
end

function is_top_level_concept(etype, M)::Bool
   size(super_types_of(etype, M), 1) == 0
end


identifies_cdt(dt_id, cdt, M)::Bool = by_id(dt_id, "orm:DataTypes/$cdt", M)  !== nothing

function maps_to_rel_string(dt_id, M)::Bool
   identifies_cdt(dt_id, "orm:VariableLengthTextDataType", M) ||
   identifies_cdt(dt_id, "orm:FixedLengthTextDataType", M) ||
   identifies_cdt(dt_id, "orm:AutoCounterNumericDataType", M)
end

function maps_to_rel_int(dt_id, M)::Bool
   identifies_cdt(dt_id, "orm:SignedIntegerNumericDataType", M) ||
   identifies_cdt(dt_id, "orm:TrueOrFalseLogicalDataType", M) ||
   identifies_cdt(dt_id, "orm:UnsignedIntegerNumericDataType", M) ||
   identifies_cdt(dt_id, "orm:UnsignedSmallIntegerNumericDataType", M) ||
   identifies_cdt(dt_id, "orm:TimeTemporalDataType", M)
end

function maps_to_rel_date(dt_id, M)::Bool
   identifies_cdt(dt_id, "orm:DateTemporalDataType", M)
end

function maps_to_rel_datetime(dt_id, M)::Bool
   identifies_cdt(dt_id, "orm:DateAndTimeTemporalDataType", M)
end
