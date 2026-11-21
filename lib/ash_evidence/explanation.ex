# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Explanation do
  @moduledoc """
  The explanation data function: what a review surface (the AST-57
  shape) needs to show WHY an assertion says what it says.

  The explanation IS the evidence — a System One model gives no reasons
  — so the display datum is built from recorded facts only: the cited
  atoms (id, seq, text, kind, page and geometry, resolved from the store
  NOW, at display
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
                required(:kind) => AshEvidence.AtomKind.t(),
                required(:page) => pos_integer() | nil,
                required(:geometry) => AshEvidence.AtomGeometry.t() | nil
              }
            ],
            unresolved_source_ids: [String.t()]
          }
  end

  alias AshEvidence.AddressedAtom
  alias AshProvenance.{Address, Gap, Step}

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

  @doc """
  The provenance steps and gaps for the atoms an observation cited, on the `ash_provenance` contract.

  `derived` is the `AshProvenance.Address` of the record that cites `atom_ids`, usually a judgment observation. Each
  atom that still resolves for the reader gives a `:was_derived_from` step from `derived` to the atom's address
  (`type: "addressed_atom"`, same base as `derived`). No atom text or geometry is read or returned.

  An id that does not resolve for the reader gives a gap, never a silent drop:

    * `:unreadable` when `:existence_opts` finds the row and the reader's read did not. The gap carries nothing else.
    * `:erased` otherwise: the row is gone. When `:receipts` holds a trace reference for the id, the gap carries it
      and a `:was_invalidated_by` step names it.
    * `:not_recorded` for a cited id that is not a UUID, so it never named an atom.

  Options:

    * `:actor`, `:tenant`, `:authorize?` - the reader's read of the atoms.
    * `:existence_opts` - read options (for example `[authorize?: false]`) used only to ask whether an id that did not
      resolve still exists. Without it every unresolved id is `:erased`.
    * `:receipts` - a map of atom id to the erasure receipt's trace reference (`"<type>:<id>"`).

  The atoms are read in one query, and the existence check is a second one only when something did not resolve.
  """
  @spec provenance(Address.t(), [String.t()], keyword()) :: %{steps: [Step.t()], gaps: [Gap.t()]}
  def provenance(%Address{} = derived, atom_ids, opts \\ []) when is_list(atom_ids) do
    ids = Enum.uniq(atom_ids)
    {uuids, malformed} = Enum.split_with(ids, &match?({:ok, _}, Ecto.UUID.cast(&1)))

    found = read_created_at(uuids, Keyword.take(opts, [:actor, :tenant, :authorize?]))
    {resolved, unresolved} = Enum.split_with(uuids, &Map.has_key?(found, &1))
    existing = existing_ids(unresolved, opts[:existence_opts])
    receipts = Map.new(opts[:receipts] || %{})

    steps = Enum.map(resolved, &derived_step(derived, &1, found[&1]))

    {gone, hidden} = Enum.split_with(unresolved, &(&1 not in existing))

    erased = Enum.map(gone, &erased(derived, &1, receipts[&1]))

    %{
      steps: steps ++ Enum.flat_map(erased, &elem(&1, 0)),
      gaps:
        Enum.map(erased, &elem(&1, 1)) ++
          Enum.map(hidden, fn _ -> Gap.new!(kind: :unreadable, of: derived) end) ++
          Enum.map(malformed, fn _ ->
            Gap.new!(kind: :not_recorded, of: derived, summary: "a cited id is not an atom id")
          end)
    }
  end

  defp atom_address(%Address{} = derived, id) do
    Address.new!(base: derived.base, type: "addressed_atom", id: id)
  end

  defp derived_step(derived, id, created_at) do
    Step.new!(
      relation: :was_derived_from,
      entity: derived,
      antecedent: atom_address(derived, id),
      at: created_at,
      granularity: :record
    )
  end

  defp erased(derived, id, nil) do
    {[], Gap.new!(kind: :erased, of: derived, summary: "atom #{id} was erased")}
  end

  defp erased(derived, id, receipt) do
    step =
      Step.new!(
        relation: :was_invalidated_by,
        entity: atom_address(derived, id),
        activity: receipt,
        granularity: :record
      )

    {[step],
     Gap.new!(kind: :erased, of: derived, receipt: receipt, summary: "atom #{id} was erased")}
  end

  defp read_created_at([], _opts), do: %{}

  defp read_created_at(ids, opts) do
    AddressedAtom
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.select([:id, :created_at])
    |> Ash.read!()
    |> Map.new(&{&1.id, &1.created_at})
  end

  defp existing_ids([], _opts), do: []
  defp existing_ids(_ids, nil), do: []

  defp existing_ids(ids, opts) do
    AddressedAtom
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.select([:id])
    |> Ash.read!()
    |> Enum.map(& &1.id)
  end

  defp resolve_atoms(source_ids) do
    ids = Enum.filter(source_ids, fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end)

    if ids == [] do
      %{}
    else
      AddressedAtom
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.load([:id, :seq, :text, :kind, :page, :geometry])
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})
    end
  end

  defp source(atom) do
    %{
      atom_id: atom.id,
      seq: atom.seq,
      text: atom.text,
      kind: atom.kind,
      page: atom.page,
      geometry: atom.geometry
    }
  end
end
