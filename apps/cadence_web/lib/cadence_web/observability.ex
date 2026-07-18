defmodule CadenceWeb.Observability do
  @moduledoc """
  Operational observability setup for the Cadence web application.
  """

  @spec setup_web_tracing() :: :ok
  def setup_web_tracing do
    :ok = OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
  end
end
