defmodule Cadence.OTPClusterSpike.Membership do
  @moduledoc false
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]) do
    children = [
      %{id: :groups, start: {:pg, :start_link, [Cadence.OTPClusterSpike.Groups]}},
      Cadence.OTPClusterSpike.NodeAgent
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
