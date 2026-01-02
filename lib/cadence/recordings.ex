defmodule Cadence.Recordings do
  @moduledoc """
  Context for the event sourcing system.

  This module provides functions to create recordings with their recordables
  in atomic transactions, query recordings for timeline display, and
  derive aggregate state from recording history.

  ## Key Patterns

  1. **Atomic creation** - Recordable and Recording are created together
  2. **Batch loading** - Recordables are loaded by type to avoid N+1
  3. **Cursor pagination** - Using (timestamp, id) tuples
  4. **Protocol-based display** - Uniform access via Recordable protocol

  ## Example

      # Create a command dispatch recording
      Recordings.create(
        CommandDispatched,
        %{command_name: "SET_MODE", parameters: %{mode: 1}, target_id: target_id},
        %{
          organization_id: org_id,
          mission_id: mission_id,
          aggregate_id: Ecto.UUID.generate(),
          actor_id: user_id,
          timestamp: DateTime.utc_now()
        }
      )
  """

  import Ecto.Query
  alias Cadence.Recordings.{Recordable, Recording}
  alias Cadence.Repo
  alias Ecto.Multi

  # ============================================
  # RECORDABLE MODULE MAPPING
  # ============================================

  # Command recordables
  @recordable_modules %{
    "CommandDispatched" => Cadence.Recordings.Recordables.CommandDispatched,
    "CommandSent" => Cadence.Recordings.Recordables.CommandSent,
    "CommandVerified" => Cadence.Recordings.Recordables.CommandVerified,
    "CommandVerificationFailed" => Cadence.Recordings.Recordables.CommandVerificationFailed,
    "CommandRejected" => Cadence.Recordings.Recordables.CommandRejected,
    "CommandErrored" => Cadence.Recordings.Recordables.CommandErrored,
    # Alarm recordables
    "AlarmTriggered" => Cadence.Recordings.Recordables.AlarmTriggered,
    "AlarmAcknowledged" => Cadence.Recordings.Recordables.AlarmAcknowledged,
    "AlarmCleared" => Cadence.Recordings.Recordables.AlarmCleared,
    "AlarmShelved" => Cadence.Recordings.Recordables.AlarmShelved,
    "AlarmUnshelved" => Cadence.Recordings.Recordables.AlarmUnshelved,
    "AlarmEscalated" => Cadence.Recordings.Recordables.AlarmEscalated,
    "AlarmValueUpdated" => Cadence.Recordings.Recordables.AlarmValueUpdated,
    # Procedure execution recordables
    "ProcedureStarted" => Cadence.Recordings.Recordables.ProcedureStarted,
    "ProcedureStepCompleted" => Cadence.Recordings.Recordables.ProcedureStepCompleted,
    "ProcedureStepSkipped" => Cadence.Recordings.Recordables.ProcedureStepSkipped,
    "ProcedurePaused" => Cadence.Recordings.Recordables.ProcedurePaused,
    "ProcedureResumed" => Cadence.Recordings.Recordables.ProcedureResumed,
    "ProcedureCompleted" => Cadence.Recordings.Recordables.ProcedureCompleted,
    "ProcedureFailed" => Cadence.Recordings.Recordables.ProcedureFailed,
    "ProcedureCancelled" => Cadence.Recordings.Recordables.ProcedureCancelled,
    # Procedure version recordables
    "ProcedureVersionCreated" => Cadence.Recordings.Recordables.ProcedureVersionCreated,
    "ProcedureVersionSubmitted" => Cadence.Recordings.Recordables.ProcedureVersionSubmitted,
    "ProcedureVersionWithdrawn" => Cadence.Recordings.Recordables.ProcedureVersionWithdrawn,
    "ProcedureVersionApproved" => Cadence.Recordings.Recordables.ProcedureVersionApproved,
    "ProcedureVersionRejected" => Cadence.Recordings.Recordables.ProcedureVersionRejected,
    "ProcedureVersionDeprecated" => Cadence.Recordings.Recordables.ProcedureVersionDeprecated,
    # Automation recordables
    "AutomationTriggered" => Cadence.Recordings.Recordables.AutomationTriggered,
    "AutomationCompleted" => Cadence.Recordings.Recordables.AutomationCompleted,
    "AutomationFailed" => Cadence.Recordings.Recordables.AutomationFailed,
    "AutomationSkipped" => Cadence.Recordings.Recordables.AutomationSkipped,
    # Queue recordables
    "CommandQueued" => Cadence.Recordings.Recordables.CommandQueued,
    "CommandDequeued" => Cadence.Recordings.Recordables.CommandDequeued,
    # Procedure review workflow recordables
    "ProcedureReviewSubmitted" => Cadence.Recordings.Recordables.ProcedureReviewSubmitted,
    "ProcedureReviewRequested" => Cadence.Recordings.Recordables.ProcedureReviewRequested,
    "ProcedureReviewApproved" => Cadence.Recordings.Recordables.ProcedureReviewApproved,
    "ProcedureChangesRequested" => Cadence.Recordings.Recordables.ProcedureChangesRequested,
    "ProcedureReviewCommentAdded" => Cadence.Recordings.Recordables.ProcedureReviewCommentAdded,
    "ProcedureThreadResolved" => Cadence.Recordings.Recordables.ProcedureThreadResolved,
    "ProcedureVersionResubmitted" => Cadence.Recordings.Recordables.ProcedureVersionResubmitted,
    "ProcedureVersionClosed" => Cadence.Recordings.Recordables.ProcedureVersionClosed
  }

  @doc """
  Returns the module for a recordable type string.
  """
  def recordable_module(type) when is_binary(type) do
    Map.get(@recordable_modules, type)
  end

  @doc """
  Returns all known recordable type strings.
  """
  def recordable_types, do: Map.keys(@recordable_modules)

  # ============================================
  # CREATION
  # ============================================

  @doc """
  Creates a recording with its recordable in a single transaction.

  ## Parameters

  - `recordable_module` - The module for the recordable (e.g., CommandDispatched)
  - `recordable_attrs` - Attributes for the recordable
  - `recording_attrs` - Attributes for the recording (must include aggregate_id, etc.)

  ## Returns

  - `{:ok, %{recordable: recordable, recording: recording}}`
  - `{:error, failed_operation, changeset, changes_so_far}`
  """
  def create(recordable_module, recordable_attrs, recording_attrs) do
    Multi.new()
    |> Multi.insert(:recordable, fn _changes ->
      recordable_module.changeset(struct(recordable_module), recordable_attrs)
    end)
    |> Multi.insert(:recording, fn %{recordable: recordable} ->
      Recording.changeset(
        %Recording{},
        Map.merge(recording_attrs, %{
          recordable_type: Recordable.recording_type(recordable),
          recordable_id: recordable.id,
          aggregate_type: Recordable.aggregate_type(recordable)
        })
      )
    end)
    |> Repo.transaction()
  end

  @doc """
  Appends a recording creation to an existing Multi.

  Useful for creating multiple recordings in a single transaction.

  ## Parameters

  - `multi` - Existing Ecto.Multi
  - `name` - Atom name for this operation (creates :name_recordable and :name_recording)
  - `recordable_module` - The module for the recordable
  - `recordable_attrs` - Attributes for the recordable
  - `recording_attrs_fn` - Function that receives changes and returns recording attrs

  ## Example

      Multi.new()
      |> Recordings.append(:dispatch, CommandDispatched, dispatch_attrs, fn _ -> recording_attrs end)
      |> Recordings.append(:sent, CommandSent, sent_attrs, fn changes ->
        %{parent_id: changes.dispatch_recording.id, ...}
      end)
      |> Repo.transaction()
  """
  def append(multi, name, recordable_module, recordable_attrs, recording_attrs_fn)
      when is_function(recording_attrs_fn, 1) do
    recordable_key = :"#{name}_recordable"
    recording_key = :"#{name}_recording"

    multi
    |> Multi.insert(recordable_key, fn _changes ->
      recordable_module.changeset(struct(recordable_module), recordable_attrs)
    end)
    |> Multi.insert(recording_key, fn changes ->
      recordable = Map.get(changes, recordable_key)
      recording_attrs = recording_attrs_fn.(changes)

      Recording.changeset(
        %Recording{},
        Map.merge(recording_attrs, %{
          recordable_type: Recordable.recording_type(recordable),
          recordable_id: recordable.id,
          aggregate_type: Recordable.aggregate_type(recordable)
        })
      )
    end)
  end

  # ============================================
  # QUERIES - TIMELINE
  # ============================================

  @doc """
  Lists recordings for timeline display within a time range.

  ## Options

  - `:organization_id` - Filter by organization (required for tenant isolation)
  - `:path_prefix` - Filter by bucket path prefix (e.g., "org_abc.miss_def")
  - `:bucket_id` - Filter by specific bucket
  - `:aggregate_types` - List of aggregate types to include
  - `:limit` - Maximum records to return (default 100)
  """
  def list_recordings(start_time, end_time, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    path_prefix = Keyword.get(opts, :path_prefix)
    bucket_id = Keyword.get(opts, :bucket_id)
    aggregate_types = Keyword.get(opts, :aggregate_types)
    limit = Keyword.get(opts, :limit, 100)

    query =
      Recording
      |> where([r], r.timestamp >= ^start_time and r.timestamp <= ^end_time)
      |> order_by([r], desc: r.timestamp)
      |> limit(^limit)

    query =
      if organization_id,
        do: where(query, [r], r.organization_id == ^organization_id),
        else: query

    query =
      if path_prefix do
        query
        |> join(:inner, [r], b in Cadence.Buckets.Bucket, on: r.bucket_id == b.id)
        |> where([r, b], like(b.path, ^"#{path_prefix}%"))
      else
        query
      end

    query = if bucket_id, do: where(query, [r], r.bucket_id == ^bucket_id), else: query

    query =
      if aggregate_types,
        do: where(query, [r], r.aggregate_type in ^aggregate_types),
        else: query

    Repo.all(query)
  end

  @doc """
  Lists recordings before a cursor with cursor-based pagination.

  ## Cursor

  The cursor is a map with `:timestamp` and `:id` keys from the last
  recording in the previous page.

  ## Options

  - `:organization_id` - Filter by organization (required for tenant isolation)
  - `:path_prefix` - Filter by bucket path prefix
  - `:bucket_id` - Filter by specific bucket
  - `:aggregate_types` - List of aggregate types to include
  - `:limit` - Maximum records to return (default 50)
  """
  def list_recordings_before(cursor, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    path_prefix = Keyword.get(opts, :path_prefix)
    bucket_id = Keyword.get(opts, :bucket_id)
    aggregate_types = Keyword.get(opts, :aggregate_types)
    limit = Keyword.get(opts, :limit, 50)

    query =
      Recording
      |> order_by([r], desc: :timestamp, desc: :id)
      |> limit(^limit)
      |> apply_cursor_filter(cursor)
      |> apply_org_filter(organization_id)
      |> apply_path_prefix_filter(path_prefix)
      |> apply_bucket_filter(bucket_id)
      |> apply_aggregate_filter(aggregate_types)

    Repo.all(query)
  end

  defp apply_cursor_filter(query, %{timestamp: timestamp, id: id})
       when not is_nil(timestamp) and not is_nil(id) do
    where(
      query,
      [r],
      r.timestamp < ^timestamp or (r.timestamp == ^timestamp and r.id < ^id)
    )
  end

  defp apply_cursor_filter(query, %{timestamp: timestamp}) when not is_nil(timestamp) do
    where(query, [r], r.timestamp < ^timestamp)
  end

  defp apply_cursor_filter(query, _cursor), do: query

  defp apply_org_filter(query, nil), do: query

  defp apply_org_filter(query, organization_id),
    do: where(query, [r], r.organization_id == ^organization_id)

  defp apply_path_prefix_filter(query, nil), do: query

  defp apply_path_prefix_filter(query, path_prefix) do
    query
    |> join(:inner, [r], b in Cadence.Buckets.Bucket, on: r.bucket_id == b.id)
    |> where([r, b], like(b.path, ^"#{path_prefix}%"))
  end

  defp apply_bucket_filter(query, nil), do: query
  defp apply_bucket_filter(query, bucket_id), do: where(query, [r], r.bucket_id == ^bucket_id)

  defp apply_aggregate_filter(query, nil), do: query

  defp apply_aggregate_filter(query, aggregate_types),
    do: where(query, [r], r.aggregate_type in ^aggregate_types)

  @doc """
  Lists recordings with their recordables, batch loaded by type.

  Avoids N+1 queries by grouping recordables by type and loading each type
  in a single query.

  Returns a list of maps: `%{recording: Recording.t(), recordable: struct()}`
  """
  def list_recordings_with_recordables(cursor, opts \\ []) do
    recordings = list_recordings_before(cursor, opts)
    load_recordables_for_recordings(recordings)
  end

  @doc """
  Loads recordables for a list of recordings, batch by type.
  """
  def load_recordables_for_recordings(recordings) when is_list(recordings) do
    # Group by type
    by_type = Enum.group_by(recordings, & &1.recordable_type)

    # Batch load each type
    recordables =
      Enum.flat_map(by_type, fn {type, recs} ->
        ids = Enum.map(recs, & &1.recordable_id)

        case recordable_module(type) do
          nil ->
            []

          module ->
            module
            |> where([r], r.id in ^ids)
            |> Repo.all()
            |> Enum.map(&{&1.id, &1})
        end
      end)
      |> Map.new()

    # Attach to recordings
    Enum.map(recordings, fn r ->
      recordable = Map.get(recordables, r.recordable_id)

      %{
        recording: r,
        recordable: recordable,
        title: if(recordable, do: Recordable.title(recordable), else: r.recordable_type),
        status: if(recordable, do: Recordable.status(recordable), else: nil),
        severity: if(recordable, do: Recordable.severity(recordable), else: nil)
      }
    end)
  end

  # ============================================
  # QUERIES - AGGREGATE HISTORY
  # ============================================

  @doc """
  Gets all recordings for an aggregate (entity history).

  Used for replaying state or viewing full history of an entity.
  """
  def get_aggregate_history(aggregate_type, aggregate_id) do
    Recording
    |> where([r], r.aggregate_type == ^aggregate_type and r.aggregate_id == ^aggregate_id)
    |> order_by([r], asc: r.timestamp)
    |> Repo.all()
  end

  @doc """
  Gets the aggregate history with recordables loaded.
  """
  def get_aggregate_history_with_recordables(aggregate_type, aggregate_id) do
    aggregate_type
    |> get_aggregate_history(aggregate_id)
    |> load_recordables_for_recordings()
  end

  # ============================================
  # QUERIES - SINGLE RECORD
  # ============================================

  @doc """
  Gets a recording by ID scoped to an organization.

  Returns `nil` if not found or if the recording doesn't belong to the organization.
  """
  def get_recording(id, organization_id) do
    Recording
    |> where([r], r.id == ^id and r.organization_id == ^organization_id)
    |> Repo.one()
  end

  @doc """
  Gets a recording by ID scoped to an organization, raises if not found.
  """
  def get_recording!(id, organization_id) do
    Recording
    |> where([r], r.id == ^id and r.organization_id == ^organization_id)
    |> Repo.one!()
  end

  @doc """
  Gets a recording by ID without organization scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where organization context is verified elsewhere.
  """
  def get_recording_unscoped(id) do
    Repo.get(Recording, id)
  end

  @doc """
  Gets a recording by ID without organization scoping, raises if not found.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where organization context is verified elsewhere.
  """
  def get_recording_unscoped!(id) do
    Repo.get!(Recording, id)
  end

  @doc """
  Loads the recordable for a recording.
  """
  def load_recordable(%Recording{recordable_type: type, recordable_id: id}) do
    case recordable_module(type) do
      nil -> nil
      module -> Repo.get(module, id)
    end
  end

  # ============================================
  # QUERIES - BUCKET
  # ============================================

  @doc """
  Lists recordings for a bucket (e.g., a shift).
  """
  def list_bucket_recordings(bucket_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Recording
    |> where([r], r.bucket_id == ^bucket_id)
    |> order_by([r], desc: r.timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  # ============================================
  # QUERIES - CAUSALITY
  # ============================================

  @doc """
  Gets all recordings in a causality chain (same root_id).
  """
  def get_causality_chain(root_id) do
    Recording
    |> where([r], r.root_id == ^root_id)
    |> order_by([r], asc: r.timestamp)
    |> Repo.all()
  end

  @doc """
  Gets child recordings of a parent recording.
  """
  def get_children(parent_id) do
    Recording
    |> where([r], r.parent_id == ^parent_id)
    |> order_by([r], asc: r.timestamp)
    |> Repo.all()
  end

  @doc """
  Lists recordings for a specific aggregate type with optional filtering.

  ## Options

  - `:bucket_id` - Filter by bucket
  - `:aggregate_id` - Filter by aggregate ID (for history of a single entity)
  - `:limit` - Max entries to return (default: 50)
  """
  def list_aggregate_recordings(aggregate_type, _cursor, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    bucket_id = Keyword.get(opts, :bucket_id)
    aggregate_id = Keyword.get(opts, :aggregate_id)

    query =
      Recording
      |> where([r], r.aggregate_type == ^aggregate_type)
      |> order_by([r], asc: r.timestamp)
      |> limit(^limit)

    query =
      if bucket_id do
        where(query, [r], r.bucket_id == ^bucket_id)
      else
        query
      end

    query =
      if aggregate_id do
        where(query, [r], r.aggregate_id == ^aggregate_id)
      else
        query
      end

    Repo.all(query)
  end
end
