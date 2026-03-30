defmodule Cadence.Telemetry.CurrentValueStore do
  @moduledoc """
  Pluggable backend for live telemetry current values.
  """

  alias Cadence.Telemetry.Sample

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback hot_path_safe?() :: boolean()
  @callback record_samples([Sample.t()]) :: :ok | {:error, term()}
  @callback latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  @callback latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  @callback reset() :: :ok
  @callback reset(binary()) :: :ok

  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts())
    end
  end

  @spec record_samples([Sample.t()]) :: :ok | {:error, term()}
  def record_samples(samples) when is_list(samples) do
    backend_module().record_samples(samples)
  end

  @spec hot_path_safe?() :: boolean()
  def hot_path_safe? do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :hot_path_safe?, 0) do
      backend.hot_path_safe?()
    else
      false
    end
  end

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend_module().latest_value(mission_id, point_id, opts)
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(_organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_value(mission_id, point_id, opts)
  end

  @spec latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    backend_module().latest_values_for_mission(mission_id, opts)
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(_organization_id, mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    latest_values_for_mission(mission_id, opts)
  end

  @spec reset() :: :ok
  def reset do
    maybe_reset([])
  end

  @spec reset(binary()) :: :ok
  def reset(mission_id) when is_binary(mission_id) do
    maybe_reset([mission_id])
  end

  defp maybe_reset(args) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :reset, length(args)) do
      apply(backend, :reset, args)
    else
      :ok
    end
  end

  defp backend_module do
    Application.get_env(:cadence, :telemetry_current_value_store, [])
    |> Keyword.get(:module, Cadence.Telemetry.CurrentValueStore.ETS)
  end

  defp backend_opts do
    Application.get_env(:cadence, :telemetry_current_value_store, [])
  end

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load telemetry current value store backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end
end
