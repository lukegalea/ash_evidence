# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.RetrievalTest do
  @moduledoc """
  The retrieval seam: hybrid (lexical + vector) candidate generation under
  competing hypotheses, over one version's addressed atoms.

  The fixtures are synthetic contract prose — no real document content.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.{CandidateSet, Domain, Retrieval}
  alias AshEvidence.Retrieval.Candidate
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(50)
    run = Fixtures.start_run(version)
    {:ok, version: version, run: run}
  end

  # ---------------------------------------------------------------------------
  # Dual-hypothesis candidate generation (lexical leg)
  # ---------------------------------------------------------------------------

  test "the claim's own clause surfaces first under :supports", %{
    version: version,
    run: run
  } do
    [exact, unrelated] =
      Fixtures.seed_atoms(version, run, [
        "the certificate expires on 2026-05-28",
        "the shipment arrives by freight"
      ])

    result = AshEvidence.retrieve!(version, "the certificate expires on 2026-05-28")

    assert [%Candidate{atom_id: atom_id} | _] = result.by_hypothesis.supports
    assert atom_id == exact.id
    refute unrelated.id in Enum.map(result.candidates, & &1.atom_id)
    assert result.legs == [:lexical]
  end

  test "the counter-hypothesis framing isolates negated language", %{
    version: version,
    run: run
  } do
    [exact, negated] =
      Fixtures.seed_atoms(version, run, [
        "the certificate coverage expires on 2026-05-28",
        "the certificate coverage never expires and is without limit"
      ])

    claim = "the certificate coverage expires"

    result = AshEvidence.retrieve!(version, claim)

    # The exact clause tops :supports; the negated clause IS retrieved
    # under :supports too (it shares the claim's terms) — contrastive
    # grouping, not exclusion.
    assert hd(result.by_hypothesis.supports).atom_id == exact.id
    assert negated.id in Enum.map(result.by_hypothesis.supports, & &1.atom_id)

    # :contradicts requires the contrast cues on top of the claim's terms,
    # so ONLY the negated clause qualifies there.
    assert Enum.map(result.by_hypothesis.contradicts, & &1.atom_id) == [negated.id]
  end

  test "a planted exception clause lands in the :exception set, not only the hypothesis set" do
    version = Fixtures.ingest_document(51)
    run = Fixtures.start_run(version)

    [echo, exception_clause] =
      Fixtures.seed_atoms(version, run, [
        "the membership fee is due annually",
        "exception: unless the member cancels, the membership fee is due annually as invoiced"
      ])

    result =
      AshEvidence.retrieve!(version, "the membership fee is due annually",
        hypotheses: [:supports, :contradicts, :exception]
      )

    assert exception_clause.id in Enum.map(result.by_hypothesis.exception, & &1.atom_id)
    refute echo.id in Enum.map(result.by_hypothesis.exception, & &1.atom_id)

    # The exception clause also surfaced under :supports (shared terms) —
    # the sets are labelled views, and the exception atom must not exist
    # in the hypothesis set ONLY.
    assert exception_clause.id in Enum.map(result.by_hypothesis.supports, & &1.atom_id)
  end

  test "k caps each hypothesis's candidate list", %{version: version, run: run} do
    Fixtures.seed_atoms(
      version,
      run,
      for(i <- 1..15, do: "gadget recall notice batch #{rem(i, 3)}")
    )

    result = AshEvidence.retrieve!(version, "gadget recall notice", k: 5)

    assert length(result.by_hypothesis.supports) == 5
    assert length(result.candidates) == 5
    assert result.k == 5
  end

  test "candidates never leak across versions" do
    v1 = Fixtures.ingest_document(52)
    v2 = Fixtures.ingest_document(53)
    r1 = Fixtures.start_run(v1)
    r2 = Fixtures.start_run(v2)

    Fixtures.seed_atoms(v1, r1, ["the deductible is waived once"])
    v2_atoms = Fixtures.seed_atoms(v2, r2, ["the deductible is waived twice"])

    result = AshEvidence.retrieve!(v1, "the deductible is waived")

    assert [_] = result.candidates
    assert hd(result.candidates).atom_id != hd(v2_atoms).id
    assert hd(result.candidates).atom_id == hd(Domain.atoms_for_version!(v1.id)).id
  end

  test "no candidates above the floor is an empty result, not an error", %{
    version: version
  } do
    result = AshEvidence.retrieve!(version, "zzqqx wuvbh")

    assert result.candidates == []
    assert result.by_hypothesis.supports == []
    assert result.by_hypothesis.contradicts == []
    assert result.legs == []
  end

  # ---------------------------------------------------------------------------
  # The vector leg
  # ---------------------------------------------------------------------------

  test "the vector leg ranks the closest embedding first, with no lexical overlap", %{
    version: version,
    run: run
  } do
    [near, far] =
      Fixtures.seed_atoms(version, run, [
        "purple elephants graze quietly",
        "mechanical wrenches assemble slowly"
      ])

    rep_near = Fixtures.project_atom(near) |> Fixtures.record_embedding([1.0, 0.0, 0.0, 0.0])

    _rep_far = Fixtures.project_atom(far) |> Fixtures.record_embedding([0.0, 1.0, 0.0, 0.0])

    claim = "animal behaviour near waterholes"

    result =
      AshEvidence.retrieve!(version, claim,
        vector: [0.9, 0.1, 0.0, 0.0],
        embedding_model: Fixtures.embedder()
      )

    # Both embeddings are retrieved (the vector leg returns k nearest);
    # the near one ranks first and its provenance is the vector leg only.
    assert [%Candidate{atom_id: atom_id, legs: legs}, _far] = result.by_hypothesis.supports
    assert atom_id == rep_near.addressed_atom_id
    assert %{vector: {1, score}} = legs.supports
    assert score > 0.5
    refute Map.has_key?(legs.supports, :lexical)
    assert result.legs == [:vector]
  end

  test "fusion boosts atoms surfaced by both legs", %{version: version, run: run} do
    [both, lexical_only] =
      Fixtures.seed_atoms(version, run, [
        "the deductible waiver applies here",
        "the deductible waiver applies there"
      ])

    Fixtures.project_atom(both) |> Fixtures.record_embedding([1.0, 0.0, 0.0, 0.0])
    Fixtures.project_atom(lexical_only) |> Fixtures.record_embedding([0.0, 1.0, 0.0, 0.0])

    result =
      AshEvidence.retrieve!(version, "the deductible waiver applies here",
        vector: [1.0, 0.0, 0.0, 0.0]
      )

    assert [%Candidate{atom_id: id, legs: legs} | _] = result.candidates
    assert id == both.id
    assert %{lexical: _, vector: _, rank: 1} = legs.supports

    # Both legs fed the winner's fused score; the lexical-only match
    # trails it despite sharing nearly all its terms.
    assert hd(result.candidates).score > Enum.at(result.candidates, 1).score
  end

  test "the embedding model scopes the vector leg", %{version: version, run: run} do
    [a, b] =
      Fixtures.seed_atoms(version, run, [
        "alpha row exists here",
        "beta row exists here"
      ])

    Fixtures.project_atom(a) |> Fixtures.record_embedding([1.0, 0.0, 0.0, 0.0])

    Fixtures.project_atom(b)
    |> Fixtures.record_embedding([1.0, 0.0, 0.0, 0.0], model: "other-embedder")

    result =
      AshEvidence.retrieve!(version, "nothing lexical matches this",
        vector: [1.0, 0.0, 0.0, 0.0],
        embedding_model: Fixtures.embedder()
      )

    assert Enum.map(result.candidates, & &1.atom_id) == [a.id]
  end

  test "representations without embeddings are invisible to the vector leg", %{
    version: version,
    run: run
  } do
    [unembedded, embedded] =
      Fixtures.seed_atoms(version, run, [
        "the first clause of note",
        "the second clause of note"
      ])

    Fixtures.project_atom(unembedded)
    Fixtures.project_atom(embedded) |> Fixtures.record_embedding([1.0, 0.0, 0.0, 0.0])

    result =
      AshEvidence.retrieve!(version, "clause of note entirely unmatched terms",
        vector: [1.0, 0.0, 0.0, 0.0]
      )

    assert Enum.map(result.candidates, & &1.atom_id) == [embedded.id]
  end

  # ---------------------------------------------------------------------------
  # Determinism (COMP-RETRIEVE/AC-3 posture)
  # ---------------------------------------------------------------------------

  test "identical inputs produce identical results, run twice" do
    version = Fixtures.ingest_document(54)
    run = Fixtures.start_run(version)

    Fixtures.seed_atoms(version, run, [
      "the premium is payable quarterly",
      "the premium is never payable quarterly",
      "unrelated boilerplate follows here"
    ])

    opts = [hypotheses: [:supports, :contradicts, :exception], vector: [1.0, 0.5, 0.25, 0.75]]

    Fixtures.project_atom(hd(Domain.atoms_for_version!(version.id)))
    |> Fixtures.record_embedding([1.0, 0.5, 0.25, 0.75])

    result_a = AshEvidence.retrieve!(version, "the premium is payable quarterly", opts)
    result_b = AshEvidence.retrieve!(version, "the premium is payable quarterly", opts)

    assert result_a == result_b
  end

  # ---------------------------------------------------------------------------
  # The projection + embedding contract
  # ---------------------------------------------------------------------------

  test "re-projecting an atom replaces the representation and voids the embedding", %{
    version: version,
    run: run
  } do
    [atom] = Fixtures.seed_atoms(version, run, ["the original clause"])

    rep = Fixtures.project_atom(atom, "the original projection")
    rep = Fixtures.record_embedding(rep, [1.0, 2.0, 3.0, 4.0])

    assert rep.embedding_model == Fixtures.embedder()

    replaced = Domain.project_atom!(atom.id, version.id, "the revised projection")

    assert replaced.id == rep.id
    assert replaced.representation == "the revised projection"
    assert is_nil(replaced.embedding_model)
    assert is_nil(replaced.embedding_model_version)

    reloaded = Ash.get!(AshEvidence.AtomRepresentation, rep.id)

    # Payload class: the vector is not selected by default...
    assert match?(%Ash.NotLoaded{field: :embedding}, reloaded.embedding)

    # ...and in the store the stale embedding is gone (voided by the
    # re-projection).
    %{rows: rows} =
      AshEvidence.Repo.query!(
        "SELECT (embedding IS NOT NULL), embedding_model FROM atom_representations WHERE id = $1",
        [Ecto.UUID.dump!(rep.id)]
      )

    assert [[false, nil]] = rows

    assert length(Domain.representations_for_version!(version.id)) == 1
  end

  test "record_embedding records the model name and version", %{version: version, run: run} do
    [atom] = Fixtures.seed_atoms(version, run, ["the clause to project"])

    rep =
      Fixtures.project_atom(atom)
      |> Fixtures.record_embedding([0.5, 0.5, 0.5, 0.5],
        model: "synthetic-test-embedder",
        version: "2.1"
      )

    assert rep.embedding_model == "synthetic-test-embedder"
    assert rep.embedding_model_version == "2.1"
  end

  # ---------------------------------------------------------------------------
  # The persisted CandidateSet (the proof a packet cites)
  # ---------------------------------------------------------------------------

  test "persist?: true records what was searched, hashes only", %{version: version, run: run} do
    [atom] = Fixtures.seed_atoms(version, run, ["the enforceable term is here"])

    result =
      AshEvidence.retrieve!(version, "the enforceable term is here",
        persist?: true,
        embedding_model: Fixtures.embedder(),
        embedding_model_version: "1"
      )

    assert result.candidate_set_id
    set = Domain.get_candidate_set!(result.candidate_set_id)

    assert set.document_version_id == version.id
    assert set.claim_hash == Base.encode16(:crypto.hash(:sha256, result.claim), case: :lower)

    assert set.query_hashes["supports"] ==
             Base.encode16(:crypto.hash(:sha256, result.queries.supports), case: :lower)

    assert set.k == result.k
    assert set.lexical_config == "english"
    assert set.embedding_model == Fixtures.embedder()
    assert set.embedding_model_version == "1"
    assert set.hypotheses == [:supports, :contradicts]

    # Candidates are id-shaped: ids, seqs, scores, hypotheses — no text.
    [candidate] = set.candidates
    assert candidate["atom_id"] == atom.id
    assert candidate["seq"] == 1
    assert is_float(candidate["score"])
    assert candidate["hypotheses"] == ["supports"]
    assert candidate["legs"]["supports"]["lexical"]["rank"] == 1
    refute Map.has_key?(candidate, "text")
  end

  test "the persisted set is identical for identical runs (AC-3 on the proof)" do
    version = Fixtures.ingest_document(55)
    run = Fixtures.start_run(version)
    Fixtures.seed_atoms(version, run, ["a term to retrieve here"])

    opts = [persist?: true]
    result_a = AshEvidence.retrieve!(version, "a term to retrieve", opts)
    result_b = AshEvidence.retrieve!(version, "a term to retrieve", opts)

    set_a = Domain.get_candidate_set!(result_a.candidate_set_id)
    set_b = Domain.get_candidate_set!(result_b.candidate_set_id)

    assert set_a.claim_hash == set_b.claim_hash
    assert set_a.query_hashes == set_b.query_hashes
    assert set_a.candidates == set_b.candidates
    assert set_a.id != set_b.id
  end

  test "candidate sets are FK-cascaded to their version (erasure linkage)" do
    version = Fixtures.ingest_document(56)
    run = Fixtures.start_run(version)
    Fixtures.seed_atoms(version, run, ["something retrievable"])

    result = AshEvidence.retrieve!(version, "something retrievable", persist?: true)
    assert %CandidateSet{} = Domain.get_candidate_set!(result.candidate_set_id)

    # Erasure on this scaffold is host-driven and act-by-act (ParseRun
    # ships no destroy), so the version-level cascade is asserted where it
    # lives: this package's own FK declares ON DELETE CASCADE, so whenever
    # the host tears the version down, the proof rows go with it.
    %{rows: rows} =
      AshEvidence.Repo.query!(
        "SELECT confdeltype FROM pg_constraint WHERE conname = 'candidate_sets_document_version_id_fkey'"
      )

    assert [["c"]] = rows
  end

  # ---------------------------------------------------------------------------
  # The lexical leg is index-backed (the CoiCoverage EXPLAIN precedent)
  # ---------------------------------------------------------------------------

  test "the lexical leg rides the GIN full-text index, not a seq scan", %{
    version: version,
    run: run
  } do
    # Scale for the planner: routine filler the query terms never match,
    # plus a few rows carrying the rare terms.
    filler = for i <- 1..300, do: "routine correspondence item #{i}"

    Fixtures.seed_atoms(
      version,
      run,
      filler ++ ["quokka habitat survey", "quokka habitat report"]
    )

    # Refresh planner stats so the sandboxed rows are what it sees.
    AshEvidence.Repo.query!("ANALYZE addressed_atoms")

    claim = "quokka habitat survey"
    query = Retrieval.framing_queries(claim, [:supports])

    sql = """
    EXPLAIN (FORMAT JSON)
    SELECT a.id::text, a.seq,
           ts_rank_cd(to_tsvector('english', a.text),
                      websearch_to_tsquery('english', $2)) AS score
    FROM addressed_atoms AS a
    WHERE a.document_version_id = $1
      AND to_tsvector('english', a.text) @@ websearch_to_tsquery('english', $2)
    ORDER BY score DESC, a.seq ASC, a.id ASC
    LIMIT $3
    """

    %{rows: rows} =
      AshEvidence.Repo.query!(sql, [Ecto.UUID.dump!(version.id), query.supports, 10])

    plan = hd(rows) |> hd()
    index_names = plan |> List.wrap() |> plan_index_names()

    assert "addressed_atoms_text_fts_index" in index_names,
           "the lexical leg must ride the full-text index, got plan: #{inspect(plan, limit: 30)}"
  end

  defp plan_index_names(node) when is_map(node) do
    index_name =
      case Map.fetch(node, "Index Name") do
        {:ok, name} -> [name]
        :error -> []
      end

    nested =
      node
      |> Map.take(["Plan", "Plans"])
      |> Map.values()
      |> List.wrap()
      |> Enum.flat_map(&plan_index_names/1)

    index_name ++ nested
  end

  defp plan_index_names(list) when is_list(list), do: Enum.flat_map(list, &plan_index_names/1)

  defp plan_index_names(_other), do: []
end
