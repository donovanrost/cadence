defmodule Cadence.Runtime.TransportRecords.Reconciliation do
  @moduledoc """
  Audited prepared-send interpretation, separate from local send status.

  A frame occurrence is (preparation ID, ordinal, frame hash), never a sequence
  number or content hash alone. Interpretations are evidence, not send authority:
  this boundary neither changes protocol state nor resolves command attempts.
  """
  import Ecto.Query
  alias Cadence.Platform.{ContentHash, ResolutionEvidence}
  alias Cadence.Repo

  alias Cadence.Runtime.TransportRecords.{
    TransportActionRequestRow,
    TransportCapabilityRecordRow,
    TransportTimerEventRow
  }

  def review(organization, mission, id, opts) do
    transaction(fn ->
      target = target!(organization, mission, id)
      snapshot(organization, mission, target, opts)
    end)
  end

  def reconcile(organization, mission, id, evidence, opts) do
    transaction(fn ->
      target = target!(organization, mission, id)
      resource = target.metadata["resource_id"]

      # Serialize audits for this resource; never used for placement or send authority.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "prepared-send-reconciliation:" <> resource
      ])

      # Stable order, including other attempts sharing this physical stream. Send
      # observation updates lock these same rows, so cannot change beneath the audit.
      sends =
        Repo.all(
          from(r in send_query(resource), order_by: r.action_request_id, lock: "FOR UPDATE")
        )

      target = Enum.find(sends, &(&1.action_request_id == id))

      case existing(target.reconciliation_evidence, evidence) do
        {:ok, entry} -> result(target, entry)
        {:error, reason} -> Repo.rollback(reason)
        :new -> apply_evidence(organization, mission, target, sends, evidence, opts)
      end
    end)
  end

  defp apply_evidence(organization, mission, target, sends, evidence, opts) do
    review = snapshot(organization, mission, target, opts, sends)

    unless review.basis_sha256 == evidence["basis_sha256"],
      do: Repo.rollback(:stale_reconciliation_basis)

    disposition = disposition(target, evidence)

    log =
      case ResolutionEvidence.append(
             target.reconciliation_evidence,
             Map.put(evidence, "review_basis", review.basis),
             disposition
           ) do
        {:ok, log} -> log
        {:error, reason} -> Repo.rollback(reason)
      end

    updated = target |> Ecto.Changeset.change(reconciliation_evidence: log) |> Repo.update!()
    result(updated, List.last(log["entries"]))
  end

  defp target!(organization, mission, id) do
    Repo.one(
      from(r in TransportActionRequestRow,
        where:
          r.organization_id == ^organization and r.mission_id == ^mission and
            r.action_request_id == ^id and r.action_kind == "provider_send_prepared"
      )
    ) || Repo.rollback(:prepared_send_not_found)
  end

  defp snapshot(organization, mission, target, opts, sends \\ nil) do
    resource = target.metadata["resource_id"]
    sends = sends || Repo.all(from(r in send_query(resource), order_by: r.action_request_id))

    unless Enum.all?(sends, &(&1.organization_id == organization and &1.mission_id == mission)),
      do: Repo.rollback(:prepared_send_scope_conflict)

    streams =
      Enum.uniq_by(sends, &{&1.realized_contact_id, &1.path_id, &1.capability_instance_id})

    scope = stream_scope(streams)

    observations =
      Repo.all(
        from(r in TransportCapabilityRecordRow,
          where: r.organization_id == ^organization and r.mission_id == ^mission,
          where: ^scope,
          order_by: r.transport_record_id
        )
      )

    timers =
      Repo.all(
        from(r in TransportTimerEventRow,
          where: r.organization_id == ^organization and r.mission_id == ^mission,
          where: ^scope,
          order_by: r.timer_event_id
        )
      )

    actions =
      Repo.all(
        from(r in TransportActionRequestRow,
          where: r.organization_id == ^organization and r.mission_id == ^mission,
          where: ^scope,
          order_by: r.action_request_id
        )
      )

    attempts = attempts(sends, opts)

    basis = %{
      schema_version: 1,
      organization_id: organization,
      mission_id: mission,
      resource_id: resource,
      preparation_id: target.action_request_id,
      sends: Enum.map(sends, &reference/1),
      observations: Enum.map(observations, &reference/1),
      actions: Enum.map(actions, &reference/1),
      timers: Enum.map(timers, &reference/1),
      attempts: Map.new(attempts, fn {id, attempt} -> {id, ContentHash.term_sha256(attempt)} end)
    }

    basis = basis |> Jason.encode!() |> Jason.decode!()

    %{
      basis_sha256: ContentHash.term_sha256(basis),
      basis: basis,
      preparation: TransportActionRequestRow.to_domain(target),
      prepared_sends: Enum.map(sends, &TransportActionRequestRow.to_domain/1),
      frame_occurrences:
        Enum.map(
          target.request_document["frames"],
          &Map.put(&1, "preparation_id", target.action_request_id)
        ),
      automatic_takeover_allowed?: false
    }
  end

  defp stream_scope(sends) do
    Enum.reduce(sends, dynamic(false), fn send, acc ->
      dynamic(
        [r],
        ^acc or
          (r.realized_contact_id == ^send.realized_contact_id and r.path_id == ^send.path_id and
             r.capability_instance_id == ^send.capability_instance_id)
      )
    end)
  end

  defp attempts(sends, opts) do
    ids =
      sends
      |> Enum.map(& &1.command_release_attempt_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    Keyword.get(opts, :attempt_basis, fn _ids -> %{} end).(ids)
  end

  defp existing(log, evidence) do
    prior =
      Enum.find(Map.get(log, "entries", []), &(&1["resolution_id"] == evidence["resolution_id"]))

    enriched =
      if prior, do: Map.put(evidence, "review_basis", prior["review_basis"]), else: evidence

    ResolutionEvidence.existing(log, enriched)
  end

  defp reference(row) do
    %{
      "id" =>
        Map.get(row, :action_request_id) || Map.get(row, :transport_record_id) ||
          Map.get(row, :timer_event_id),
      "sha256" => ContentHash.term_sha256(row_basis(row))
    }
  end

  defp row_basis(row), do: row |> Map.from_struct() |> Map.drop([:__meta__])

  defp send_query(resource) do
    from(r in TransportActionRequestRow,
      where:
        r.action_kind == "provider_send_prepared" and
          fragment("? ->> 'resource_id' = ?", r.metadata, ^resource)
    )
  end

  defp disposition(target, evidence) do
    frames = target.request_document["frames"]

    cond do
      evidence["session_ref"] != target.metadata["incarnation"] or
          not Enum.all?(evidence["frames"], &correlated?(&1, frames)) ->
        "held_uncorrelated"

      contradictory?(target.reconciliation_evidence, evidence) ->
        "held_contradictory"

      Enum.any?(evidence["frames"], &(&1["outcome"] == "unknown")) ->
        "held_unknown"

      length(evidence["frames"]) != length(frames) ->
        "held_partial"

      true ->
        "recorded_pending_qualified_recovery"
    end
  end

  defp correlated?(claim, frames),
    do:
      Enum.any?(
        frames,
        &(&1["ordinal"] == claim["ordinal"] and &1["frame_id"] == claim["frame_id"])
      )

  defp contradictory?(log, evidence) do
    prior =
      Enum.filter(
        Map.get(log, "entries", []),
        &(&1["disposition"] not in ["held_uncorrelated", "held_contradictory"])
      )

    Enum.any?(evidence["frames"], &conflicts_with_prior?(&1, prior))
  end

  defp conflicts_with_prior?(claim, prior) do
    prior
    |> Enum.flat_map(& &1["frames"])
    |> Enum.any?(fn old ->
      old["ordinal"] == claim["ordinal"] and old["frame_id"] == claim["frame_id"] and
        incompatible?(old, claim)
    end)
  end

  defp incompatible?(old, claim) do
    definitive = ~w(not_sent rejected protocol_acknowledged)

    old["outcome"] in definitive and claim["outcome"] in definitive and
      Map.take(old, ~w(outcome acceptance_stage)) != Map.take(claim, ~w(outcome acceptance_stage))
  end

  defp result(target, entry) do
    %{
      preparation: TransportActionRequestRow.to_domain(target),
      evidence: entry,
      disposition: entry["disposition"],
      holds_preserved?: true,
      automatic_takeover_allowed?: false
    }
  end

  defp transaction(fun) do
    Repo.transaction(fun)
  rescue
    _ -> {:error, :prepared_send_reconciliation_unavailable}
  catch
    :exit, _ -> {:error, :prepared_send_reconciliation_unavailable}
  end
end
