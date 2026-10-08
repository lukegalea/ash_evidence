# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Explanation do
  @moduledoc """
  The explanation data function: what a review surface (the AST-57
  shape) needs to show WHY an assertion says what it says.

  The explanation IS the evidence — a System One model gives no reasons
  — so the display datum is built from recorded facts only: the cited
  atoms (id, seq, text, bbox, resolved from the store NOW, at display
  time — never stored on the assertion or the packet), plus the
  observation's own recorded fields (disposition, recorded probability,
  question version, model digest) passed in as data.

  Erasure degrades honestly: a source id whose atom no longer resolves
  comes back in `unresolved_source_ids` — a valid reference to
  something that no longer resolves — and is never silently dropped.
  """

  @moduledoc since: "0.1.0"

  defmodule Item do
    @moduledoc """
    One observation's display datum: the recorded fields the caller
    passed (disposition, probability, question version, model digest)
    plus the resolved sources — atom content fetched at display time.
    """

    defstruct [
      :observation_id,
      :disposition,
      :probability,
      :question_version,
      :model_digest,
      :sources,
      :unresolved_source_ids
    ]

    @type t :: %__MODULE__{
            observation_id: String.t() | nil,
            disposition: String.t(),
            probability: String.t() | nil,
            question_version: pos_integer() | nil,
            model_digest: String.t() | nil,
            sources: [
              %{
                required(:atom_id) => String.t(),
                required(:seq) => pos_integer(),
                required(:text) => String.t(),
                optional(:bbox) => map() | nil
              }
            ],
            unresolved_source_ids: [String.t()]
          }
  end

  alias AshEvidence.AddressedAtom

  require Ash.Query

  @doc """
  Resolve a batch of observations into display items. Each input is a
  map with:

    * `:source_ids` — the cited atom ids (from the ledger observation);
    * `:disposition` — the recorded value (string, as the ledger holds);
    * `:probability` — the recorded probability of that disposition, as
      a decimal string (passed through verbatim);
    * `:observation_id`, `:question_version`, `:model_digest` — as
      recorded.

  Atoms are resolved in ONE query for the whole batch.
  """
  @spec for_observations([map()]) :: [Item.t()]
  def for_observations(items) when is_list(items) do
    source_ids =
      items |> Enum.flat_map(&List.wrap(&1[:source_ids])) |> Enum.uniq()

    by_id = resolve_atoms(source_ids)

    Enum.map(items, fn item ->
      {found, unresolved} =
        Enum.split_with(List.wrap(item[:source_ids]), &Map.has_key?(by_id, &1))

      %Item{
        observation_id: item[:observation_id],
        disposition: item[:disposition] && to_string(item[:disposition]),
        probability: item[:probability],
        question_version: item[:question_version],
        model_digest: item[:model_digest],
        sources: Enum.map(found, fn atom_id -> source(by_id[atom_id]) end),
        unresolved_source_ids: unresolved
      }
    end)
  end

  defp resolve_atoms(source_ids) do
    ids = Enum.filter(source_ids, fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end)

    if ids == [] do
      %{}
    else
      AddressedAtom
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.load([:id, :seq, :text, :bbox])
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})
    end
  end

  defp source(atom) do
    %{
      atom_id: atom.id,
      seq: atom.seq,
      text: atom.text,
      bbox: atom.bbox
    }
  end
end
