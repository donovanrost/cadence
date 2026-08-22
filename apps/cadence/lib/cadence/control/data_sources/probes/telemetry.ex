defmodule Cadence.Control.DataSources.Probes.Telemetry do
  @moduledoc false

  alias Cadence.Control.DataSources.Probes.QuestDB
  alias Cadence.DataSources.{DataSource, SourceProbe}

  @spec probe(DataSource.t(), keyword()) :: SourceProbe.t()
  def probe(%DataSource{} = data_source, opts \\ []) when is_list(opts) do
    case metadata_value(data_source.metadata, :storage) do
      storage when storage in [:questdb, "questdb"] ->
        case Keyword.fetch(opts, :data_source_probe_policy) do
          {:ok, policy} -> QuestDB.probe(data_source, opts, policy)
          :error -> QuestDB.probe(data_source, opts)
        end

      storage ->
        SourceProbe.unsupported(%{
          adapter: "telemetry",
          storage: storage || "unknown",
          reason: "telemetry sources only have a live probe for QuestDB-backed storage"
        })
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp metadata_value(_metadata, _key), do: nil
end
