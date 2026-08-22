defmodule Cadence.Telemetry.Storage.Writers.PostgresReadModel do
  @moduledoc """
  Test/read-model telemetry writer backed by the existing Postgres sample table.

  QuestDB is the canonical managed history target. This writer keeps current
  Postgres-backed history reads and tests working until the QuestDB read source
  exists.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  alias Cadence.Telemetry.SampleRecords
  alias Cadence.Telemetry.Storage.ObservationEnvelope

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, _opts) when is_list(envelopes) do
    envelopes
    |> Enum.map(fn %ObservationEnvelope{} = envelope ->
      ObservationEnvelope.to_sample(envelope)
    end)
    |> SampleRecords.persist_samples()
  end
end
