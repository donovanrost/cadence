defmodule Cadence.IngressArchive do
  @moduledoc """
  Pluggable archive backend for raw ingress evidence.

  The default runtime backend is an object-store-shaped archive that batches
  raw evidence into segment files and stores lightweight query indexes in
  Postgres. Tests can use the Postgres compatibility backend to keep exact
  transactional behavior.
  """

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.{Batch, Receipt}
  alias Cadence.Replay.Scope

  @default_backend Cadence.IngressArchive.Postgres

  @type policy :: %{
          required(:backend) => module(),
          required(:backend_opts) => keyword()
        }

  @type stats :: %{
          queue_depth: non_neg_integer(),
          oldest_buffered_age_ms: non_neg_integer(),
          flush_count: non_neg_integer(),
          flush_failure_count: non_neg_integer(),
          last_flush_error: binary() | nil,
          flushed_count: non_neg_integer(),
          segment_count: non_neg_integer(),
          flush_total_us: non_neg_integer(),
          avg_flush_us: float(),
          flushed_bytes_total: non_neg_integer(),
          avg_segment_bytes: float()
        }

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback persist_raw_evidence_multi(Multi.t(), RawEvidence.t()) :: Multi.t()
  @callback persist_raw_evidence(RawEvidence.t()) :: :ok | {:error, term()}
  @callback persist_batch(Batch.t()) :: {:ok, Receipt.t()} | {:error, term()}
  @callback fetch_raw_evidences(binary(), Scope.t()) ::
              {:ok, [RawEvidence.t()]} | {:error, term()}
  @callback flush(binary() | nil) :: :ok | {:error, term()}
  @callback reset() :: :ok
  @callback stats(binary()) :: stats()
  @callback reset_stats(binary()) :: :ok

  @doc """
  Builds a child spec from the current application configuration.

  This compatibility arity reads application configuration when called. The
  supervised runtime uses `child_spec/1` with a policy captured at startup.
  """
  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec, do: child_spec(configured_policy())

  @spec child_spec(policy()) :: Supervisor.child_spec() | nil
  def child_spec(%{backend: backend, backend_opts: backend_opts}) do
    backend = ensure_backend_loaded!(backend)

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts)
    end
  end

  @spec persist_raw_evidence_multi(Multi.t(), RawEvidence.t()) :: Multi.t()
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{} = raw_evidence) do
    persist_raw_evidence_multi(configured_policy(), multi, raw_evidence)
  end

  @spec persist_raw_evidence_multi(policy(), Multi.t(), RawEvidence.t()) :: Multi.t()
  def persist_raw_evidence_multi(%{} = policy, %Multi{} = multi, %RawEvidence{} = raw_evidence),
    do: call_backend(policy, :persist_raw_evidence_multi, [multi, raw_evidence])

  @spec persist_raw_evidence(RawEvidence.t()) :: :ok | {:error, term()}
  def persist_raw_evidence(%RawEvidence{} = raw_evidence) do
    persist_raw_evidence(configured_policy(), raw_evidence)
  end

  @spec persist_raw_evidence(policy(), RawEvidence.t()) :: :ok | {:error, term()}
  def persist_raw_evidence(%{} = policy, %RawEvidence{} = raw_evidence),
    do: call_backend(policy, :persist_raw_evidence, [raw_evidence])

  @spec persist_batch(Batch.t()) :: {:ok, Receipt.t()} | {:error, term()}
  def persist_batch(%Batch{} = batch), do: persist_batch(configured_policy(), batch)

  @spec persist_batch(policy(), Batch.t()) :: {:ok, Receipt.t()} | {:error, term()}
  def persist_batch(%{} = policy, %Batch{} = batch) do
    with {:ok, %Receipt{} = receipt} <- call_backend(policy, :persist_batch, [batch]),
         true <- Receipt.valid_for_batch?(receipt, batch) do
      {:ok, receipt}
    else
      false -> {:error, :archive_receipt_does_not_match_batch}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_archive_receipt}
    end
  end

  @spec persist_raw_evidences([RawEvidence.t()]) :: :ok | {:error, term()}
  def persist_raw_evidences(raw_evidences) when is_list(raw_evidences),
    do: persist_raw_evidences(configured_policy(), raw_evidences)

  @spec persist_raw_evidences(policy(), [RawEvidence.t()]) :: :ok | {:error, term()}
  def persist_raw_evidences(%{} = policy, raw_evidences) when is_list(raw_evidences) do
    backend = backend(policy)

    cond do
      raw_evidences == [] ->
        :ok

      function_exported?(backend, :persist_raw_evidences, 1) ->
        call_backend(policy, :persist_raw_evidences, [raw_evidences])

      true ->
        persist_raw_evidence_batch(backend, raw_evidences)
    end
  end

  @spec fetch_raw_evidences(binary(), Scope.t()) :: {:ok, [RawEvidence.t()]} | {:error, term()}
  def fetch_raw_evidences(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_raw_evidences(configured_policy(), mission_id, scope)
  end

  @spec fetch_raw_evidences(policy(), binary(), Scope.t()) ::
          {:ok, [RawEvidence.t()]} | {:error, term()}
  def fetch_raw_evidences(%{} = policy, mission_id, %Scope{} = scope)
      when is_binary(mission_id),
      do: call_backend(policy, :fetch_raw_evidences, [mission_id, scope])

  @spec fetch_raw_evidence(binary(), binary()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def fetch_raw_evidence(mission_id, evidence_id)
      when is_binary(mission_id) and is_binary(evidence_id) do
    fetch_raw_evidence(configured_policy(), mission_id, evidence_id)
  end

  @spec fetch_raw_evidence(policy(), binary(), binary()) ::
          {:ok, RawEvidence.t()} | {:error, term()}
  def fetch_raw_evidence(%{} = policy, mission_id, evidence_id)
      when is_binary(mission_id) and is_binary(evidence_id) do
    case fetch_raw_evidences(policy, mission_id, Scope.new(%{evidence_ids: [evidence_id]})) do
      {:ok, [%RawEvidence{} = evidence]} -> {:ok, evidence}
      {:error, {:evidence_not_found, _ids}} -> {:error, :raw_evidence_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil), do: flush(configured_policy(), mission_id)

  @spec flush(policy(), binary() | nil) :: :ok | {:error, term()}
  def flush(%{} = policy, mission_id) do
    backend = backend(policy)

    if function_exported?(backend, :flush, 1) do
      call_backend(policy, :flush, [mission_id])
    else
      :ok
    end
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_policy())

  @spec reset(policy()) :: :ok
  def reset(%{} = policy) do
    backend = backend(policy)

    if function_exported?(backend, :reset, 0) do
      call_backend(policy, :reset, [])
    else
      :ok
    end
  end

  @spec stats(binary()) :: stats()
  def stats(mission_id) when is_binary(mission_id) do
    stats(configured_policy(), mission_id)
  end

  @spec stats(policy(), binary()) :: stats()
  def stats(%{} = policy, mission_id) when is_binary(mission_id) do
    backend = backend(policy)

    if function_exported?(backend, :stats, 1) do
      call_backend(policy, :stats, [mission_id])
    else
      empty_stats()
    end
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    reset_stats(configured_policy(), mission_id)
  end

  @spec reset_stats(policy(), binary()) :: :ok
  def reset_stats(%{} = policy, mission_id) when is_binary(mission_id) do
    backend = backend(policy)

    if function_exported?(backend, :reset_stats, 1) do
      call_backend(policy, :reset_stats, [mission_id])
    else
      :ok
    end
  end

  @doc false
  @spec policy(keyword() | map()) :: policy()
  def policy(config) when is_list(config) or is_map(config) do
    config = if is_map(config), do: Map.to_list(config), else: config

    %{
      backend: Keyword.get(config, :module, @default_backend),
      backend_opts: Keyword.delete(config, :module)
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    :cadence
    |> Application.get_env(:ingress_archive, [])
    |> policy()
  end

  defp backend(%{backend: backend}), do: ensure_backend_loaded!(backend)

  defp call_backend(%{backend_opts: backend_opts} = policy, function, args) do
    backend = backend(policy)

    if function_exported?(backend, function, length(args) + 1) do
      apply(backend, function, args ++ [backend_opts])
    else
      apply(backend, function, args)
    end
  end

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load ingress archive backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end

  defp empty_stats do
    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: 0,
      avg_segment_bytes: 0.0
    }
  end

  defp persist_raw_evidence_batch(backend, raw_evidences) do
    Enum.reduce_while(raw_evidences, :ok, fn
      %RawEvidence{} = raw_evidence, :ok ->
        case backend.persist_raw_evidence(raw_evidence) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _other, :ok ->
        {:halt, {:error, :invalid_raw_evidence_batch}}
    end)
  end
end
