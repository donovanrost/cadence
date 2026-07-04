defmodule Cadence.Telemetry.HistoryStore do
  @moduledoc """
  Pluggable backend for telemetry sample history.
  """

  alias Cadence.Telemetry.Sample

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
  def sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    sample_history(mission_id, point_id, Keyword.put_new(opts, :organization_id, organization_id))
  end

  @spec sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    backend = ensure_backend_loaded!(backend_module())

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
    case decimated_sample_history_result(mission_id, point_id, opts) do
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
    backend = ensure_backend_loaded!(backend_module())

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
    backend = ensure_backend_loaded!(backend_module())

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
