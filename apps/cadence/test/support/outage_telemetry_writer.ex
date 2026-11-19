defmodule Cadence.OutageTelemetryWriter do
  @moduledoc """
  A telemetry storage writer for tests (DECISIONS #71): stores through the Postgres read model,
  except while `outage/1` is on, when every write fails as an unreachable TSDB would.

  The runtime captures its storage policy when the application boots, so a test can't swap the
  writer through the application env afterwards. `delegate/1` switches where writes go instead:
  the `:questdb` suite (QuestDBCase) points it at the real QuestDB writer and restores it on exit.
  """

  @behaviour Cadence.Telemetry.Storage.Writer

  alias Cadence.Telemetry.Storage.Writers.PostgresReadModel

  @key {__MODULE__, :outage}
  @delegate_key {__MODULE__, :delegate}

  @doc "Turns the outage on or off."
  def outage(on?) when is_boolean(on?), do: :persistent_term.put(@key, on?)

  @doc "Sets the writer module that stores outside an outage (the Postgres read model by default)."
  def delegate(module) when is_atom(module), do: :persistent_term.put(@delegate_key, module)

  @doc "The writer module that stores outside an outage."
  def delegate, do: :persistent_term.get(@delegate_key, PostgresReadModel)

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_envelopes(envelopes, opts) do
    if :persistent_term.get(@key, false),
      do: {:error, {:telemetry_storage_unavailable, :econnrefused}},
      else: delegate().persist_envelopes(envelopes, opts)
  end
end
