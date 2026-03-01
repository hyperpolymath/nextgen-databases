;; SPDX-License-Identifier: PMPL-1.0-or-later
(ecosystem
  (version "1.0.0")
  (last-updated "2026-03-01")

  (name "typeql-experimental")
  (type "experimental-language-extension")
  (purpose "Explore advanced type-theoretic extensions to VQL")

  (position-in-ecosystem
    (parent "nextgen-databases"
      (relationship "sub-project")
      (description "Lives within the nextgen-databases monorepo, no own .git"))
    (description "Experimental sister project to VQL-dt. While VQL-dt is the
                  production dependent type system for VeriSimDB (~35% wired),
                  typeql-experimental explores six advanced extensions that may
                  eventually feed back into VQL-dt. All 9 Idris2 modules
                  type-check clean with zero banned patterns."))

  (related-projects
    (project "verisimdb"
      (relationship "sibling-dependency")
      (description "VQL v3.0 grammar (317 lines), VQL-dt type checker,
                    AST types, parser combinator patterns. Primary reference.")
      (artefacts-used "vql-grammar.ebnf" "VQLParser.res" "VQLTypes.res"))

    (project "lithoglyph"
      (relationship "sibling-pattern")
      (description "GQL-dt (FBQLdt) Idris2 ABI patterns. ipkg structure,
                    module organisation, zero-believe_me invariant.")
      (artefacts-used "fbqldt.ipkg" "src/FormBD/*.idr"))

    (project "proven"
      (relationship "potential-consumer")
      (description "Formal verification library. Proof-carrying code extension
                    may integrate with proven's certificate format."))

    (project "quandledb"
      (relationship "sibling-inspiration")
      (description "Knot-theory database. KQL query language may benefit from
                    similar type extensions."))

    (project "nqc"
      (relationship "sibling-tool")
      (description "NQC cross-database console. Web UI patterns (ReScript + Deno)
                    informed the parser build setup.")))

  (technologies
    (technology "Idris2" (role "type-system-kernel") (version "0.8.0"))
    (technology "ReScript" (role "parser") (version ">= 11.0"))
    (technology "Deno" (role "runtime") (version ">= 2.0"))
    (technology "Zig" (role "ffi-bridge") (version "0.15.2"))))
