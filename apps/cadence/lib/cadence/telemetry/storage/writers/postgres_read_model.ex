defmodule Cadence.Telemetry.Storage.Writers.PostgresReadModel do
  @moduledoc """
  Test/read-model telemetry writer backed by the existing Postgres sample table.

  QuestDB is the canonical managed history target. This writer keeps current
  Postgres-backed history reads and tests working until the QuestDB read source
  exists.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  alias Cadence.Persistence.Schemas.TelemetrySampleRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage.ObservationEnvelope

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, _opts) when is_list(envelopes) do
    rows = sample_rows(envelopes)

    case rows do
      [] ->
        :ok

      [_ | _] ->
        case Repo.insert_all(TelemetrySampleRow, rows,
               conflict_target: :sample_id,
               on_conflict: :nothing
             ) do
          {count, _rows} when count <= length(rows) -> :ok
          {count, _rows} -> {:error, {:insert_all_count_mismatch, :telemetry_samples, count}}
        end
    end
  end

  defp sample_rows(envelopes) do
    inserted_at = DateTime.utc_now()

    Enum.map(envelopes, fn %ObservationEnvelope{} = envelope ->
      envelope
      |> ObservationEnvelope.to_sample()
      |> TelemetrySampleRow.insert_attrs(inserted_at)
    end)
  end
end
