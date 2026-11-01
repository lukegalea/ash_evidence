# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AtomKind do
  @moduledoc """
  What layout unit an addressed atom is.

    * `:word` — one word as the instrument read it; the finest address.
    * `:line` — one line of text. Its `source_ids` are its word atoms.
    * `:cell` — one table cell. Its `source_ids` are the words or lines
      inside it.
    * `:region` — any other bounded area of a page (a block, a figure, a
      mark). Its `source_ids` are the atoms it contains, and its `text`
      is their text or the region's label.
  """

  @moduledoc since: "0.2.0"

  use Ash.Type.Enum, values: [:word, :line, :cell, :region]
end
