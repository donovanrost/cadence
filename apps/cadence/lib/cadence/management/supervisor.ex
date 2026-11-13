defmodule Cadence.Management.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # The password-check throttle's table (Accounts.AttemptLimit).
    Supervisor.init([Cadence.Accounts.AttemptLimit], strategy: :one_for_one)
  end
end
