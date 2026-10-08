# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Domain do
  @moduledoc """
  The Ash domain of the evidence pipeline: document versions, parse runs,
  addressed atoms, their retrieval projections, and the candidate sets
  retrieval records.

  Hosts add this module to their `config :ash, ash_domains` (or call the
  code interfaces directly — they are the intended surface). The code
  interfaces mirror the slice-0 pipeline sequence: ingest a document
  version, start a parse run, seed/record atoms, close the run — and the
  retrieval seams: project an atom for the vector leg, record the
  embedding the host's model produced.

  `validate_config_inclusion?: false` because this is a library-shipped
  domain: it belongs in the HOST's `ash_domains`, never in this package's
  own app config.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshEvidence.DocumentVersion do
      define :ingest_document, action: :ingest, args: [:kind, :bytes, :sha256]
      define :get_document_version, action: :read, get_by: [:id]
    end

    resource AshEvidence.ParseRun do
      define :start_parse_run, action: :start, args: [:document_version_id, :instrument]
      define :mark_parse_run_ok, action: :mark_ok
      define :mark_parse_run_failed, action: :mark_failed
    end

    resource AshEvidence.AddressedAtom do
      define :ingest_atom,
        action: :ingest,
        args: [:document_version_id, :parse_run_id, :seq, :text]

      define :atoms_for_version, action: :for_version, args: [:document_version_id]
      define :atoms_for_run, action: :for_run, args: [:parse_run_id]
      define :atoms_by_ids, action: :by_ids, args: [:ids]
    end

    resource AshEvidence.EvidenceEvaluation do
      define :start_evaluation, action: :start
      define :get_evaluation, action: :read, get_by: [:id]
      define :mark_evaluation_ok, action: :mark_ok
      define :mark_evaluation_failed, action: :mark_failed
      define :evaluations_for_version, action: :for_version, args: [:document_version_id]
    end

    resource AshEvidence.Packet do
      define :assemble_packet, action: :assemble
      define :get_packet, action: :read, get_by: [:id]
      define :record_packet_adjudication, action: :record_adjudication
      define :packets_for_evaluation, action: :for_evaluation, args: [:evaluation_id]
    end

    resource AshEvidence.AtomRepresentation do
      define :project_atom,
        action: :project,
        args: [:addressed_atom_id, :document_version_id, :representation]

      define :record_embedding,
        action: :record_embedding,
        args: [:embedding, :embedding_model, :embedding_model_version]

      define :representations_for_version,
        action: :for_version,
        args: [:document_version_id]
    end

    resource AshEvidence.CandidateSet do
      define :record_candidate_set, action: :record
      define :get_candidate_set, action: :read, get_by: [:id]
    end

    resource AshEvidence.EvalSet do
      define :open_eval_set,
        action: :open,
        args: [:name, :version, :description, :split_seed, :split_provenance]

      define :get_eval_set, action: :read, get_by: [:id]
      define :get_eval_set_by_name_version, action: :by_name_version, args: [:name, :version]
      define :publish_eval_set, action: :publish
    end

    resource AshEvidence.EvalItem do
      define :add_eval_item, action: :add
      define :get_eval_item, action: :read, get_by: [:id]
      define :items_for_set, action: :for_set, args: [:eval_set_id]
    end
  end
end
