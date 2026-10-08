# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Retrieval do
  @moduledoc """
  Hybrid retrieval over one document version's addressed atoms, with
  dual-hypothesis candidate generation.

  Retrieval that only looks for support manufactures false supports, so
  a claim is retrieved under competing framings — at minimum the
  hypothesis and the counter-hypothesis (the ContractNLI
  entailed/contradicted/not-mentioned posture), optionally the exception
  framing. Each framing runs its own query and keeps its own ranked set;
  what downstream adjudication receives is contrastive candidates, not a
  flat list. A candidate records WHICH framing surfaced it and at what
  rank and score.

  Two legs, fused per framing with reciprocal rank fusion:

    * **Lexical** — Postgres full-text over the atoms' own text
      (`to_tsvector('english', text)`, GIN-indexed; `ts_rank_cd`
      ranking). Always runs.
    * **Vector** — exact cosine scan over the version's
      `AshEvidence.AtomRepresentation` embeddings. Runs when the caller
      supplies the claim's embedding (`:vector`) — the host embeds,
      this package records and scores; there is no embedding model
      here. Exact scan keeps retrieval deterministic (a property this
      seam is held to); a host that needs ANN at scale adds an `hnsw`
      index host-side, pinned to its model's dimensions — this query
      does not change.

  Ranking is not existence and retrieval confidence is not entailment
  confidence: the scores here say how well an atom matched a query,
  nothing more. No thresholds, no verdicts — the scores and hypothesis
  labels go to the caller (the packets seam) as ranked, labelled ids.

  Determinism: same inputs against the same indexes produce the same
  result — deterministic default queries, deterministic SQL ordering
  (score, then seq, then id), stable fusion, exact scan.

  Framing defaults are lexical heuristics, deliberately: `:supports`
  queries the claim verbatim; `:contradicts` and `:exception` AND the
  claim with fixed contrast cues (`never without`, `except unless` —
  cues chosen outside Postgres' english stoplist). A host that wants
  model-written counter-hypothesis queries passes `queries:`.
  """

  alias AshEvidence.CandidateSet
  alias AshEvidence.Repo

  @framings [:supports, :contradicts, :exception]
  @default_framings [:supports, :contradicts]
  @default_k 10
  @rrf_k 60
  @lexical_config "english"

  # Contrast cues per framing, ANDed onto the claim's terms. These are
  # query-construction heuristics (fixed, deterministic), not policy: no
  # threshold, no verdict, no filtering of results happens here.
  @framing_cues [
    supports: [],
    contradicts: ["never", "without"],
    exception: ["except", "unless"]
  ]

  @typedoc "The framing a candidate was retrieved under"
  @type framing :: :supports | :contradicts | :exception

  @typedoc "Rank (1-based) and raw score within one leg of one framing"
  @type leg_hit :: {rank :: pos_integer(), score :: float()}

  defmodule Candidate do
    @moduledoc """
    One retrieved atom, as the retrieval seam carries it: the atom id
    (the packet currency), its address, fused score, and per-framing
    provenance.

    `legs` is keyed by framing; each framing entry carries the fused
    `rank` and `score` within that framing, plus the raw leg hits that
    fed the fusion (`lexical:` / `vector:` as `{rank, score}`) for the
    legs that surfaced the atom. No text travels with a candidate; text
    resolves from the store.
    """

    defstruct [:atom_id, :seq, :score, :hypotheses, :legs]

    @type t :: %__MODULE__{
            atom_id: String.t(),
            seq: pos_integer(),
            score: float(),
            hypotheses: [AshEvidence.Retrieval.framing()],
            legs: %{
              required(AshEvidence.Retrieval.framing()) => %{
                required(:rank) => pos_integer(),
                required(:score) => float(),
                optional(:lexical) => AshEvidence.Retrieval.leg_hit(),
                optional(:vector) => AshEvidence.Retrieval.leg_hit()
              }
            }
          }
  end

  defmodule Result do
    @moduledoc """
    The outcome of one retrieval: the queries each framing ran, the
    merged ranked candidates, and the per-hypothesis grouping downstream
    adjudication consumes. `candidate_set_id` is set when the retrieval
    was persisted (`persist?: true`).
    """

    defstruct [
      :document_version_id,
      :claim,
      :queries,
      :k,
      :framings,
      :legs,
      :embedding_model,
      :candidates,
      :by_hypothesis,
      :candidate_set_id
    ]

    @type t :: %__MODULE__{
            document_version_id: String.t(),
            claim: String.t(),
            queries: %{AshEvidence.Retrieval.framing() => String.t()},
            k: pos_integer(),
            framings: [AshEvidence.Retrieval.framing()],
            legs: [:lexical | :vector],
            embedding_model: String.t() | nil,
            candidates: [AshEvidence.Retrieval.Candidate.t()],
            by_hypothesis: %{
              AshEvidence.Retrieval.framing() => [AshEvidence.Retrieval.Candidate.t()]
            },
            candidate_set_id: String.t() | nil
          }
  end

  @doc "The framings retrieval knows."
  @spec framings() :: [framing()]
  def framings, do: @framings

  @doc """
  The deterministic default query per framing for a claim, with any
  caller overrides applied (`overrides` is a framing → query-text map or
  keyword). Overriding is the seam for model-written counter-hypothesis
  queries.
  """
  @spec framing_queries(String.t(), [framing()], keyword() | map()) ::
          %{framing() => String.t()}
  def framing_queries(claim, framings, overrides \\ [])

  def framing_queries(claim, framings, overrides) when is_binary(claim) and is_list(framings) do
    overrides = Map.new(overrides)

    Map.new(framings, fn framing ->
      case Map.fetch(overrides, framing) do
        {:ok, text} when is_binary(text) ->
          {framing, text}

        {:ok, other} ->
          raise ArgumentError,
                "query for #{inspect(framing)} must be a string, got: #{inspect(other)}"

        :error ->
          {framing, default_framing_query(claim, framing)}
      end
    end)
  end

  def framing_queries(_claim, _framings, _overrides) do
    raise ArgumentError, "claim must be a string"
  end

  @doc """
  Retrieve candidates for `claim` over `version`'s atoms.

  ## Options

    * `:hypotheses` — framings to run. Default `[:supports, :contradicts]`;
      `:exception` is opt-in (or pass all three).
    * `:queries` — per-framing query text overrides (keyword or map),
      used verbatim instead of the deterministic defaults.
    * `:k` — per-hypothesis candidate cap. Default 10.
    * `:vector` — the claim's embedding, as a list of numbers, an
      `Ash.Vector`, or a per-framing keyword of those. Supplied per the
      host's embedder; when absent only the lexical leg runs.
    * `:embedding_model` — restrict the vector leg to representations
      embedded by this model (cosine across models is meaningless) and
      record it on the persisted set.
    * `:embedding_model_version` — recorded on the persisted set.
    * `:persist?` — record an `AshEvidence.CandidateSet` (query text
      hashes, index versions, k, ranked candidates) so a packet can
      prove what was searched. Default `false`.
  """
  @spec retrieve(AshEvidence.DocumentVersion.t() | String.t(), String.t(), keyword()) ::
          {:ok, Result.t()}
  def retrieve(version_or_id, claim, opts \\ []) do
    version_id = version_id(version_or_id)

    unless is_binary(claim), do: raise(ArgumentError, "claim must be a string")

    framings = framings!(Keyword.get(opts, :hypotheses, @default_framings))
    k = positive_k!(Keyword.get(opts, :k, @default_k))
    queries = framing_queries(claim, framings, Keyword.get(opts, :queries, []))

    vectors = normalize_vectors(Keyword.get(opts, :vector), framings)
    model = Keyword.get(opts, :embedding_model)

    {fused, legs} = run_legs(version_id, queries, vectors, model, k)

    {candidates, by_hypothesis} = merge_framings(fused, k)

    result = %Result{
      document_version_id: version_id,
      claim: claim,
      queries: queries,
      k: k,
      framings: framings,
      legs: legs,
      embedding_model: model,
      candidates: candidates,
      by_hypothesis: by_hypothesis,
      candidate_set_id: nil
    }

    {:ok, maybe_persist(result, Keyword.get(opts, :persist?, false), opts)}
  end

  @doc "Raising `retrieve/3`."
  @spec retrieve!(AshEvidence.DocumentVersion.t() | String.t(), String.t(), keyword()) ::
          Result.t()
  def retrieve!(version_or_id, claim, opts \\ []) do
    {:ok, result} = retrieve(version_or_id, claim, opts)
    result
  end

  ## Framings and queries

  defp framings!(framings) do
    if is_list(framings) and framings != [] and Enum.all?(framings, &(&1 in @framings)) do
      framings
    else
      raise ArgumentError,
            "hypotheses must be a non-empty subset of #{inspect(@framings)}, " <>
              "got: #{inspect(framings)}"
    end
  end

  defp positive_k!(k) when is_integer(k) and k > 0, do: k

  defp positive_k!(k) do
    raise ArgumentError, "k must be a positive integer, got: #{inspect(k)}"
  end

  defp default_framing_query(claim, framing) do
    case Keyword.fetch!(@framing_cues, framing) do
      [] -> claim
      cues -> String.trim(claim) <> " " <> Enum.join(cues, " ")
    end
  end

  ## Vector input

  defp normalize_vectors(nil, _framings), do: %{}

  defp normalize_vectors(%Ash.Vector{} = vector, framings), do: per_framing(framings, vector)

  defp normalize_vectors(vectors, framings) when is_list(vectors) do
    if Keyword.keyword?(vectors) do
      keyword_vectors(vectors, framings)
    else
      cast_vector!(vectors) |> then(&per_framing(framings, &1))
    end
  end

  defp normalize_vectors(other, _framings) do
    raise ArgumentError,
          "vector must be a list of numbers, an Ash.Vector, or a per-framing keyword of " <>
            "those, got: #{inspect(other)}"
  end

  defp keyword_vectors(vectors, framings) do
    Map.new(vectors, fn {framing, value} ->
      unless framing in framings do
        raise ArgumentError,
              "vector given for #{inspect(framing)}, which is not among the requested " <>
                "hypotheses #{inspect(framings)}"
      end

      {framing, cast_vector!(value)}
    end)
  end

  defp cast_vector!(%Ash.Vector{} = vector), do: vector

  defp cast_vector!(list) when is_list(list) do
    case Ash.Vector.new(list) do
      {:ok, vector} -> vector
      {:error, :invalid_vector} -> raise ArgumentError, "not a valid vector: #{inspect(list)}"
    end
  end

  defp cast_vector!(other), do: raise(ArgumentError, "not a valid vector: #{inspect(other)}")

  defp per_framing(framings, vector), do: Map.new(framings, &{&1, vector})

  ## Legs

  defp run_legs(version_id, queries, vectors, model, k) do
    {fused, legs} =
      Enum.map_reduce(queries, MapSet.new(), fn {framing, query}, legs ->
        lexical = lexical_leg(version_id, query, k)
        legs = if lexical != [], do: MapSet.put(legs, :lexical), else: legs

        vector = vector_leg(version_id, Map.get(vectors, framing), model, k)
        legs = if vector != [], do: MapSet.put(legs, :vector), else: legs

        {{framing, {fuse(lexical, vector), lexical, vector}}, legs}
      end)

    ordered_legs = Enum.filter([:lexical, :vector], &MapSet.member?(legs, &1))
    {Map.new(fused), ordered_legs}
  end

  # The lexical leg: full-text over the version's own atom text, ranked
  # by ts_rank_cd, capped at k. Every value is a parameter — nothing
  # caller-supplied is ever interpolated into the SQL.
  @lexical_sql """
  SELECT a.id::text, a.seq,
         ts_rank_cd(to_tsvector('english', a.text),
                    websearch_to_tsquery('english', $2)) AS score
  FROM addressed_atoms AS a
  WHERE a.document_version_id = $1
    AND to_tsvector('english', a.text) @@ websearch_to_tsquery('english', $2)
  ORDER BY score DESC, a.seq ASC, a.id ASC
  LIMIT $3
  """

  defp lexical_leg(version_id, query, k) do
    %{rows: rows} = Repo.query!(@lexical_sql, [uuid_param(version_id), query, k])

    rows
    |> Enum.with_index(1)
    |> Enum.map(fn {[atom_id, seq, score], rank} -> {atom_id, seq, rank, score} end)
    |> Enum.reject(fn {_atom_id, _seq, _rank, score} -> score <= 0.0 end)
  end

  # The vector leg: exact cosine scan over the version's representations,
  # nearest first, capped at k. Only embeddings the host recorded run
  # here; rows without embeddings are invisible to it.
  @vector_sql """
  SELECT r.addressed_atom_id::text, a.seq,
         1 - (r.embedding <=> $2) AS score
  FROM atom_representations AS r
  JOIN addressed_atoms AS a ON a.id = r.addressed_atom_id
  WHERE r.document_version_id = $1
    AND r.embedding IS NOT NULL
    AND ($3::text IS NULL OR r.embedding_model = $3)
  ORDER BY r.embedding <=> $2
  LIMIT $4
  """

  defp vector_leg(_version_id, nil, _model, _k), do: []

  defp vector_leg(version_id, %Ash.Vector{} = vector, model, k) do
    %{rows: rows} = Repo.query!(@vector_sql, [uuid_param(version_id), vector, model, k])

    rows
    |> Enum.with_index(1)
    |> Enum.map(fn {[atom_id, seq, score], rank} -> {atom_id, seq, rank, score} end)
  end

  ## Fusion

  # Reciprocal rank fusion within one framing: a candidate's fused score
  # is the sum of 1/(K + rank) over the legs that surfaced it. Stable and
  # deterministic given identical leg results.
  @spec fuse([tuple()], [tuple()]) :: [
          {atom_id :: String.t(), seq :: pos_integer(), fused :: float(), legs :: map()}
        ]
  defp fuse(lexical, vector) do
    tagged =
      Enum.map(lexical, fn {atom_id, seq, rank, score} ->
        {atom_id, seq, :lexical, rank, score}
      end) ++
        Enum.map(vector, fn {atom_id, seq, rank, score} ->
          {atom_id, seq, :vector, rank, score}
        end)

    tagged
    |> Enum.group_by(fn {atom_id, _seq, _leg, _rank, _score} -> atom_id end)
    |> Enum.map(fn {atom_id, hits} ->
      # All hits for an atom share its seq (one atom, one address).
      seq =
        hits
        |> Enum.map(fn {_id, s, _leg, _rank, _score} -> s end)
        |> Enum.min()

      leg_details =
        Map.new(hits, fn {_id, _s, leg, rank, score} -> {leg, {rank, score}} end)

      fused =
        hits
        |> Enum.map(fn {_id, _s, _leg, rank, _score} -> 1.0 / (@rrf_k + rank) end)
        |> Enum.sum()

      {atom_id, seq, fused, leg_details}
    end)
    |> Enum.sort_by(fn {_atom_id, seq, fused, _legs} -> {-fused, seq} end)
  end

  ## Merge across framings

  # Cap each framing's fused list at k. The per-framing lists become the
  # result's hypothesis grouping (contrastive sets, each in its own fused
  # rank order); the merge across framings produces the flat ranked list:
  # one candidate per atom, total score = sum of per-framing fused scores.
  # Sorted by score, then seq, then id — deterministic.
  @spec merge_framings(map(), pos_integer()) :: {[Candidate.t()], %{framing() => [Candidate.t()]}}
  defp merge_framings(fused_by_framing, k) do
    by_hypothesis =
      Map.new(fused_by_framing, fn {framing, {fused, _lexical, _vector}} ->
        {framing,
         fused
         |> Enum.take(k)
         |> Enum.with_index(1)
         |> Enum.map(fn {{atom_id, seq, fused_score, leg_details}, rank} ->
           %Candidate{
             atom_id: atom_id,
             seq: seq,
             score: fused_score,
             hypotheses: [framing],
             legs: %{framing => framing_detail(leg_details, rank, fused_score)}
           }
         end)}
      end)

    candidates =
      fused_by_framing
      |> Enum.flat_map(fn {framing, {fused, _lexical, _vector}} ->
        fused
        |> Enum.take(k)
        |> Enum.with_index(1)
        |> Enum.map(fn {{atom_id, seq, fused_score, leg_details}, rank} ->
          {atom_id, seq, framing, rank, fused_score, leg_details}
        end)
      end)
      |> Enum.group_by(fn {atom_id, _seq, _framing, _rank, _score, _legs} -> atom_id end)
      |> Enum.map(fn {atom_id, appearances} ->
        seq =
          appearances
          |> Enum.map(fn {_id, s, _f, _r, _sc, _l} -> s end)
          |> Enum.min()

        hypotheses =
          appearances |> Enum.map(fn {_id, _s, f, _r, _sc, _l} -> f end) |> Enum.uniq()

        legs =
          Map.new(appearances, fn {_id, _s, framing, rank, fused_score, leg_details} ->
            {framing, framing_detail(leg_details, rank, fused_score)}
          end)

        total =
          appearances
          |> Enum.map(fn {_id, _s, _f, _r, score, _l} -> score end)
          |> Enum.sum()

        %Candidate{atom_id: atom_id, seq: seq, score: total, hypotheses: hypotheses, legs: legs}
      end)
      |> Enum.sort_by(fn %Candidate{atom_id: atom_id, seq: seq, score: score} ->
        {-score, seq, atom_id}
      end)

    {candidates, by_hypothesis}
  end

  defp framing_detail(leg_details, rank, fused_score) do
    leg_details
    |> Map.put(:rank, rank)
    |> Map.put(:score, fused_score)
  end

  ## Persistence

  defp maybe_persist(result, false, _opts), do: result

  defp maybe_persist(result, true, opts) do
    set =
      Ash.create!(CandidateSet, %{
        document_version_id: result.document_version_id,
        claim_hash: sha256(result.claim),
        query_hashes: Map.new(result.queries, fn {framing, text} -> {framing, sha256(text)} end),
        k: result.k,
        lexical_config: @lexical_config,
        embedding_model: result.embedding_model,
        embedding_model_version: Keyword.get(opts, :embedding_model_version),
        hypotheses: result.framings,
        candidates: Enum.map(result.candidates, &serialize_candidate/1)
      })

    %{result | candidate_set_id: set.id}
  end

  defp serialize_candidate(%Candidate{} = candidate) do
    %{
      "atom_id" => candidate.atom_id,
      "seq" => candidate.seq,
      "score" => candidate.score,
      "hypotheses" => Enum.map(candidate.hypotheses, &to_string/1),
      "legs" =>
        Map.new(candidate.legs, fn {framing, detail} ->
          {to_string(framing), serialize_framing_detail(detail)}
        end)
    }
  end

  defp serialize_framing_detail(detail) do
    detail
    |> Map.new(fn
      {:lexical, {rank, score}} -> {"lexical", %{"rank" => rank, "score" => score}}
      {:vector, {rank, score}} -> {"vector", %{"rank" => rank, "score" => score}}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp sha256(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  # Raw-SQL parameters for uuid columns are 16-byte binaries (Ecto does
  # this conversion for schema loads; the engine does it here).
  defp uuid_param(id) do
    case Ecto.UUID.dump(id) do
      {:ok, binary} -> binary
      :error -> raise ArgumentError, "not a uuid: #{inspect(id)}"
    end
  end

  defp version_id(%AshEvidence.DocumentVersion{id: id}), do: id

  defp version_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "not a document version id: #{inspect(id)}"
    end
  end

  defp version_id(other), do: raise(ArgumentError, "not a document version: #{inspect(other)}")
end
