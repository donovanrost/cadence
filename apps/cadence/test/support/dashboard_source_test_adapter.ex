defmodule Cadence.Support.DashboardSourceTestAdapter do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataLinks,
    PlannedSourceRequest,
    ResolveWarning,
    SourceFacts,
    SourceResult
  }

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.DataSources.SourceProbe

  def capabilities do
    %SourceCapabilities{
      logical_source: :telemetry,
      supported_sampling: [:latest, :raw_series],
      supported_products: [:latest_value, :bounded_receipt_time_history],
      supported_time_axes: [:generation_time, :receipt_time],
      supported_value_types: [:engineering],
      supported_shapes: [:scalar, :wide],
      supports_watermarks?: false
    }
  end

  def probe(data_source, opts) do
    notify(opts, {:dashboard_source_test_adapter_probe, data_source.data_source_id})

    case Keyword.get(opts, :probe_mode, :ok) do
      :ok ->
        SourceProbe.healthy(:source_probe_succeeded, probe_metadata(opts), probe_kind: :adapter)

      :degraded ->
        SourceProbe.degraded(:source_query_failed, %{adapter: "test"}, probe_kind: :adapter)

      :unavailable ->
        SourceProbe.unavailable(:source_connection_failed, %{adapter: "test"},
          probe_kind: :adapter
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  def facts(_request, opts) do
    source_binding = Keyword.fetch!(opts, :source_binding)

    case Keyword.get(opts, :facts_mode, :ok) do
      :invalid ->
        {:ok, %SourceFacts{source_health: :offline, meta: "invalid"}}

      _mode ->
        {:ok,
         %SourceFacts{
           source_binding: source_binding.binding,
           data_source: source_binding.data_source,
           source_health: Keyword.get(opts, :source_health, :healthy)
         }}
    end
  end

  def resolve(%PlannedSourceRequest{} = request, opts) do
    track_concurrency(opts, fn ->
      notify(opts, {:dashboard_source_test_adapter_resolve, data_source_id(opts)})

      notify(
        opts,
        {:dashboard_source_test_adapter_request, data_source_id(opts), sampling_mode(request)}
      )

      maybe_sleep(request, opts)

      case Keyword.get(opts, :mode, :ok) do
        :invalid_result ->
          %SourceResult{
            request_id: "",
            frames: [:not_a_frame],
            meta: "invalid"
          }

        :error_result ->
          %SourceResult{
            request_id: request.request_id,
            warnings: [
              %ResolveWarning{
                code: :source_unavailable,
                severity: :error,
                scope: :dashboard,
                message: "Test source unavailable",
                details: %{
                  source_request_id: request.request_id,
                  data_source_id: data_source_id(opts)
                },
                links: DataLinks.request_observable_links(request, source: :warning)
              }
            ],
            meta: %{degraded?: true}
          }

        :raise ->
          raise "test source failure"

        :exit ->
          exit(:test_source_exit)

        _mode ->
          %SourceResult{
            request_id: request.request_id,
            meta: %{degraded?: false}
          }
      end
    end)
  end

  defp notify(opts, message) do
    case Keyword.get(opts, :test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _other -> :ok
    end
  end

  defp probe_metadata(opts) do
    %{adapter: "test"}
    |> maybe_put_adapter_reported_capabilities(opts)
  end

  defp maybe_put_adapter_reported_capabilities(metadata, opts) do
    case Keyword.get(opts, :adapter_reported_capabilities) do
      capabilities when is_map(capabilities) ->
        Map.put(metadata, :adapter_reported_capabilities, capabilities)

      _other ->
        metadata
    end
  end

  defp data_source_id(opts) do
    opts
    |> Keyword.fetch!(:source_binding)
    |> Map.fetch!(:data_source)
    |> Map.fetch!(:data_source_id)
  end

  defp maybe_sleep(%PlannedSourceRequest{} = request, opts) do
    sleep_ms =
      opts
      |> Keyword.get(:sleep_ms_by_sampling, %{})
      |> Map.get(sampling_mode(request), Keyword.get(opts, :sleep_ms, 0))

    if is_integer(sleep_ms) and sleep_ms > 0 do
      Process.sleep(sleep_ms)
    end
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    Map.get(sampling, :mode, Map.get(sampling, "mode"))
  end

  defp track_concurrency(opts, fun) do
    case Keyword.get(opts, :concurrency_agent) do
      agent when is_pid(agent) ->
        Agent.update(agent, fn %{current: current, max: max} ->
          current = current + 1
          %{current: current, max: max(max, current)}
        end)

        try do
          fun.()
        after
          Agent.update(agent, fn %{current: current, max: max} ->
            %{current: current - 1, max: max}
          end)
        end

      _other ->
        fun.()
    end
  end
end
