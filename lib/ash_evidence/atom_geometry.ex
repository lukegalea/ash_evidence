# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AtomGeometry do
  @moduledoc """
  Where an addressed atom sits on its page.

    * `page_w`, `page_h` — the page size the instrument measured, in
      `unit`. Both are positive.
    * `unit` — `:pt` (PDF points, 1/72 inch) or `:px` (raster pixels).
    * `rotation_applied` — degrees, clockwise, that the instrument
      rotated (and deskewed) the page before it measured the box. `0.0`
      when it measured the page as stored. The box is in that rotated
      frame; the parse run's `config` records the transform per page
      (see `AshEvidence.ParseRun`) so a box maps back to the original.
    * `bbox` — `%{x0, y0, x1, y1}`, normalised to `[0, 1]` of `page_w` and
      `page_h`, with the origin at the TOP-LEFT of the page: `x` grows
      rightwards, `y` grows downwards. `(x0, y0)` is the top-left corner
      and `(x1, y1)` the bottom-right, so `0 <= x0 <= x1 <= 1` and
      `0 <= y0 <= y1 <= 1`; a box outside that is refused.

  Normalised coordinates make boxes comparable across renditions of the
  same page at different resolutions. Multiply by `page_w`/`page_h` to
  get back to `unit`.
  """

  @moduledoc since: "0.2.0"

  use Ash.Resource, data_layer: :embedded

  @unit_interval [type: :float, allow_nil?: false, constraints: [min: 0.0, max: 1.0]]

  attributes do
    attribute :page_w, :float do
      allow_nil? false
      public? true
      constraints greater_than: 0.0
    end

    attribute :page_h, :float do
      allow_nil? false
      public? true
      constraints greater_than: 0.0
    end

    attribute :unit, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pt, :px]
    end

    attribute :rotation_applied, :float do
      allow_nil? false
      public? true
      constraints min: -360.0, max: 360.0
    end

    attribute :bbox, :map do
      allow_nil? false
      public? true

      constraints fields: [
                    x0: @unit_interval,
                    y0: @unit_interval,
                    x1: @unit_interval,
                    y1: @unit_interval
                  ]
    end
  end

  validations do
    validate AshEvidence.Validations.OrderedBox
  end
end
