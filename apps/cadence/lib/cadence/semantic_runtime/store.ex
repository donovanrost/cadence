defmodule Cadence.SemanticRuntime.Store do
  @moduledoc """
  Ownership and snapshots for a partition's semantic runtime (DECISIONS #94/#96, #692).

  There is no per-batch log. A partition evaluates in memory (`Cadence.SemanticRuntime`) and
  snapshots its state about once a minute (`snapshot/5`); a recovering owner takes the partition
  (`recover/2`: a new ownership epoch, which fences the previous owner) and loads the last
  snapshot. What the snapshot does not cover is replayed from the ingress journal, from the
  per-stream offsets the snapshot holds; effect ids are derived from (stream, offset), so the
  replay repeats nothing (#476, #480). A partition that persists no journal (journal off) loses at
  most the memory since its last snapshot (about 60 s).

  **A superseded owner is fenced at its next snapshot, not at its next batch.** Taking the
  partition bumps the ownership epoch, but the previous owner only learns it when it next writes a
  snapshot (within one interval, 60 s, or when it goes idle), and then stops. Until then it keeps
  processing and writing effects. That is accepted: its snapshot write is fenced, so it can never
  overwrite the new owner's recovery point, and its effects (samples, alarm transitions, episodes,
  managed requests) are insert-or-get under the same replay-safe ids the new owner derives from
  the same (stream, offset), so nothing duplicates.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Repo
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey}
  alias Cadence.SemanticRuntime.{HeadRow, Snapshot, State, Writer}

  @doc """
  Takes the partition: a new ownership epoch (fencing the previous owner) and the last snapshot.
  `{:ok, state, writer, resume}`: the snapshot's state (an empty one when there is none, or it is
  unusable) and the journal offset per stream it includes.
  """
  @spec recover(MissionRuntimeSpec.t(), PartitionKey.t()) ::
          {:ok, State.t(), Writer.t(), map()} | {:error, term()}
  def recover(spec, partition_key) do
    with {:ok, writer} <- acquire(spec, partition_key) do
      {state, resume} = load_snapshot(spec, partition_key, writer)
      {:ok, state, writer, resume}
    end
  end

  @doc """
  Writes the partition's semantic snapshot: `state` and `resume` (journal stream id => the offset
  the state includes). Only the current owner may: a superseded owner gets
  `{:error, :semantic_runtime_fenced}` and writes nothing.
  """
  @spec snapshot(MissionRuntimeSpec.t(), PartitionKey.t(), Writer.t(), State.t(), map()) ::
          :ok | {:error, term()}
  def snapshot(spec, partition_key, %Writer{} = writer, %State{} = state, resume)
      when is_map(resume) do
    started = System.monotonic_time()

    outcome =
      Repo.transaction(fn ->
        head = lock_head(spec, partition_key)
        validate_writer!(head, spec, partition_key, writer)
        Snapshot.put(spec, partition_key, writer.epoch, state, resume)
      end)

    case outcome do
      {:ok, {:ok, bytes}} ->
        :telemetry.execute(
          [:cadence, :runtime, :partition, :snapshot_written],
          %{
            bytes: bytes,
            duration_ms:
              System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
          },
          %{mission_id: spec.mission_id, partition_id: PartitionKey.identifier(partition_key)}
        )

        :ok

      {:error, reason} ->
        emit(reason, spec, partition_key, writer)
        {:error, reason}
    end
  end

  defp load_snapshot(spec, partition_key, writer) do
    {outcome, state, resume} =
      case Snapshot.fetch(spec, partition_key) do
        {:ok, %State{} = state, resume} ->
          {:hit, state, resume}

        :missing ->
          {:missing, %State{}, %{}}

        {:invalid, reason} ->
          Logger.warning(
            "Semantic snapshot unusable (#{reason}); the partition starts empty and the next " <>
              "snapshot replaces it",
            mission_id: spec.mission_id,
            partition_id: PartitionKey.identifier(partition_key)
          )

          {:invalid, %State{}, %{}}
      end

    :telemetry.execute(
      [:cadence, :runtime, :partition, :snapshot_recovery],
      %{count: 1},
      %{
        mission_id: spec.mission_id,
        partition_id: PartitionKey.identifier(partition_key),
        outcome: outcome,
        ownership_epoch: writer.epoch
      }
    )

    {state, resume}
  end

  defp acquire(spec, partition_key) do
    result =
      Repo.transaction(fn ->
        Repo.insert!(
          struct!(HeadRow, %{
            organization_scope_id: organization_scope(spec.organization_id),
            mission_id: spec.mission_id,
            partition_id: PartitionKey.identifier(partition_key),
            runtime_basis_sha256: spec.runtime_basis_sha256,
            generation: spec.generation
          }),
          on_conflict: :nothing
        )

        head = lock_head(spec, partition_key)
        validate_generation!(head, spec)

        head =
          head
          |> Ecto.Changeset.change(
            ownership_epoch: head.ownership_epoch + 1,
            runtime_basis_sha256: spec.runtime_basis_sha256,
            generation: spec.generation
          )
          |> Repo.update!()

        %Writer{epoch: head.ownership_epoch, identity: writer_identity(spec, partition_key)}
      end)

    case result do
      {:ok, writer} ->
        emit(:acquired, spec, partition_key, writer)
        {:ok, writer}

      error ->
        error
    end
  end

  defp validate_generation!(head, spec) do
    cond do
      head.generation > spec.generation ->
        Repo.rollback(:semantic_runtime_stale_generation)

      head.generation == spec.generation and
          head.runtime_basis_sha256 != spec.runtime_basis_sha256 ->
        Repo.rollback(:semantic_runtime_generation_conflict)

      true ->
        :ok
    end
  end

  defp validate_writer!(nil, _spec, _key, _writer), do: Repo.rollback(:semantic_runtime_fenced)

  defp validate_writer!(head, spec, partition_key, writer) do
    if writer.identity != writer_identity(spec, partition_key) or
         head.ownership_epoch != writer.epoch or
         head.runtime_basis_sha256 != spec.runtime_basis_sha256 or
         head.generation != spec.generation do
      Repo.rollback(:semantic_runtime_fenced)
    else
      :ok
    end
  end

  defp writer_identity(spec, partition_key),
    do:
      {organization_scope(spec.organization_id), spec.mission_id,
       PartitionKey.identifier(partition_key), spec.runtime_basis_sha256, spec.generation}

  defp lock_head(spec, partition_key) do
    HeadRow
    |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
    |> where([row], row.mission_id == ^spec.mission_id)
    |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp emit(outcome, spec, partition_key, writer) do
    metadata = %{
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(partition_key),
      generation: spec.generation,
      outcome: outcome,
      ownership_epoch: writer.epoch
    }

    :telemetry.execute([:cadence, :runtime, :partition, :ownership], %{count: 1}, metadata)

    Logger.info(
      "Semantic runtime ownership #{inspect(outcome)} epoch=#{writer.epoch}",
      Map.to_list(metadata)
    )
  end

  defp organization_scope(nil), do: "__unscoped_organization__"
  defp organization_scope(organization_id), do: organization_id
end
