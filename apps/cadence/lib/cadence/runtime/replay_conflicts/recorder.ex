defmodule Cadence.Runtime.ReplayConflicts.Recorder do
  @moduledoc """
  The writes of `Cadence.Runtime.ReplayConflicts` (#99 follow-up): open, bump and resolve a tripped
  unit's record, and the sampler's buffer readings. Internal to the runtime plane: only its
  stalled-unit callers (the ingress persistence projector, the journal consumer, the partition
  owner) and the sampler call it (lead, 11-17). Other planes read through `ReplayConflicts`.

  Each caller records after the failing transaction has returned, never from inside it, and a
  failed write is logged and never changes the caller's retry or stop: the next retry writes it.
  While open, a record is keyed on (mission, path, unit, effect): a later trip of the same effect
  bumps `conflict_count` and `last_conflict_at`, so a crash before the write still leaves exactly
  one open record.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Ids
  alias Cadence.Repo
  alias Cadence.Runtime.ReplayConflicts.Row

  @type path :: :storage | :processing | :timer
  @type unit :: %{
          required(:mission_id) => binary(),
          required(:path) => path(),
          required(:unit_key) => binary(),
          optional(:partition_id) => binary() | nil,
          optional(:realized_contact_id) => binary() | nil,
          optional(:path_id) => binary() | nil,
          optional(:provider_binding_id) => binary() | nil,
          optional(:stream_key) => binary() | nil,
          optional(:partition_stopped) => boolean(),
          optional(:stopped_while) => binary() | nil
        }
  @type tracking :: :unknown | :clear | :open

  @open_target {:unsafe_fragment,
                "(mission_id, path, unit_key, effect_id) WHERE resolved_at IS NULL"}
  @search_depth 8

  @doc """
  A journal stream's unit (`:storage` or `:processing`): one stream per (contact, path, provider
  binding). Both paths of one stream share its `stream_key`, so devops counts its room once.
  """
  @spec stream_unit(:storage | :processing, binary(), binary(), binary(), binary()) :: unit()
  def stream_unit(path, mission_id, realized_contact_id, path_id, provider_binding_id) do
    stream_key = Enum.join([realized_contact_id, path_id, provider_binding_id], ":")

    %{
      mission_id: mission_id,
      path: path,
      unit_key: "stream:" <> stream_key,
      stream_key: stream_key,
      realized_contact_id: realized_contact_id,
      path_id: path_id,
      provider_binding_id: provider_binding_id
    }
  end

  @doc """
  A partition's unit (`:timer`). `stopped_while` when its owner stopped and stays down until its
  next start: `"starting"` (its start hit the conflict) or `"applying"` (an activation reconcile).
  """
  @spec partition_unit(binary(), binary(), binary() | nil) :: unit()
  def partition_unit(mission_id, partition_id, stopped_while \\ nil) do
    %{
      mission_id: mission_id,
      path: :timer,
      unit_key: "partition:" <> partition_id,
      partition_id: partition_id,
      partition_stopped: not is_nil(stopped_while),
      stopped_while: stopped_while
    }
  end

  @doc """
  The `{kind, id}` of a replay-id conflict anywhere in `reason` (callers wrap it differently), or
  nil.
  """
  @spec conflict(term()) :: {atom(), binary()} | nil
  def conflict(reason), do: find(reason, @search_depth)

  defp find({:replay_id_conflict, kind, id}, _depth) when is_atom(kind) and is_binary(id),
    do: {kind, id}

  defp find(_term, 0), do: nil

  defp find(term, depth) when is_tuple(term),
    do: term |> Tuple.to_list() |> find_first(depth - 1)

  defp find(term, depth) when is_list(term), do: find_first(term, depth - 1)

  defp find(%{} = term, depth) when not is_struct(term),
    do: term |> Map.values() |> find_first(depth - 1)

  defp find(_term, _depth), do: nil

  defp find_first(terms, depth) do
    Enum.find_value(terms, fn
      term when is_tuple(term) or is_list(term) or is_map(term) -> find(term, depth)
      _scalar -> nil
    end)
  end

  @doc """
  After a unit's write returned `result`: on a replay-id conflict, record it (`:open`); on success,
  resolve the unit's open records when there may be any (`:unknown` after a start, or `:open`),
  else nothing (`:clear`). Any other error leaves `tracking` as it was. Never raises.
  """
  @spec track(term(), unit(), tracking()) :: tracking()
  def track(result, unit, tracking) do
    case outcome(result) do
      {:conflict, kind, id} ->
        _ = record(unit, kind, id)
        :open

      # A failed resolve keeps `tracking`, so the next success tries again.
      :ok when tracking in [:unknown, :open] ->
        if resolve(unit) == :ok, do: :clear, else: tracking

      :ok ->
        :clear

      :other_error ->
        tracking
    end
  end

  defp outcome(:ok), do: :ok
  defp outcome({:ok, _value}), do: :ok
  defp outcome({:noreply, _state}), do: :ok

  defp outcome(error) do
    case conflict(error) do
      {kind, id} -> {:conflict, kind, id}
      nil -> :other_error
    end
  end

  @doc "Open (or bump) the unit's record of `effect_id`. `:error` (logged) if the write fails."
  @spec record(unit(), atom(), binary(), DateTime.t()) :: :ok | :error
  def record(unit, kind, effect_id, now \\ DateTime.utc_now()) do
    attrs = %{
      id: Ids.new("replay_id_conflict"),
      mission_id: unit.mission_id,
      path: Atom.to_string(unit.path),
      unit_key: unit.unit_key,
      effect_kind: Atom.to_string(kind),
      effect_id: effect_id,
      partition_id: Map.get(unit, :partition_id),
      realized_contact_id: Map.get(unit, :realized_contact_id),
      path_id: Map.get(unit, :path_id),
      provider_binding_id: Map.get(unit, :provider_binding_id),
      stream_key: Map.get(unit, :stream_key),
      partition_stopped: Map.get(unit, :partition_stopped, false),
      stopped_while: Map.get(unit, :stopped_while),
      first_seen_at: now,
      last_conflict_at: now,
      conflict_count: 1,
      inserted_at: now,
      updated_at: now
    }

    bump =
      from(row in Row,
        update: [
          inc: [conflict_count: 1],
          set: [
            last_conflict_at: ^now,
            updated_at: ^now,
            partition_stopped: fragment("EXCLUDED.partition_stopped OR ?", row.partition_stopped),
            stopped_while: fragment("COALESCE(EXCLUDED.stopped_while, ?)", row.stopped_while)
          ]
        ]
      )

    guarded(:record, unit, fn ->
      Repo.insert_all(Row, [attrs], on_conflict: bump, conflict_target: @open_target)
      :telemetry.execute([:cadence, :replay_id, :conflict], %{count: 1}, metadata(unit, kind))
    end)
  end

  @doc "Resolve the unit's open records: it committed past them. `:error` (logged) on failure."
  @spec resolve(unit(), DateTime.t()) :: :ok | :error
  def resolve(unit, now \\ DateTime.utc_now()) do
    guarded(:resolve, unit, fn -> unit |> open_query() |> resolve_all(now) end)
  end

  @doc """
  Resolve only the partition's records about stopping (`partition_stopped`): a start that
  succeeds got past them. Its timer-trip records wait for the stable time (domain R-a).
  """
  @spec resolve_stopped(unit(), DateTime.t()) :: :ok | :error
  def resolve_stopped(unit, now \\ DateTime.utc_now()) do
    guarded(:resolve, unit, fn ->
      unit |> open_query() |> where([row], row.partition_stopped) |> resolve_all(now)
    end)
  end

  defp open_query(unit) do
    Row
    |> where([row], row.mission_id == ^unit.mission_id)
    |> where([row], row.path == ^Atom.to_string(unit.path))
    |> where([row], row.unit_key == ^unit.unit_key and is_nil(row.resolved_at))
  end

  defp resolve_all(query, now),
    do: Repo.update_all(query, set: [resolved_at: now, updated_at: now])

  # The record must never change the caller's behaviour (lead, 11-17): log, and the next retry
  # writes it again.
  defp guarded(operation, unit, fun) do
    _ = fun.()
    :ok
  rescue
    # Only a test process without a sandbox connection (no DB in that test) sees this.
    DBConnection.OwnershipError -> :error
    error -> write_failed(operation, unit, Exception.message(error))
  catch
    :exit, reason -> write_failed(operation, unit, inspect(reason))
  end

  defp write_failed(operation, unit, message) do
    Logger.warning(
      "MM_REPLAY_ID_CONFLICT record #{operation} failed for #{unit.unit_key} " <>
        "(mission #{unit.mission_id}): #{message}; the next retry writes it"
    )

    :error
  end

  defp metadata(unit, kind),
    do: %{kind: kind, path: unit.path, mission_id: unit.mission_id}

  @doc "Every open record (the sampler)."
  @spec all_open() :: [Row.t()]
  def all_open do
    Row
    |> where([row], is_nil(row.resolved_at))
    |> Repo.all()
  end

  @doc "The sampler's buffer reading for one open record."
  @spec put_buffer(binary(), map()) :: :ok
  def put_buffer(id, attrs) when is_binary(id) and is_map(attrs) do
    Row
    |> where([row], row.id == ^id and is_nil(row.resolved_at))
    |> Repo.update_all(set: Map.to_list(attrs))

    :ok
  end
end
