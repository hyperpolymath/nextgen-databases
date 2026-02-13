;; SPDX-License-Identifier: PMPL-1.0-or-later
(ecosystem (metadata (version "0.1.0") (last-updated "2026-02-13"))
  (project (name "nextgen-databases") (purpose "Database portfolio tracking and coordination") (role parent-repository))
  (related-projects
    (project (name "nextgen-languages") (relationship "sibling-standard") (description "Language portfolio — query languages listed there"))
    (project (name "quandledb") (relationship "child") (description "Knot-theory database"))
    (project (name "Skein.jl") (relationship "child-dependency") (description "Knot database engine"))
    (project (name "verisimdb") (relationship "child") (description "Multimodal verification database"))
    (project (name "lithoglyphdb") (relationship "child") (description "Glyph and inscription database"))
    (project (name "glyphbase") (relationship "child") (description "Web frontend for LithoglyphDB"))))
