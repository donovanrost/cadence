defmodule Cadence.OutageTelemetryWriter do
  @moduledoc """
  A telemetry storage writer for tests (DECISIONS #71): stores through the Postgres read model,
  except while `outage/1` is on, when every write fails as an unreachable TSDB would.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  alias Cadence.Telemetry.Storage.Writers.PostgresReadModel

  @key {__MODULE__, :outage}

  @doc "Turns the outage on or off."
  def outage(on?) when is_boolean(on?), do: :persistent_term.put(@key, on?)

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, opts) do
    if :persistent_term.get(@key, false),
      do: {:error, {:telemetry_storage_unavailable, :econnrefused}},
      else: PostgresReadModel.persist_envelopes(envelopes, opts)
  end
end
