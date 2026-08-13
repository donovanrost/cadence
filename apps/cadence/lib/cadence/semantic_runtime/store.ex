defmodule Cadence.SemanticRuntime.Store do
  @moduledoc "Durable ordered-input log and deterministic recovery for semantic execution."

  import Ecto.Query

  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{CommitRow, Result, State, Update}

  @conflict_target [
    :organization_scope_id,
    :mission_id,
    :partition_id,
    :runtime_basis_sha256,
    :commit_id
  ]

  @spec commit(
          MissionRuntimeSpec.t(),
          PartitionKey.t(),
          [Update.t()],
          Result.t(),
          State.t()
        ) :: {:ok, Result.t(), State.t()} | {:error, term()}
  def commit(
        %MissionRuntimeSpec{} = spec,
        %PartitionKey{} = partition_key,
        updates,
        %Result{} = result,
        %State{} = state
      )
      when is_list(updates) do
    input = {:updates, updates}
    commit_input(spec, partition_key, input, result, state)
  end

  @spec commit_timer(
          MissionRuntimeSpec.t(),
          PartitionKey.t(),
          term(),
          binary(),
          DateTime.t(),
          binary(),
          Result.t(),
          State.t()
        ) :: {:ok, Result.t(), State.t()} | {:error, term()}
  def commit_timer(
        %MissionRuntimeSpec{} = spec,
        %PartitionKey{} = partition_key,
        scope,
        algorithm_id,
        %DateTime{} = at,
        timer_key,
        %Result{} = result,
        %State{} = state
      ) do
    input = {:timer, scope, algorithm_id, at, timer_key}
    commit_input(spec, partition_key, input, result, state)
  end

  defp commit_input(spec, partition_key, input, result, state) do
    commit_id = commit_id(spec, partition_key, input)

    attrs = %{
      commit_id: commit_id,
      organization_id: spec.organization_id,
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(partition_key),
      mission_model_revision_id: spec.mission_model_revision_id,
      runtime_basis_sha256: spec.runtime_basis_sha256,
      input_term: encode(input),
      result_term: encode(result),
      state_term: encode(state)
    }

    case Repo.insert(CommitRow.changeset(attrs),
           on_conflict: :nothing,
           conflict_target: @conflict_target,
           returning: true
         ) do
      {:ok, %CommitRow{commit_sequence: sequence}} when is_integer(sequence) ->
        {:ok, result, state}

      {:ok, %CommitRow{}} ->
        fetch_existing(spec, partition_key, commit_id, input)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec recover(MissionRuntimeSpec.t(), PartitionKey.t(), map()) ::
          {:ok, State.t()} | {:error, term()}
  def recover(%MissionRuntimeSpec{} = spec, %PartitionKey{} = partition_key, plan)
      when is_map(plan) do
    rows =
      CommitRow
      |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
      |> where([row], row.mission_id == ^spec.mission_id)
      |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
      |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
      |> order_by([row], asc: row.commit_sequence)
      |> Repo.all()

    Enum.reduce_while(rows, {:ok, %State{}}, fn row, {:ok, state} ->
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
    end)
  end

  @spec timer_cursors(MissionRuntimeSpec.t(), PartitionKey.t()) ::
          {:ok, %{binary() => DateTime.t()}} | {:error, term()}
  def timer_cursors(%MissionRuntimeSpec{} = spec, %PartitionKey{} = partition_key) do
    rows =
      CommitRow
      |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
      |> where([row], row.mission_id == ^spec.mission_id)
      |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
      |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
      |> order_by([row], asc: row.commit_sequence)
      |> Repo.all()

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
      CommitRow
      |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
      |> where([row], row.mission_id == ^spec.mission_id)
      |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
      |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
      |> where([row], is_nil(row.projected_at))
      |> order_by([row], asc: row.commit_sequence)
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
      CommitRow
      |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
      |> where([row], row.mission_id == ^spec.mission_id)
      |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
      |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
      |> where([row], is_nil(row.projected_at))
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

  defp fetch_existing(spec, partition_key, commit_id, input) do
    row =
      CommitRow
      |> where([row], row.organization_scope_id == ^organization_scope(spec.organization_id))
      |> where([row], row.mission_id == ^spec.mission_id)
      |> where([row], row.partition_id == ^PartitionKey.identifier(partition_key))
      |> where([row], row.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
      |> where([row], row.commit_id == ^commit_id)
      |> Repo.one()

    with %CommitRow{} <- row,
         {:ok, ^input} <- decode(row.input_term),
         {:ok, %Result{} = result} <- decode(row.result_term),
         {:ok, %State{} = state} <- decode(row.state_term) do
      {:ok, result, state}
    else
      nil -> {:error, :semantic_runtime_commit_not_found}
      _other -> {:error, :semantic_runtime_commit_conflict}
    end
  end

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
