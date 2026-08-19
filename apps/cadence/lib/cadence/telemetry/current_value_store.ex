defmodule Cadence.Telemetry.CurrentValueStore do
  @moduledoc """
  Pluggable backend for live telemetry current values.
  """

  alias Cadence.Telemetry.Sample

  @default_backend Cadence.Telemetry.CurrentValueStore.ETS

  @type policy :: %{
          required(:backend) => module(),
          required(:backend_opts) => keyword()
        }

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback hot_path_safe?() :: boolean()
  @callback record_samples([Sample.t()]) :: :ok | {:error, term()}
  @callback replace_value(binary(), binary(), Sample.t() | nil, keyword()) ::
              :ok | {:error, term()}
  @callback replace_values_for_scope(binary(), [Sample.t()], keyword()) ::
              :ok | {:error, term()}
  @callback latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  @callback latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  @callback reset() :: :ok
  @callback reset(binary()) :: :ok

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

  @doc """
  Records samples using the current application configuration.

  Prefer `record_samples/2` for internal workflows that already own a captured
  backend policy.
  """
  @spec record_samples([Sample.t()]) :: :ok | {:error, term()}
  def record_samples(samples) when is_list(samples),
    do: record_samples(configured_policy(), samples)

  @spec record_samples(policy(), [Sample.t()]) :: :ok | {:error, term()}
  def record_samples(%{} = policy, samples) when is_list(samples),
    do: backend(policy).record_samples(samples)

  @spec replace_value(binary(), binary(), Sample.t() | nil, keyword()) :: :ok | {:error, term()}
  def replace_value(mission_id, point_id, sample_or_nil, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    replace_value(configured_policy(), mission_id, point_id, sample_or_nil, opts)
  end

  @spec replace_value(policy(), binary(), binary(), Sample.t() | nil, keyword()) ::
          :ok | {:error, term()}
  def replace_value(%{} = policy, mission_id, point_id, sample_or_nil, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend(policy).replace_value(mission_id, point_id, sample_or_nil, opts)
  end

  @spec replace_values_for_scope(binary(), [Sample.t()], keyword()) :: :ok | {:error, term()}
  def replace_values_for_scope(mission_id, samples, opts \\ [])
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    replace_values_for_scope(configured_policy(), mission_id, samples, opts)
  end

  @spec replace_values_for_scope(policy(), binary(), [Sample.t()], keyword()) ::
          :ok | {:error, term()}
  def replace_values_for_scope(%{} = policy, mission_id, samples, opts)
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    backend(policy).replace_values_for_scope(mission_id, samples, opts)
  end

  @spec hot_path_safe?() :: boolean()
  def hot_path_safe?, do: hot_path_safe?(configured_policy())

  @spec hot_path_safe?(policy()) :: boolean()
  def hot_path_safe?(%{} = policy) do
    backend = backend(policy)

    if function_exported?(backend, :hot_path_safe?, 0) do
      backend.hot_path_safe?()
    else
      false
    end
  end

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_value(configured_policy(), mission_id, point_id, opts)
  end

  @spec latest_value(policy(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend(policy).latest_value(mission_id, point_id, opts)
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(_organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_value(mission_id, point_id, opts)
  end

  @spec latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    latest_values_for_mission(configured_policy(), mission_id, opts)
  end

  @spec latest_values_for_mission(policy(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(%{} = policy, mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    backend(policy).latest_values_for_mission(mission_id, opts)
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(_organization_id, mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    latest_values_for_mission(mission_id, opts)
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_policy())

  @spec reset(policy()) :: :ok
  def reset(%{} = policy), do: maybe_reset(policy, [])

  @spec reset(binary()) :: :ok
  def reset(mission_id) when is_binary(mission_id) do
    reset(configured_policy(), mission_id)
  end

  @spec reset(policy(), binary()) :: :ok
  def reset(%{} = policy, mission_id) when is_binary(mission_id) do
    maybe_reset(policy, [mission_id])
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
    |> Application.get_env(:telemetry_current_value_store, [])
    |> policy()
  end

  defp maybe_reset(policy, args) do
    backend = backend(policy)

    if function_exported?(backend, :reset, length(args)) do
      apply(backend, :reset, args)
    else
      :ok
    end
  end

  defp backend(%{backend: backend}), do: ensure_backend_loaded!(backend)

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load telemetry current value store backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end
end
