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
  alias Cadence.Replay.Scope

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
  @callback fetch_raw_evidences(binary(), Scope.t()) ::
              {:ok, [RawEvidence.t()]} | {:error, term()}
  @callback flush(binary() | nil) :: :ok | {:error, term()}
  @callback reset() :: :ok
  @callback stats(binary()) :: stats()
  @callback reset_stats(binary()) :: :ok

  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts())
    end
  end

  @spec persist_raw_evidence_multi(Multi.t(), RawEvidence.t()) :: Multi.t()
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{} = raw_evidence) do
    ensure_backend_loaded!(backend_module()).persist_raw_evidence_multi(multi, raw_evidence)
  end

  @spec persist_raw_evidence(RawEvidence.t()) :: :ok | {:error, term()}
  def persist_raw_evidence(%RawEvidence{} = raw_evidence) do
    ensure_backend_loaded!(backend_module()).persist_raw_evidence(raw_evidence)
  end

  @spec persist_raw_evidences([RawEvidence.t()]) :: :ok | {:error, term()}
  def persist_raw_evidences(raw_evidences) when is_list(raw_evidences) do
    backend = ensure_backend_loaded!(backend_module())

    cond do
      raw_evidences == [] ->
        :ok

      function_exported?(backend, :persist_raw_evidences, 1) ->
        backend.persist_raw_evidences(raw_evidences)

      true ->
        persist_raw_evidence_batch(backend, raw_evidences)
    end
  end

  @spec fetch_raw_evidences(binary(), Scope.t()) :: {:ok, [RawEvidence.t()]} | {:error, term()}
  def fetch_raw_evidences(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    ensure_backend_loaded!(backend_module()).fetch_raw_evidences(mission_id, scope)
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :flush, 1) do
      backend.flush(mission_id)
    else
      :ok
    end
  end

  @spec reset() :: :ok
  def reset do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :reset, 0) do
      backend.reset()
    else
      :ok
    end
  end

  @spec stats(binary()) :: stats()
  def stats(mission_id) when is_binary(mission_id) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :stats, 1) do
      backend.stats(mission_id)
    else
      empty_stats()
    end
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :reset_stats, 1) do
      backend.reset_stats(mission_id)
    else
      :ok
    end
  end

  defp backend_module do
    Application.get_env(:cadence, :ingress_archive, [])
    |> Keyword.get(:module, Cadence.IngressArchive.Postgres)
  end

  defp backend_opts do
    Application.get_env(:cadence, :ingress_archive, [])
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
