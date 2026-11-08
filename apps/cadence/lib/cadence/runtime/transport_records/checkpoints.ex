defmodule Cadence.Runtime.TransportRecords.Checkpoints do
  @moduledoc false
  import Ecto.Query
  alias Cadence.{Ids, Repo}
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{ProtocolCheckpoint, TransportCapabilityRecord, TransportRecords}

  alias Cadence.Runtime.TransportRecords.{
    TransportActionRequestRow,
    TransportCapabilityRecordRow,
    TransportTimerEventRow
  }

  alias Ecto.Multi

  @kinds ~w(sends observations timers)

  def save(state, document) do
    transaction(fn ->
      resource = document["scope"]["resource_id"]
      lock(resource)
      chain = checkpoint_chain(resource)
      validate_chain!(chain)
      actual = references(state, resource)
      prior = covered(chain)
      unless subset?(prior, actual), do: Repo.rollback(:protocol_checkpoint_basis_changed)
      delta = Map.new(@kinds, &{&1, Map.drop(actual[&1], Map.keys(prior[&1]))})
      insert_checkpoint(state, document, List.last(chain), delta)
    end)
  end

  def add(multi, nil, _records, _actions, _timers), do: multi

  def add(multi, {state, document}, records, actions, timers) do
    ids = %{
      "sends" =>
        Enum.flat_map(actions, fn action ->
          if action.action_kind == :provider_request and
               is_binary(action.request_document[:preparation_id]),
             do: [action.request_document.preparation_id],
             else: []
        end),
      "observations" => Enum.map(records, & &1.transport_record_id),
      "timers" => Enum.map(timers, & &1.timer_event_id)
    }

    Multi.run(multi, :versioned_protocol_checkpoint, fn _repo, _changes ->
      transaction(fn -> append_checkpoint(state, document, ids) end)
    end)
  end

  # Normal commits fetch only the previous checkpoint and their own new evidence.
  # Full history verification is deliberately reserved for explicit export/recovery.
  defp append_checkpoint(state, document, ids) do
    resource = document["scope"]["resource_id"]
    lock(resource)

    previous =
      Repo.one(
        from(r in TransportCapabilityRecordRow,
          where:
            r.event_kind == "protocol_checkpoint" and
              fragment("? ->> 'resource_id' = ?", r.metadata, ^resource),
          order_by: [desc: fragment("(? ->> 'checkpoint_revision')::bigint", r.metadata)],
          limit: 1
        )
      )

    previous = if previous, do: TransportCapabilityRecordRow.to_domain(previous)

    if previous && not valid_document?(previous),
      do: Repo.rollback(:invalid_protocol_checkpoint_chain)

    delta = references(state, resource, if(previous, do: ids))
    insert_checkpoint(state, document, previous, delta)
  end

  defp insert_checkpoint(state, document, previous, delta) do
    resource = document["scope"]["resource_id"]

    validate_writer!(state, document, previous)
    id = Ids.new("protocol_checkpoint")
    revision = if previous, do: previous.state_snapshot["revision"] + 1, else: 1
    prior_basis = if previous, do: previous.state_snapshot["basis_sha256"]

    sealed =
      document
      |> Map.merge(%{
        "checkpoint_id" => id,
        "revision" => revision,
        "predecessor_id" => if(previous, do: previous.transport_record_id),
        "evidence" => delta,
        "basis_sha256" => ContentHash.term_sha256({prior_basis, delta})
      })
      |> ProtocolCheckpoint.seal()

    insert!(
      record(state, id, :protocol_checkpoint, sealed, %{
        "resource_id" => resource,
        "checkpoint_revision" => revision
      })
    )

    sealed
  end

  defp validate_writer!(state, document, previous) do
    resource = document["scope"]["resource_id"]

    if previous && previous.state_snapshot["origin"]["runtime_id"] != state.send_runtime_id,
      do: Repo.rollback(:protocol_state_restore_required)

    if previous && previous.state_snapshot["scope"] != document["scope"],
      do: Repo.rollback(:protocol_checkpoint_scope_mismatch)

    clear =
      if previous,
        do: TransportRecords.clear?(resource),
        else: TransportRecords.clear?(resource, state.send_runtime_id)

    case clear do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def load(state, id) do
    transaction(fn ->
      resource = state.session_handle.resource
      lock(resource)
      current_checkpoint!(state, id, resource)
    end)
  end

  def install(state, document, review) do
    transaction(fn ->
      lock(review.resource_id)
      current = current_checkpoint!(state, document["checkpoint_id"], review.resource_id)
      if current != document, do: Repo.rollback(:protocol_checkpoint_basis_changed)

      id =
        "protocol_restoration_" <>
          ContentHash.term_sha256(
            {state.send_runtime_id, document["checkpoint_id"], review.basis_sha256}
          )

      summary = %{
        "checkpoint_id" => document["checkpoint_id"],
        "checkpoint_sha256" => document["sha256"],
        "checkpoint_revision" => document["revision"],
        "basis_sha256" => document["basis_sha256"],
        "target_runtime_id" => state.send_runtime_id,
        "target_session_incarnation" => review.incarnation,
        "target_basis_sha256" => review.basis_sha256,
        "status" => "committed_pending_installation"
      }

      persist_installation!(state, id, summary, review.resource_id)
      Map.put(summary, "restoration_id", id)
    end)
  end

  defp persist_installation!(state, id, summary, resource) do
    case Repo.get(TransportCapabilityRecordRow, id) do
      nil ->
        insert!(record(state, id, :protocol_restored, summary, %{"resource_id" => resource}))

      row ->
        if TransportCapabilityRecordRow.to_domain(row).state_snapshot != summary,
          do: Repo.rollback(:protocol_restoration_conflict)
    end
  end

  defp current_checkpoint!(state, id, resource) do
    chain = checkpoint_chain(resource)
    validate_chain!(chain)

    selected =
      if id == :latest,
        do: List.last(chain),
        else: Enum.find(chain, &(&1.transport_record_id == id))

    unless selected && selected.mission_id == state.mission_id &&
             selected.realized_contact_id == state.realized_contact_id &&
             selected.path_id == state.path_id &&
             selected.capability_instance_id == state.capability_instance_id,
           do: Repo.rollback(:protocol_checkpoint_not_found)

    unless List.last(chain).transport_record_id == selected.transport_record_id,
      do: Repo.rollback(:stale_protocol_checkpoint)

    unless covered(chain) == references(state, resource),
      do: Repo.rollback(:protocol_checkpoint_basis_changed)

    selected.state_snapshot
  end

  defp checkpoint_chain(resource) do
    Repo.all(
      from(r in TransportCapabilityRecordRow,
        where:
          r.event_kind == "protocol_checkpoint" and
            fragment("? ->> 'resource_id' = ?", r.metadata, ^resource)
      )
    )
    |> Enum.map(&TransportCapabilityRecordRow.to_domain/1)
    |> Enum.sort_by(& &1.state_snapshot["revision"])
  end

  defp validate_chain!(chain) do
    Enum.reduce(chain, nil, fn row, previous ->
      unless valid_link?(row, previous), do: Repo.rollback(:invalid_protocol_checkpoint_chain)
      row
    end)
  end

  defp valid_link?(row, previous) do
    revision = if previous, do: previous.state_snapshot["revision"] + 1, else: 1
    predecessor = if previous, do: previous.transport_record_id
    basis = if previous, do: previous.state_snapshot["basis_sha256"]

    valid_document?(row) and row.state_snapshot["revision"] == revision and
      row.state_snapshot["predecessor_id"] == predecessor and compatible_scope?(row, previous) and
      row.state_snapshot["basis_sha256"] ==
        ContentHash.term_sha256({basis, row.state_snapshot["evidence"]})
  end

  defp valid_document?(row) do
    doc = row.state_snapshot

    ProtocolCheckpoint.valid_hash?(doc) and doc["schema_version"] == 1 and
      doc["checkpoint_id"] == row.transport_record_id and is_integer(doc["revision"]) and
      doc["revision"] > 0 and row.metadata["checkpoint_revision"] == doc["revision"] and
      row_scope?(row)
  end

  defp compatible_scope?(_row, nil), do: true

  defp compatible_scope?(row, previous),
    do: row.state_snapshot["scope"] == previous.state_snapshot["scope"]

  defp row_scope?(row) do
    scope = row.state_snapshot["scope"]

    scope["resource_id"] == row.metadata["resource_id"] and scope["mission_id"] == row.mission_id and
      scope["contact_id"] == row.realized_contact_id and scope["path_id"] == row.path_id and
      scope["binding_id"] == row.capability_instance_id
  end

  defp empty_refs, do: Map.new(@kinds, &{&1, %{}})

  defp covered(chain) do
    Enum.reduce(chain, empty_refs(), fn record, acc ->
      Map.new(@kinds, &{&1, merge_delta!(acc[&1], record.state_snapshot["evidence"][&1])})
    end)
  end

  defp merge_delta!(prior, delta) do
    unless is_map(delta) and
             MapSet.disjoint?(MapSet.new(Map.keys(prior)), MapSet.new(Map.keys(delta))),
           do: Repo.rollback(:invalid_protocol_checkpoint_chain)

    Map.merge(prior, delta)
  end

  defp subset?(prior, actual),
    do:
      Enum.all?(@kinds, fn kind ->
        Map.take(actual[kind], Map.keys(prior[kind])) == prior[kind]
      end)

  # No operational-review limit: each row is hashed once on recovery, and checked
  # against the immutable evidence intervals carried by the checkpoint chain.
  defp references(state, resource, ids \\ nil) do
    sends =
      from(r in TransportActionRequestRow,
        where:
          r.action_kind == "provider_send_prepared" and
            fragment("? ->> 'resource_id' = ?", r.metadata, ^resource)
      )

    observations =
      from(r in TransportCapabilityRecordRow,
        where:
          r.mission_id == ^state.mission_id and
            r.realized_contact_id == ^state.realized_contact_id and
            r.path_id == ^state.path_id and
            r.capability_instance_id == ^state.capability_instance_id and
            r.event_kind not in ["initialized", "protocol_checkpoint", "protocol_restored"]
      )

    timers =
      from(r in TransportTimerEventRow,
        where:
          r.mission_id == ^state.mission_id and
            r.realized_contact_id == ^state.realized_contact_id and
            r.path_id == ^state.path_id and
            r.capability_instance_id == ^state.capability_instance_id
      )

    %{
      "sends" =>
        rows(sends, ids, "sends", :action_request_id, fn r -> {r.request_document, r.metadata} end),
      "observations" =>
        rows(observations, ids, "observations", :transport_record_id, fn r ->
          {r.state_snapshot, r.metadata}
        end),
      "timers" =>
        rows(timers, ids, "timers", :timer_event_id, fn r ->
          {r.event_kind, r.due_at, r.metadata}
        end)
    }
  end

  defp rows(query, ids, kind, key, value) do
    query = if ids, do: where(query, [r], field(r, ^key) in ^ids[kind]), else: query

    result =
      Repo.all(query)
      |> Map.new(fn row -> {Map.fetch!(row, key), ContentHash.term_sha256(value.(row))} end)

    if ids && map_size(result) != length(Enum.uniq(ids[kind])),
      do: Repo.rollback(:incomplete_protocol_checkpoint_evidence)

    result
  end

  defp record(state, id, kind, document, metadata) do
    %TransportCapabilityRecord{
      transport_record_id: id,
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      capability_instance_id: state.capability_instance_id,
      family_key: state.family_key,
      activation_id: state.activation_id,
      binding_set_id: state.binding_set_id,
      binding_set_version: state.binding_set_version,
      partition_affinity: state.partition_key.affinity,
      partition_value: state.partition_key.value,
      event_kind: kind,
      state_snapshot: document,
      recorded_at: DateTime.utc_now(),
      emitted_record_kinds: [],
      emitted_record_count: 0,
      action_request_count: 0,
      metadata: metadata
    }
  end

  defp insert!(record) do
    case Repo.insert(TransportCapabilityRecordRow.changeset(record)) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Semantic transaction serialization; never placement or a renewable execution lease.
  defp lock(resource),
    do:
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "protocol-checkpoint:" <> resource
      ])

  defp transaction(fun) do
    Repo.transaction(fun)
  rescue
    _ -> {:error, :protocol_checkpoint_persistence_unavailable}
  catch
    :exit, _ -> {:error, :protocol_checkpoint_persistence_unavailable}
  end
end
