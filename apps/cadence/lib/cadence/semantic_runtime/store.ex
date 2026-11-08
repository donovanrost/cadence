defmodule Cadence.SemanticRuntime.Store do
  @moduledoc "Durable ordered-input log and deterministic recovery for semantic execution."

  import Ecto.Query

  require Logger

  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{Checkpoint, CommitRow, HeadRow, Result, State, Writer}

  @doc "Commits only if this ownership epoch still holds the exact recovered predecessor."
  def commit(
        spec,
        partition_key,
        %Writer{} = writer,
        updates,
        %Result{} = result,
        %State{} = state
      )
      when is_list(updates) do
    commit_input(spec, partition_key, writer, {:updates, updates}, result, state)
  end

  def commit_timer(
        spec,
        partition_key,
        %Writer{} = writer,
        {scope, algorithm_id, %DateTime{} = at, timer_key},
        %Result{} = result,
        %State{} = state
      ) do
    commit_input(
      spec,
      partition_key,
      writer,
      {:timer, scope, algorithm_id, at, timer_key},
      result,
      state
    )
  end

  @doc "Fences previous writers, restores a checkpoint, and verifies the remaining durable suffix."
  def recover_writer(spec, partition_key, plan) do
    with {:ok, {writer, checkpoint}} <- acquire(spec, partition_key),
         {:ok, state} <- recover_checkpoint(spec, partition_key, plan, writer, checkpoint) do
      {:ok, state, writer}
    end
  end

  defp recover_checkpoint(spec, key, plan, writer, checkpoint) do
    started = System.monotonic_time()

    outcome =
      Repo.transaction(
        fn ->
          {status, initial, sequence} = Checkpoint.restore(checkpoint, writer.commit_sequence)

          query =
            commits(spec, key)
            |> where([row], row.commit_sequence > ^sequence)
            |> where([row], row.commit_sequence <= ^writer.commit_sequence)
            |> order_by([row], asc: row.commit_sequence)

          case recover_rows_counted(query, plan, initial, true) do
            {:ok, state, count} -> {state, status, sequence, count}
            {:error, reason} -> Repo.rollback(reason)
          end
        end,
        timeout: :infinity
      )

    case outcome do
      {:ok, {state, status, sequence, count}} ->
        with :ok <- maybe_checkpoint_recovered_head(spec, key, writer, state, status, count) do
          emit_checkpoint_recovery(spec, key, writer, status, sequence, count, started)
          {:ok, state}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_checkpoint_recovery(spec, key, writer, status, sequence, count, started) do
    metadata = %{
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(key),
      outcome: status,
      checkpoint_sequence: sequence,
      commit_sequence: writer.commit_sequence
    }

    measurements = %{
      count: 1,
      replayed_commits: count,
      duration: System.monotonic_time() - started
    }

    :telemetry.execute([:cadence, :runtime, :partition, :checkpoint], measurements, metadata)

    Logger.info(
      "Semantic checkpoint recovery #{status} replayed_commits=#{count} " <>
        "duration_ms=#{System.convert_time_unit(measurements.duration, :native, :millisecond)}",
      Map.to_list(metadata)
    )
  end

  defp maybe_checkpoint_recovered_head(_spec, _key, _writer, _state, :hit, 0), do: :ok

  defp maybe_checkpoint_recovered_head(spec, key, writer, state, _status, _count) do
    # A new replica may claim ownership during replay. It publishes its own
    # checkpoint; the recovered stale writer remains subject to the normal fence.
    case checkpoint_recovered_head(spec, key, writer, state) do
      {:ok, :ok} ->
        :ok

      {:error, reason}
      when reason in [:semantic_runtime_fenced, :semantic_runtime_stale_predecessor] ->
        :ok

      error ->
        error
    end
  end

  defp checkpoint_recovered_head(_spec, _key, %{commit_sequence: 0}, _state), do: {:ok, :ok}

  defp checkpoint_recovered_head(spec, key, writer, state) do
    Repo.transaction(fn ->
      validate_writer!(lock_head(spec, key), spec, key, writer)

      row =
        commits(spec, key)
        |> where([row], row.commit_sequence == ^writer.commit_sequence)
        |> Repo.one!()

      # Anchor only the exact state that was restored/verified, never a newer head.
      case decode(row.state_term) do
        {:ok, ^state} -> Checkpoint.publish(row)
        _ -> Repo.rollback(:semantic_runtime_checkpoint_conflict)
      end
    end)
  end

  @doc "Evaluates and conditionally commits, recovering a missing suffix on ownership contention."
  def process(spec, key, writer, state, updates, plan) do
    evaluate(spec, key, writer, state, {:updates, updates}, plan, 2)
  end

  def timer(spec, key, writer, state, {scope, algorithm_id, at, timer_key}, plan) do
    evaluate(spec, key, writer, state, {:timer, scope, algorithm_id, at, timer_key}, plan, 2)
  end

  defp evaluate(spec, key, writer, state, input, plan, retries) do
    with {:ok, result, next_state} <- replay(input, state, plan) do
      spec
      |> commit_input(key, writer, input, result, next_state)
      |> maybe_retry(spec, key, writer, state, input, plan, retries)
    end
  end

  defp maybe_retry({:error, reason}, spec, key, writer, _state, input, plan, retries)
       when reason in [:semantic_runtime_fenced, :semantic_runtime_stale_predecessor] and
              retries > 0 do
    if writer.identity == writer_identity(spec, key) do
      # A warm standby may be far behind. Use the same captured checkpoint and
      # verified suffix as a new owner instead of replaying from its stale state.
      with {:ok, recovered, next_writer} <- recover_writer(spec, key, plan) do
        evaluate(spec, key, next_writer, recovered, input, plan, retries - 1)
      end
    else
      {:error, :semantic_runtime_fenced}
    end
  end

  defp maybe_retry(result, _spec, _key, _writer, _state, _input, _plan, _retries), do: result

  defp acquire(spec, partition_key) do
    result =
      Repo.transaction(fn ->
        identity = %{
          organization_scope_id: organization_scope(spec.organization_id),
          mission_id: spec.mission_id,
          partition_id: PartitionKey.identifier(partition_key)
        }

        Repo.insert!(
          struct!(
            HeadRow,
            Map.merge(identity, %{
              runtime_basis_sha256: spec.runtime_basis_sha256,
              generation: spec.generation
            })
          ),
          on_conflict: :nothing
        )

        head = lock_head(spec, partition_key)
        validate_generation!(head, spec)

        sequence =
          commits(spec, partition_key)
          |> select([row], max(row.commit_sequence))
          |> Repo.one() || 0

        head =
          head
          |> Ecto.Changeset.change(
            ownership_epoch: head.ownership_epoch + 1,
            commit_sequence: sequence,
            runtime_basis_sha256: spec.runtime_basis_sha256,
            generation: spec.generation
          )
          |> Repo.update!()

        writer = %Writer{
          epoch: head.ownership_epoch,
          commit_sequence: head.commit_sequence,
          identity: writer_identity(spec, partition_key)
        }

        # Capture the small reference under the same head lock. Loading it later
        # could see a checkpoint ahead of this writer and force a full replay.
        {writer, Checkpoint.fetch(spec, partition_key)}
      end)

    case result do
      {:ok, {writer, checkpoint}} ->
        emit(:acquired, spec, partition_key, writer)
        {:ok, {writer, checkpoint}}

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

  defp commit_input(spec, partition_key, writer, input, result, state) do
    commit_id = commit_id(spec, partition_key, input)

    outcome =
      Repo.transaction(fn ->
        head = lock_head(spec, partition_key)
        validate_writer!(head, spec, partition_key, writer)

        existing =
          commits(spec, partition_key) |> where([row], row.commit_id == ^commit_id) |> Repo.one()

        case existing do
          nil -> insert_commit(spec, partition_key, writer, commit_id, input, result, state)
          row -> existing_commit(row, head, spec, partition_key, input, writer)
        end
      end)

    case outcome do
      {:ok, response} ->
        response

      {:error, reason} ->
        emit(reason, spec, partition_key, writer)
        {:error, reason}
    end
  end

  defp validate_writer!(nil, _spec, _key, _writer), do: Repo.rollback(:semantic_runtime_fenced)

  defp validate_writer!(head, spec, partition_key, writer) do
    cond do
      writer.identity != writer_identity(spec, partition_key) or
        head.ownership_epoch != writer.epoch or
        head.runtime_basis_sha256 != spec.runtime_basis_sha256 or
          head.generation != spec.generation ->
        Repo.rollback(:semantic_runtime_fenced)

      head.commit_sequence != writer.commit_sequence ->
        Repo.rollback(:semantic_runtime_stale_predecessor)

      true ->
        :ok
    end
  end

  defp insert_commit(spec, partition_key, writer, commit_id, input, result, state) do
    attrs = %{
      commit_id: commit_id,
      organization_id: spec.organization_id,
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(partition_key),
      mission_model_revision_id: spec.mission_model_revision_id,
      runtime_basis_sha256: spec.runtime_basis_sha256,
      ownership_epoch: writer.epoch,
      predecessor_sequence: writer.commit_sequence,
      input_term: encode(input),
      result_term: encode(result),
      state_term: encode(state)
    }

    case Repo.insert(CommitRow.changeset(Map.merge(attrs, input_metadata(input)))) do
      {:ok, row} ->
        Checkpoint.publish(row)
        {:ok, result, state, %{writer | commit_sequence: row.commit_sequence}}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # A retried old input still returns its original result, but NEVER its historical state.
  # The current head and ownership remain unchanged, including for multi-scope timer retries.
  defp existing_commit(row, head, spec, partition_key, input, writer) do
    latest =
      commits(spec, partition_key)
      |> where([row], row.commit_sequence == ^head.commit_sequence)
      |> Repo.one!()

    with {:ok, ^input} <- decode(row.input_term),
         {:ok, %Result{} = result} <- decode(row.result_term),
         {:ok, %State{} = state} <- decode(latest.state_term) do
      {:ok, result, state, writer}
    else
      _other -> Repo.rollback(:semantic_runtime_commit_conflict)
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

  defp commits(spec, partition_key) do
    CommitRow
    |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
    |> where([row], row.mission_id == ^spec.mission_id)
    |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
    |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
  end

  defp emit(outcome, spec, partition_key, writer) do
    metadata = %{
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(partition_key),
      generation: spec.generation,
      outcome: outcome,
      ownership_epoch: writer.epoch,
      commit_sequence: writer.commit_sequence
    }

    :telemetry.execute([:cadence, :runtime, :partition, :ownership], %{count: 1}, metadata)

    Logger.info(
      "Semantic runtime ownership #{inspect(outcome)} epoch=#{writer.epoch} predecessor=#{writer.commit_sequence}",
      Map.to_list(metadata)
    )
  end

  @spec recover(MissionRuntimeSpec.t(), PartitionKey.t(), map()) ::
          {:ok, State.t()} | {:error, term()}
  @doc "Read-only full-history audit. Deliberately ignores checkpoints and verifies every result/state."
  def recover(%MissionRuntimeSpec{} = spec, %PartitionKey{} = partition_key, plan)
      when is_map(plan) do
    recover_to(spec, partition_key, plan, nil)
  end

  defp recover_to(spec, partition_key, plan, sequence) do
    query = commits(spec, partition_key) |> order_by([row], asc: row.commit_sequence)

    query =
      if is_nil(sequence), do: query, else: where(query, [row], row.commit_sequence <= ^sequence)

    # A long rehearsal can retain hundreds of megabytes of compressed states.
    # Keep one consistent ordered cursor without transferring the entire log at once.
    case Repo.transaction(fn -> recover_rows(query, plan) end, timeout: :infinity) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp recover_rows(query, plan, initial_state \\ %State{}) do
    case recover_rows_counted(query, plan, initial_state, false) do
      {:ok, state, _count} -> {:ok, state}
      error -> error
    end
  end

  defp recover_rows_counted(query, plan, initial_state, backfill?) do
    query
    |> Repo.stream(max_rows: 100)
    |> Enum.reduce_while({:ok, initial_state, 0}, fn row, {:ok, state, count} ->
      case replay_row(row, state, plan) do
        {:cont, {:ok, next}} ->
          backfill_input_metadata(row, backfill?)
          {:cont, {:ok, next, count + 1}}

        {:halt, error} ->
          {:halt, error}
      end
    end)
  end

  defp backfill_input_metadata(%{input_kind: nil} = row, true) do
    {:ok, input} = decode(row.input_term)

    from(c in CommitRow, where: c.commit_sequence == ^row.commit_sequence)
    |> Repo.update_all(set: Map.to_list(input_metadata(input)))
  end

  defp backfill_input_metadata(_row, _backfill?), do: :ok

  defp input_metadata({:updates, _}), do: %{input_kind: "updates"}

  defp input_metadata({:timer, _scope, _algorithm, at, key}),
    do: %{
      input_kind: "timer",
      timer_key: key,
      timer_at: DateTime.from_unix!(DateTime.to_unix(at, :microsecond), :microsecond)
    }

  defp replay_row(row, state, plan) do
    with {:ok, input} <- decode(row.input_term),
         {:ok, expected_result} <- decode(row.result_term),
         {:ok, expected_state} <- decode(row.state_term),
         {:ok, actual_result, actual_state} <- replay(input, state, plan),
         :ok <- verify_replay(row, expected_result, expected_state, actual_result, actual_state) do
      {:cont, {:ok, actual_state}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
      other -> {:halt, {:error, {:semantic_runtime_commit_invalid, row.commit_id, other}}}
    end
  end

  @spec timer_cursors(MissionRuntimeSpec.t(), PartitionKey.t()) ::
          {:ok, %{binary() => DateTime.t()}} | {:error, term()}
  def timer_cursors(%MissionRuntimeSpec{} = spec, %PartitionKey{} = partition_key) do
    # DISTINCT ON bounds the normal query to one row per timer. Older binaries
    # can still append NULL metadata during rollout; only that suffix is decoded.
    latest =
      commits(spec, partition_key)
      |> where([row], row.input_kind == "timer")
      |> distinct([row], row.timer_key)
      |> order_by([row], asc: row.timer_key, desc: row.commit_sequence)
      |> select([row], %{commit_sequence: row.commit_sequence, input_term: row.input_term})
      |> Repo.all()

    legacy =
      commits(spec, partition_key)
      |> where([row], is_nil(row.input_kind))
      |> select([row], %{commit_sequence: row.commit_sequence, input_term: row.input_term})
      |> Repo.all()

    rows = Enum.sort_by(latest ++ legacy, & &1.commit_sequence)

    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, cursors} ->
      case decode(row.input_term) do
        {:ok, {:timer, _scope, _algorithm_id, %DateTime{} = at, timer_key}} ->
          {:cont, {:ok, Map.put(cursors, timer_key, at)}}

        {:ok, _other} ->
          {:cont, {:ok, cursors}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @spec pending_timer_results(MissionRuntimeSpec.t(), PartitionKey.t()) ::
          {:ok, [%{at: DateTime.t(), timer_key: binary(), result: Result.t()}]}
          | {:error, term()}
  def pending_timer_results(%MissionRuntimeSpec{} = spec, %PartitionKey{} = partition_key) do
    rows =
      commits(spec, partition_key)
      |> where([row], row.input_kind == "timer" or is_nil(row.input_kind))
      |> where([row], is_nil(row.projected_at))
      |> order_by([row], asc: row.commit_sequence)
      |> select([row], %{input_term: row.input_term, result_term: row.result_term})
      |> Repo.all()

    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, groups} ->
      case merge_pending_timer_result(row, groups) do
        {:ok, next_groups} -> {:cont, {:ok, next_groups}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, groups} ->
        {:ok,
         groups
         |> Map.values()
         |> Enum.sort_by(&{DateTime.to_unix(&1.at, :microsecond), &1.timer_key})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp merge_pending_timer_result(row, groups) do
    with {:ok, input} <- decode(row.input_term),
         {:ok, result} <- decode(row.result_term) do
      merge_decoded_timer_result(input, result, groups)
    end
  end

  defp merge_decoded_timer_result(
         {:timer, _scope, _algorithm_id, %DateTime{} = at, timer_key},
         %Result{} = result,
         groups
       )
       when is_binary(timer_key) do
    key = {at, timer_key}
    group = Map.get(groups, key, %{at: at, timer_key: timer_key, result: %Result{}})

    {:ok, Map.put(groups, key, %{group | result: merge_results(group.result, result)})}
  end

  defp merge_decoded_timer_result(_input, _result, groups), do: {:ok, groups}

  @spec mark_timer_projected(
          MissionRuntimeSpec.t(),
          PartitionKey.t(),
          binary(),
          DateTime.t()
        ) :: :ok | {:error, term()}
  def mark_timer_projected(
        %MissionRuntimeSpec{} = spec,
        %PartitionKey{} = partition_key,
        timer_key,
        %DateTime{} = at
      )
      when is_binary(timer_key) do
    rows =
      commits(spec, partition_key)
      |> where([row], is_nil(row.projected_at))
      |> where(
        [row],
        (row.input_kind == "timer" and row.timer_key == ^timer_key and
           row.timer_at == ^at) or is_nil(row.input_kind)
      )
      |> select([row], %{commit_sequence: row.commit_sequence, input_term: row.input_term})
      |> Repo.all()

    with {:ok, sequences} <- timer_sequences(rows, timer_key, at) do
      case sequences do
        [] ->
          :ok

        sequences ->
          from(row in CommitRow, where: row.commit_sequence in ^sequences)
          |> Repo.update_all(set: [projected_at: DateTime.utc_now()])

          :ok
      end
    end
  end

  defp replay({:updates, updates}, state, plan),
    do: SemanticRuntime.process(state, updates, plan)

  defp replay({:timer, scope, algorithm_id, at, _timer_key}, state, plan),
    do: SemanticRuntime.timer(state, scope, algorithm_id, at, plan)

  defp replay(input, _state, _plan),
    do: {:error, {:semantic_runtime_commit_input_unsupported, input}}

  defp verify_replay(row, expected_result, expected_state, actual_result, actual_state) do
    if expected_result == actual_result and expected_state == actual_state do
      :ok
    else
      {:error, {:semantic_runtime_replay_diverged, row.commit_id}}
    end
  end

  defp timer_sequences(rows, timer_key, at) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, sequences} ->
      case decode(row.input_term) do
        {:ok, {:timer, _scope, _algorithm_id, ^at, ^timer_key}} ->
          {:cont, {:ok, [row.commit_sequence | sequences]}}

        {:ok, _other} ->
          {:cont, {:ok, sequences}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp merge_results(left, right) do
    %Result{
      parameter_updates: left.parameter_updates ++ right.parameter_updates,
      monitoring_results: left.monitoring_results ++ right.monitoring_results,
      alarm_transitions: left.alarm_transitions ++ right.alarm_transitions,
      diagnostics: left.diagnostics ++ right.diagnostics
    }
  end

  defp commit_id(spec, partition_key, input) do
    ContentHash.term_sha256({
      spec.runtime_basis_sha256,
      PartitionKey.identifier(partition_key),
      input
    })
  end

  defp encode(term), do: :erlang.term_to_binary(term, compressed: 6)

  defp decode(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :semantic_runtime_commit_decode_failed}
  end

  defp organization_scope(nil), do: "__unscoped_organization__"
  defp organization_scope(organization_id), do: organization_id
end
