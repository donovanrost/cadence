defmodule Cadence.Telemetry.HistoryStore do
  @moduledoc """
  Pluggable backend for telemetry sample history.
  """

  alias Cadence.Telemetry.Sample

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback persist_samples([Sample.t()]) :: :ok | {:error, term()}
  @callback sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  @callback reset() :: :ok

  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts())
    end
  end

  @spec persist_samples([Sample.t()]) :: :ok | {:error, term()}
  def persist_samples(samples) when is_list(samples) do
    backend_module().persist_samples(samples)
  end

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend_module().sample_history(mission_id, point_id, opts)
  end

  @spec sample_history(binary(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(_organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history(mission_id, point_id, opts)
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

  defp backend_module do
    Application.get_env(:cadence, :telemetry_history_store, [])
    |> Keyword.get(:module, Cadence.Telemetry.HistoryStore.Noop)
  end

  defp backend_opts do
    Application.get_env(:cadence, :telemetry_history_store, [])
  end

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load telemetry history store backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end
end
