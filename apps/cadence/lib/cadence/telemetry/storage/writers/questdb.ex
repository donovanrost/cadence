defmodule Cadence.Telemetry.Storage.Writers.QuestDB do
  @moduledoc """
  Canonical managed QuestDB telemetry history writer.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  alias Cadence.Telemetry.Storage.QuestDB.ObservationWriter

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, opts) when is_list(envelopes) and is_list(opts) do
    ObservationWriter.persist_envelopes(envelopes, opts)
  end
end
