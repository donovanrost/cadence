defmodule Cadence.Management.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # In-memory tables only: the password-check throttle and Policy's confirmed
    # (organization, mission) pairs. No Repo, control or data services.
    Supervisor.init([Cadence.Accounts.AttemptLimit, Cadence.Auth.MissionOrganizationCache],
      strategy: :one_for_one
    )
  end
end
