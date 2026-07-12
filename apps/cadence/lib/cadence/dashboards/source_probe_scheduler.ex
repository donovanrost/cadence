defmodule Cadence.Dashboards.SourceProbeScheduler do
  @moduledoc """
  Periodically probes dashboard data sources whose physical source health is not fresh.
  """

  use GenServer

  alias Cadence.Dashboards.{DataSource, DataSources, SourceHealth, SourceProbePolicy}

  @default_interval_ms 60_000
  @default_max_concurrency 4
  @default_probe_timeout_ms 5_000

  @type summary :: %{
          checked: non_neg_integer(),
          probed: non_neg_integer(),
          skipped_fresh: non_neg_integer(),
          skipped_disabled: non_neg_integer(),
          skipped_policy: non_neg_integer(),
          skipped_unscoped: non_neg_integer(),
          skipped_source_health_disabled: non_neg_integer(),
          errors: [term()]
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec probe_now(GenServer.server()) :: summary()
  def probe_now(server \\ __MODULE__) do
    GenServer.call(server, :probe_now, :infinity)
  end

  @spec run_once(keyword()) :: summary()
  def run_once(opts \\ []) when is_list(opts) do
    if SourceHealth.enabled?(opts) do
      opts
      |> list_sources()
      |> Enum.reduce(initial_summary(), &classify_source(&1, &2, opts))
      |> probe_due_sources(opts)
    else
      initial_summary()
      |> Map.delete(:due_sources)
      |> Map.put(:skipped_source_health_disabled, 1)
    end
  end

  @impl true
  def init(opts) do
    state = %{
      opts: opts,
      interval_ms: positive_integer(Keyword.get(opts, :interval_ms), @default_interval_ms),
      timer_ref: nil
    }

    {:ok, schedule_probe(state)}
  end

  @impl true
  def handle_call(:probe_now, _from, state) do
    {:reply, run_once(state.opts), state}
  end

  @impl true
  def handle_info(:probe_due_sources, state) do
    _summary = run_once(state.opts)
    {:noreply, schedule_probe(state)}
  end

  defp list_sources(opts) do
    opts
    |> Keyword.get(:list_sources_fun, &DataSources.list_data_sources/2)
    |> then(fn list_sources_fun -> list_sources_fun.(nil, nil) end)
  end

  defp classify_source(%DataSource{} = source, summary, opts) do
    probe_policy = SourceProbePolicy.from_data_source(source)

    cond do
      not DataSource.active?(source) ->
        increment(summary, :skipped_disabled)

      is_nil(source.mission_id) ->
        increment(summary, :skipped_unscoped)

      not probe_policy.enabled? ->
        summary
        |> increment(:checked)
        |> increment(:skipped_policy)

      true ->
        source
        |> physical_source_status()
        |> SourceHealth.classify_status(
          source,
          SourceProbePolicy.source_health_opts(probe_policy, opts)
        )
        |> case do
          %{freshness: :fresh} ->
            summary
            |> increment(:checked)
            |> increment(:skipped_fresh)

          _classification ->
            summary
            |> increment(:checked)
            |> Map.update!(:due_sources, &[source | &1])
        end
    end
  end

  defp physical_source_status(%DataSource{} = source) do
    SourceHealth.list_source_health_statuses(source.organization_id, source.mission_id,
      data_source_id: source.data_source_id
    )
    |> Enum.filter(&physical_source_status?/1)
    |> Enum.sort_by(&status_seen_at/1, {:desc, DateTime})
    |> List.first()
  end

  defp physical_source_status?(status) do
    is_nil(status.source_binding_id) and is_nil(status.realm) and is_nil(status.dataset)
  end

  defp status_seen_at(status), do: status.last_seen_at || status.observed_at

  defp probe_due_sources(summary, opts) do
    due_sources = Map.fetch!(summary, :due_sources)

    due_sources = Enum.reverse(due_sources)

    results =
      due_sources
      |> Task.async_stream(&probe_source(&1, opts),
        max_concurrency:
          positive_integer(Keyword.get(opts, :max_concurrency), @default_max_concurrency),
        timeout:
          positive_integer(Keyword.get(opts, :probe_timeout_ms), @default_probe_timeout_ms),
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    due_sources
    |> Enum.zip(results)
    |> Enum.reduce(Map.delete(summary, :due_sources), fn {source, result}, summary ->
      merge_probe_result(source, result, summary, opts)
    end)
  end

  defp probe_source(%DataSource{} = source, opts) do
    probe_fun = Keyword.get(opts, :probe_fun, &DataSources.probe_data_source/3)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    probe_policy = SourceProbePolicy.from_data_source(source)

    attrs = %{
      mission_id: source.mission_id,
      observed_at: now
    }

    probe_opts =
      opts
      |> Keyword.put_new(:actor_id, "dashboard_source_probe_scheduler")
      |> Keyword.update(:payload, probe_payload(probe_policy), fn payload ->
        Map.merge(probe_payload(probe_policy), payload_map(payload))
      end)

    probe_fun.(source.data_source_id, attrs, probe_opts)
  end

  defp merge_probe_result(_source, {:ok, {:ok, _result, _status}}, summary, _opts),
    do: increment(summary, :probed)

  defp merge_probe_result(_source, {:ok, {:error, reason}}, summary, _opts) do
    summary
    |> increment(:probed)
    |> Map.update!(:errors, &[reason | &1])
  end

  defp merge_probe_result(source, {:exit, :timeout}, summary, opts) do
    source
    |> record_probe_timeout(opts)
    |> case do
      :ok ->
        Map.update!(summary, :errors, &[{:exit, :timeout} | &1])

      {:error, reason} ->
        Map.update!(summary, :errors, &[{:source_probe_timeout_record_failed, reason} | &1])
    end
  end

  defp merge_probe_result(_source, {:exit, reason}, summary, _opts) do
    Map.update!(summary, :errors, &[{:exit, reason} | &1])
  end

  defp record_probe_timeout(%DataSource{} = source, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    probe_policy = SourceProbePolicy.from_data_source(source)

    attrs = %{
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      logical_source: :unknown,
      data_source_id: source.data_source_id,
      source_health: :unavailable,
      reason: :source_probe_timeout,
      observed_at: now,
      payload: %{
        source: "dashboard_source_probe_scheduler",
        probe_kind: "scheduler",
        probe_message: "Source probe exceeded scheduler timeout.",
        probe_metadata: %{
          probe_policy_id: probe_policy.policy_id,
          probe_stale_after_ms: probe_policy.stale_after_ms,
          probe_timeout_ms:
            positive_integer(
              Keyword.get(opts, :probe_timeout_ms),
              @default_probe_timeout_ms
            )
        },
        connection_test_result: "blocked",
        connection_test_kind: "scheduler_timeout",
        connection_test_message: "Scheduled source probe timed out before completion."
      }
    }

    case SourceHealth.record_source_health(attrs, opts) do
      {:ok, :unchanged, _status} -> :ok
      {:ok, _event, _status} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_probe(state) do
    timer_ref = Process.send_after(self(), :probe_due_sources, state.interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp initial_summary do
    %{
      checked: 0,
      probed: 0,
      skipped_fresh: 0,
      skipped_disabled: 0,
      skipped_policy: 0,
      skipped_unscoped: 0,
      skipped_source_health_disabled: 0,
      errors: [],
      due_sources: []
    }
  end

  defp increment(summary, key), do: Map.update!(summary, key, &(&1 + 1))

  defp probe_payload(probe_policy) do
    %{
      source: "dashboard_source_probe_scheduler",
      probe_policy_id: probe_policy.policy_id,
      probe_stale_after_ms: probe_policy.stale_after_ms
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp payload_map(payload) when is_map(payload), do: payload
  defp payload_map(payload) when is_list(payload), do: Map.new(payload)
  defp payload_map(_payload), do: %{}

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
