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
  @callback hot_path_safe?(keyword()) :: boolean()
  @callback record_samples([Sample.t()]) :: :ok | {:error, term()}
  @callback record_samples([Sample.t()], keyword()) :: :ok | {:error, term()}
  @callback replace_value(binary(), binary(), Sample.t() | nil, keyword()) ::
              :ok | {:error, term()}
  @callback replace_value(binary(), binary(), Sample.t() | nil, keyword(), keyword()) ::
              :ok | {:error, term()}
  @callback replace_values_for_scope(binary(), [Sample.t()], keyword()) ::
              :ok | {:error, term()}
  @callback replace_values_for_scope(binary(), [Sample.t()], keyword(), keyword()) ::
              :ok | {:error, term()}
  @callback latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  @callback latest_value(binary(), binary(), keyword(), keyword()) :: Sample.t() | nil
  @callback latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  @callback latest_values_for_mission(binary(), keyword(), keyword()) :: [Sample.t()]
  @callback reset() :: :ok
  @callback reset(binary()) :: :ok
  @callback reset(:all | binary(), keyword()) :: :ok

  @optional_callbacks hot_path_safe?: 1,
                      latest_value: 4,
                      latest_values_for_mission: 3,
                      record_samples: 2,
                      replace_value: 5,
                      replace_values_for_scope: 4,
                      reset: 2

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
  def record_samples(%{backend_opts: backend_opts} = policy, samples) when is_list(samples) do
    backend = backend(policy)

    if function_exported?(backend, :record_samples, 2) do
      backend.record_samples(samples, backend_opts)
    else
      backend.record_samples(samples)
    end
  end

  @spec replace_value(binary(), binary(), Sample.t() | nil, keyword()) :: :ok | {:error, term()}
  def replace_value(mission_id, point_id, sample_or_nil, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    replace_value(configured_policy(), mission_id, point_id, sample_or_nil, opts)
  end

  @spec replace_value(policy(), binary(), binary(), Sample.t() | nil, keyword()) ::
          :ok | {:error, term()}
  def replace_value(
        %{backend_opts: backend_opts} = policy,
        mission_id,
        point_id,
        sample_or_nil,
        opts
      )
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = backend(policy)

    if function_exported?(backend, :replace_value, 5) do
      backend.replace_value(mission_id, point_id, sample_or_nil, opts, backend_opts)
    else
      backend.replace_value(mission_id, point_id, sample_or_nil, operation_opts(policy, opts))
    end
  end

  @spec replace_values_for_scope(binary(), [Sample.t()], keyword()) :: :ok | {:error, term()}
  def replace_values_for_scope(mission_id, samples, opts \\ [])
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    replace_values_for_scope(configured_policy(), mission_id, samples, opts)
  end

  @spec replace_values_for_scope(policy(), binary(), [Sample.t()], keyword()) ::
          :ok | {:error, term()}
  def replace_values_for_scope(%{backend_opts: backend_opts} = policy, mission_id, samples, opts)
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    backend = backend(policy)

    if function_exported?(backend, :replace_values_for_scope, 4) do
      backend.replace_values_for_scope(mission_id, samples, opts, backend_opts)
    else
      backend.replace_values_for_scope(mission_id, samples, operation_opts(policy, opts))
    end
  end

  @spec hot_path_safe?() :: boolean()
  def hot_path_safe?, do: hot_path_safe?(configured_policy())

  @spec hot_path_safe?(policy()) :: boolean()
  def hot_path_safe?(%{backend_opts: backend_opts} = policy) do
    backend = backend(policy)

    cond do
      function_exported?(backend, :hot_path_safe?, 1) -> backend.hot_path_safe?(backend_opts)
      function_exported?(backend, :hot_path_safe?, 0) -> backend.hot_path_safe?()
      true -> false
    end
  end

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_value(configured_policy(), mission_id, point_id, opts)
  end

  @spec latest_value(policy(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(%{backend_opts: backend_opts} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = backend(policy)

    if function_exported?(backend, :latest_value, 4) do
      backend.latest_value(mission_id, point_id, opts, backend_opts)
    else
      backend.latest_value(mission_id, point_id, operation_opts(policy, opts))
    end
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
  def latest_values_for_mission(%{backend_opts: backend_opts} = policy, mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    backend = backend(policy)

    if function_exported?(backend, :latest_values_for_mission, 3) do
      backend.latest_values_for_mission(mission_id, opts, backend_opts)
    else
      backend.latest_values_for_mission(mission_id, operation_opts(policy, opts))
    end
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(_organization_id, mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    latest_values_for_mission(mission_id, opts)
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_policy())

  @spec reset(policy()) :: :ok
  def reset(%{backend_opts: backend_opts} = policy) do
    backend = backend(policy)

    cond do
      function_exported?(backend, :reset, 2) -> backend.reset(:all, backend_opts)
      function_exported?(backend, :reset, 0) -> backend.reset()
      true -> :ok
    end
  end

  @spec reset(binary()) :: :ok
  def reset(mission_id) when is_binary(mission_id) do
    reset(configured_policy(), mission_id)
  end

  @spec reset(policy(), binary()) :: :ok
  def reset(%{backend_opts: backend_opts} = policy, mission_id) when is_binary(mission_id) do
    backend = backend(policy)

    cond do
      function_exported?(backend, :reset, 2) -> backend.reset(mission_id, backend_opts)
      function_exported?(backend, :reset, 1) -> backend.reset(mission_id)
      true -> :ok
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
    |> Application.get_env(:telemetry_current_value_store, [])
    |> policy()
  end

  defp backend(%{backend: backend}), do: ensure_backend_loaded!(backend)

  defp operation_opts(%{backend_opts: backend_opts}, opts),
    do: Keyword.merge(backend_opts, opts)

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load telemetry current value store backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end
end
