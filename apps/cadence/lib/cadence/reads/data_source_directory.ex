defmodule Cadence.Reads.DataSourceDirectory do
  @moduledoc """
  D1, the console's data sources list (Setup rail 07): every source visible to
  the mission (platform-managed ones included), with its probed health, when
  data last arrived, and its credential state. Staleness comes from the
  server (U9): `stale` is `nil` when no source declares an expected interval
  to judge it by (`metadata.expected_interval_seconds`).
  """

  alias Cadence.DataSources.{AdapterRegistry, DataSource, SourceCredentialReference}
  alias Cadence.ExtensionCatalog
  alias Cadence.Projections.DataSources.{Health, Watermarks}
  alias Cadence.Reads.DataSources

  @doc "One source as `list/3` shows it, or `nil` when the mission can't see it."
  @spec fetch(binary(), binary(), binary()) :: map() | nil
  def fetch(organization_id, mission_id, data_source_id),
    do: organization_id |> list(mission_id) |> Enum.find(&(&1.id == data_source_id))

  @spec list(binary(), binary(), DateTime.t()) :: [map()]
  def list(organization_id, mission_id, now \\ DateTime.utc_now()) do
    health =
      organization_id
      |> Health.list_source_health_statuses(mission_id)
      |> Enum.group_by(& &1.data_source_id)

    received =
      organization_id
      |> Watermarks.list_source_watermark_statuses(mission_id)
      |> Enum.group_by(& &1.data_source_id, & &1.latest_receipt_time)
      |> Map.new(fn {id, times} -> {id, times |> Enum.reject(&is_nil/1) |> max_time()} end)

    organization_id
    |> DataSources.list_data_sources(mission_id)
    |> Enum.map(
      &row(&1, Map.get(health, &1.data_source_id, []), received[&1.data_source_id], now)
    )
    |> Enum.sort_by(&{&1.owner != :cadence, &1.display_name})
  end

  @doc "A data source's name as the console shows it (its display name, else a derived one)."
  @spec name(DataSource.t()) :: binary()
  def name(%DataSource{} = source) do
    metadata = unwrap(source.metadata)
    metadata["display_name"] || display_name(source, metadata)
  end

  defp row(%DataSource{} = source, health, last_received_at, now) do
    metadata = unwrap(source.metadata)
    interval = metadata["expected_interval_seconds"]

    %{
      id: source.data_source_id,
      display_name: name(source),
      kind: source.kind,
      owner: source.owner,
      status: source.status,
      # L11 (fe-setup): what the edit screens need.
      state: if(source.status == :active, do: :enabled, else: :disabled),
      shared: is_nil(source.organization_id),
      logical_source: logical_source(source, metadata),
      isolation_level: source.isolation_level,
      storage: metadata["storage"],
      credentials_ref: mask(source.credentials_ref),
      # L11 (qa, fe-setup): the backend operations this source takes; the page offers only these.
      tsdb_actions: tsdb_actions(source),
      health: health(health, source, now),
      last_received_at: last_received_at,
      expected_interval_s: if(is_integer(interval), do: interval),
      stale: stale(last_received_at, interval, now),
      credentials: credentials(source.credentials_ref)
    }
  end

  defp tsdb_actions(%DataSource{} = source) do
    case DataSource.tsdb_backend_lifecycle(source) do
      :ok -> ~w(provision reconcile deprovision)
      {:error, _reason} -> []
    end
  end

  # The worst current health across the source's logical sources; unknown once a probe is stale.
  defp health([], _source, _now), do: nil

  defp health(statuses, source, now) do
    classified = Enum.map(statuses, &Health.classify_status(&1, source, now: now))

    status =
      cond do
        Enum.any?(classified, &(&1.source_health in [:degraded, :unavailable])) ->
          :degraded

        Enum.all?(classified, &(&1.source_health == :healthy)) ->
          :healthy

        true ->
          :unknown
      end

    %{
      status: status,
      checked_at:
        classified |> Enum.map(& &1.last_seen_at) |> Enum.reject(&is_nil/1) |> max_time()
    }
  end

  defp stale(nil, _interval, _now), do: nil

  defp stale(received, interval, now) when is_integer(interval) and interval > 0,
    do: DateTime.diff(now, to_utc(received)) > interval

  defp stale(_received, _interval, _now), do: nil

  defp logical_source(source, metadata) do
    key =
      metadata["logical_source"] ||
        case AdapterRegistry.logical_source(source.adapter) do
          nil -> nil
          logical -> to_string(logical)
        end

    key && %{key: key, label: Map.get(adapter_labels(), key, humanize(key))}
  end

  @doc "Registrable logical sources: `%{key => label}`."
  def adapter_labels do
    Map.new(ExtensionCatalog.source_adapters(), &{to_string(&1.logical_source), &1.label})
  end

  # The reference only, with its middle elided (never material).
  defp mask(nil), do: nil
  defp mask(ref) when byte_size(ref) <= 12, do: ref

  defp mask(ref),
    do: String.slice(ref, 0, 8) <> "…" <> String.slice(ref, -4, 4)

  defp credentials(nil), do: nil

  defp credentials(ref) do
    case DataSources.fetch_credential_reference(ref) do
      {:ok, %SourceCredentialReference{} = reference} ->
        %{
          status: if(reference.status == :active, do: :valid, else: :expired),
          rotated_at: reference.last_rotated_at
        }

      _missing ->
        %{status: :none, rotated_at: nil}
    end
  end

  defp display_name(source, metadata) do
    storage = metadata["storage"]

    case {source.kind, storage} do
      {:managed_tsdb, "questdb"} -> "Telemetry store (QuestDB)"
      {:projection, _} -> source.data_source_id |> humanize() |> String.replace("Managed ", "")
      _other -> humanize(source.data_source_id)
    end
  end

  defp humanize(id), do: id |> String.replace("_", " ") |> String.capitalize()

  defp max_time([]), do: nil
  defp max_time(times), do: times |> Enum.map(&to_utc/1) |> Enum.max(DateTime)

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp unwrap(%{"value" => value}) when is_map(value), do: value
  defp unwrap(value) when is_map(value), do: value
  defp unwrap(_value), do: %{}
end
