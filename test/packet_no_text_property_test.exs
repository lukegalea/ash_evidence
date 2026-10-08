# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.PacketNoTextPropertyTest do
  @moduledoc """
  AC-1 as a PROPERTY: for arbitrarily composed packets over an atom
  corpus, the serialised packet (and its evaluation row) carries atom
  ids, hashes and scores — and never a byte of atom text.

  The generator is a seeded pseudo-random loop (no new dependencies):
  every iteration draws a fresh candidate subset, fresh observation
  joins, fresh selected/limiting/missing sets, assembles a real packet
  through the domain, and serialises it.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Test.Fixtures

  @moduletag :db

  @iterations 15
  # Each corpus text carries a unique sentinel token; the serialised
  # bytes must contain none of them.
  @texts for i <- 1..8, do: "clause #{i} bearing sentinel QWUX#{i}ZZ token"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    # Reproducible pseudo-random draws, process-local (async-safe).
    :rand.seed(:exsss, {1515, 51_000, 7})
    :ok
  end

  test "no serialised packet ever carries atom text" do
    version = Fixtures.ingest_document(70)
    run = Fixtures.start_run(version)
    atoms = Fixtures.seed_atoms(version, run, @texts)
    ids = Enum.map(atoms, & &1.id)
    tokens = Enum.map(@texts, fn text -> sentinel(text) end)

    evaluation = Fixtures.start_evaluation(version)

    for _ <- 1..@iterations do
      candidate_ids = Enum.filter(ids, fn _ -> :rand.uniform() < 0.6 end)
      candidate_ids = if candidate_ids == [], do: [hd(ids)], else: candidate_ids

      joins =
        Map.new(candidate_ids, fn id ->
          {id, Fixtures.observation_join(Ash.UUID.generate(), Fixtures.hash_of(id))}
        end)

      packet =
        Fixtures.assemble_packet(evaluation, candidate_ids,
          candidate_observations: joins,
          selected_atom_ids: Enum.filter(candidate_ids, fn _ -> :rand.uniform() < 0.4 end),
          limiting_atom_ids: Enum.filter(candidate_ids, fn _ -> :rand.uniform() < 0.3 end),
          missing_dimensions: for(_ <- 1..:rand.uniform(3), do: "dimension-#{:rand.uniform(5)}"),
          requires_expansion: :rand.uniform() < 0.5
        )

      serialised = Jason.encode!(packet_map(packet))

      for token <- tokens do
        refute String.contains?(serialised, token),
               "the serialised packet leaked atom text (sentinel #{token})"
      end

      # And no full text either, for defence in depth.
      for text <- @texts do
        refute String.contains?(serialised, text)
      end
    end
  end

  test "no serialised evaluation ever carries atom text either" do
    version = Fixtures.ingest_document(71)
    run = Fixtures.start_run(version)
    Fixtures.seed_atoms(version, run, @texts)
    tokens = Enum.map(@texts, &sentinel/1)

    for _ <- 1..@iterations do
      evaluation =
        Fixtures.start_evaluation(version,
          candidate_set_ids: [Ash.UUID.generate()],
          expansion_steps: [
            %{
              step: 1,
              candidate_set_id: Ash.UUID.generate(),
              observation_ids: [Ash.UUID.generate()]
            }
          ]
        )

      serialised =
        Jason.encode!(%{
          "id" => evaluation.id,
          "subject" => evaluation.subject,
          "predicate" => evaluation.predicate,
          "rule_ref" => evaluation.rule_ref,
          "question_set_hash" => evaluation.question_set_hash,
          "candidate_set_ids" => evaluation.candidate_set_ids,
          "expansion_steps" => evaluation.expansion_steps,
          "profile" => evaluation.profile,
          "call_shape" => evaluation.call_shape,
          "status" => evaluation.status
        })

      for token <- tokens do
        refute String.contains?(serialised, token),
               "the serialised evaluation leaked atom text (sentinel #{token})"
      end
    end
  end

  # The packet as it crosses the wire: every packet attribute, keyed as
  # the record holds it.
  defp packet_map(packet) do
    %{
      "id" => packet.id,
      "evaluation_id" => packet.evaluation_id,
      "candidate_atom_ids" => packet.candidate_atom_ids,
      "candidate_observations" => packet.candidate_observations,
      "selected_atom_ids" => packet.selected_atom_ids,
      "limiting_atom_ids" => packet.limiting_atom_ids,
      "missing_dimensions" => packet.missing_dimensions,
      "requires_expansion" => packet.requires_expansion,
      "created_at" => packet.created_at
    }
  end

  # The unique token inside a corpus text ("... sentinel QWUX<i>ZZ ...").
  defp sentinel(text) do
    [token] = Regex.run(~r/QWUX\d+ZZ/, text)
    token
  end
end
