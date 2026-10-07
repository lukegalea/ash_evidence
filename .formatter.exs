# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

# Used by "mix format"
[
  # ash's formatter plugins keep the DSL blocks in our resources shaped the
  # same way ash projects format them.
  import_deps: [:ash, :ash_postgres],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
