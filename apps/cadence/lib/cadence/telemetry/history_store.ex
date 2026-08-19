defmodule Cadence.Telemetry.HistoryStore do
  @moduledoc """
  Pluggable backend for telemetry sample history.
  """

  alias Cadence.Telemetry.Sample

  @default_backend Cadence.Telemetry.HistoryStore.Noop

  @type policy :: %{
          required(:backend) => module(),
          required(:backend_opts) => keyword(),
          optional(:storage_policy) => Cadence.Telemetry.Storage.policy() | nil
        }

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback persist_samples([Sample.t()]) :: :ok | {:error, term()}
  @callback sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  @callback sample_history_result(binary(), binary(), keyword()) ::
              {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  @callback sample_watermark_result(binary(), binary(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback decimated_sample_history_result(binary(), binary(), keyword()) ::
              {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  @callback reset() :: :ok

  @optional_callbacks decimated_sample_history_result: 3,
                      sample_history_result: 3,
                      sample_watermark_result: 3

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
  Persists samples using the current application configuration.

  Prefer `persist_samples/2` when a caller owns a captured backend policy.
  """
  @spec persist_samples([Sample.t()]) :: :ok | {:error, term()}
  def persist_samples(samples) when is_list(samples),
    do: persist_samples(configured_policy(), samples)

  @spec persist_samples(policy(), [Sample.t()]) :: :ok | {:error, term()}
  def persist_samples(%{} = policy, samples) when is_list(samples) do
    backend = backend(policy)

    if function_exported?(backend, :persist_samples, 2) do
      backend.persist_samples(samples, backend_context(policy))
    else
      backend.persist_samples(samples)
    end
  end

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history(configured_policy(), mission_id, point_id, opts)
  end

  @spec sample_history(policy(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend(policy).sample_history(mission_id, point_id, operation_opts(policy, opts))
  end

  @spec sample_history(binary(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history(mission_id, point_id, Keyword.put_new(opts, :organization_id, organization_id))
  end

  @spec sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history_result(configured_policy(), mission_id, point_id, opts)
  end

  @spec sample_history_result(policy(), binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = backend(policy)
    opts = operation_opts(policy, opts)

    if function_exported?(backend, :sample_history_result, 3) do
      backend.sample_history_result(mission_id, point_id, opts)
    else
      {:ok, %{samples: backend.sample_history(mission_id, point_id, opts), diagnostics: %{}}}
    end
  end

  @spec sample_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history_result(
      mission_id,
      point_id,
      Keyword.put_new(opts, :organization_id, organization_id)
    )
  end

  @spec decimated_sample_history(binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    decimated_sample_history(configured_policy(), mission_id, point_id, opts)
  end

  @spec decimated_sample_history(policy(), binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_sample_history(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    case decimated_sample_history_result(policy, mission_id, point_id, opts) do
      {:ok, %{buckets: buckets}} -> {:ok, buckets}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec decimated_sample_history(binary(), binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    decimated_sample_history(
      mission_id,
      point_id,
      Keyword.put_new(opts, :organization_id, organization_id)
    )
  end

  @spec decimated_sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    decimated_sample_history_result(configured_policy(), mission_id, point_id, opts)
  end

  @spec decimated_sample_history_result(policy(), binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_sample_history_result(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = backend(policy)
    opts = operation_opts(policy, opts)

    if function_exported?(backend, :decimated_sample_history_result, 3) do
      normalize_decimated_history_result(
        backend.decimated_sample_history_result(mission_id, point_id, opts)
      )
    else
      {:error, {:unsupported_history_capability, backend, :decimated_sample_history_result}}
    end
  end

  @spec decimated_sample_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_sample_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    decimated_sample_history_result(
      mission_id,
      point_id,
      Keyword.put_new(opts, :organization_id, organization_id)
    )
  end

  @spec sample_watermark_result(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def sample_watermark_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_watermark_result(configured_policy(), mission_id, point_id, opts)
  end

  @spec sample_watermark_result(policy(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sample_watermark_result(%{} = policy, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = backend(policy)
    opts = operation_opts(policy, opts)

    if function_exported?(backend, :sample_watermark_result, 3) do
      backend.sample_watermark_result(mission_id, point_id, opts)
    else
      {:error, {:unsupported_history_capability, backend, :sample_watermark_result}}
    end
  end

  @spec sample_watermark_result(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sample_watermark_result(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_watermark_result(
      mission_id,
      point_id,
      Keyword.put_new(opts, :organization_id, organization_id)
    )
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_policy())

  @spec reset(policy()) :: :ok
  def reset(%{} = policy) do
    backend = backend(policy)

    if function_exported?(backend, :reset, 0) do
      backend.reset()
    else
      :ok
    end
  end

  @doc false
  @spec policy(keyword() | map(), keyword()) :: policy()
  def policy(config, opts \\ [])
      when (is_list(config) or is_map(config)) and is_list(opts) do
    config = if is_map(config), do: Map.to_list(config), else: config

    %{
      backend: Keyword.get(config, :module, @default_backend),
      backend_opts: Keyword.delete(config, :module),
      storage_policy: Keyword.get(opts, :storage_policy)
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    policy(
      Application.get_env(:cadence, :telemetry_history_store, []),
      storage_policy: Cadence.Telemetry.Storage.configured_policy()
    )
  end

  defp backend(%{backend: backend}), do: ensure_backend_loaded!(backend)

  defp operation_opts(%{backend_opts: backend_opts}, opts),
    do: Keyword.merge(backend_opts, opts)

  defp backend_context(%{backend_opts: backend_opts, storage_policy: storage_policy}) do
    Keyword.put(backend_opts, :storage_policy, storage_policy)
  end

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load telemetry history store backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end

  defp normalize_decimated_history_result({:ok, %{buckets: buckets, diagnostics: diagnostics}})
       when is_list(buckets) and is_map(diagnostics) do
    {:ok, %{buckets: buckets, diagnostics: diagnostics}}
  end

  defp normalize_decimated_history_result({:ok, buckets}) when is_list(buckets) do
    {:ok, %{buckets: buckets, diagnostics: %{}}}
  end

  defp normalize_decimated_history_result({:error, reason}), do: {:error, reason}

  defp normalize_decimated_history_result(other) do
    {:error, {:invalid_decimated_history_result, other}}
  end
end
