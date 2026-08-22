defmodule Cadence.Architecture.DashboardBoundary do
  @moduledoc """
  Prevents dashboard query and evidence adapters from reaching through their
  public read/provider boundaries into operational owners or persistence.
  """

  @adapter_prefixes [
    "lib/cadence/dashboards/sources/",
    "lib/cadence/dashboards/source_registry/",
    "lib/cadence/dashboards/data_link_resolver/"
  ]

  @adapter_files [
    "lib/cadence/dashboards/source_registry.ex",
    "lib/cadence/dashboards/data_link_resolver.ex",
    "lib/cadence/dashboards/runtime_fact_consumer.ex"
  ]

  @forbidden_prefixes [
    "lib/cadence/management/",
    "lib/cadence/control/",
    "lib/cadence/comms/ground_station_store",
    "lib/cadence/comms/routing_rule_store",
    "lib/cadence/comms/transport_store",
    "lib/cadence/contacts/contact_store",
    "lib/cadence/telemetry/storage/backfill_lifecycle_events/",
    "lib/cadence/telemetry/storage/observation_identity_states/"
  ]

  @forbidden_files [
    "lib/cadence/commanding.ex",
    "lib/cadence/contacts.ex",
    "lib/cadence/operational_events.ex",
    "lib/cadence/repo.ex",
    "lib/cadence/source_endpoints.ex",
    "lib/cadence/spacecraft_store.ex",
    "lib/cadence/telemetry/storage.ex",
    "lib/cadence/telemetry/storage/backfill_lifecycle_event.ex",
    "lib/cadence/telemetry/storage/backfill_lifecycle_events.ex",
    "lib/cadence/telemetry/storage/observation_identity_states.ex"
  ]

  @type finding :: %{
          required(:kind) => :dashboard_io_boundary,
          required(:source) => String.t(),
          required(:sink) => String.t(),
          required(:label) => String.t(),
          required(:fingerprint) => String.t()
        }

  @spec findings_for_edge(String.t(), String.t(), term()) :: [finding()]
  def findings_for_edge(source, sink, label) do
    if adapter_source?(source) and forbidden_sink?(sink) do
      [
        %{
          kind: :dashboard_io_boundary,
          source: source,
          sink: sink,
          label: "#{label}; use Cadence.Reads or a configured provider boundary",
          fingerprint: Enum.join([:dashboard_io_boundary, source, sink], "|")
        }
      ]
    else
      []
    end
  end

  defp adapter_source?(source) do
    source in @adapter_files or Enum.any?(@adapter_prefixes, &String.starts_with?(source, &1))
  end

  defp forbidden_sink?(sink) do
    sink in @forbidden_files or Enum.any?(@forbidden_prefixes, &String.starts_with?(sink, &1))
  end
end
