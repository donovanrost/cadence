defmodule Cadence.GroundNetworks.ProviderEventIngestionSupervisor do
  @moduledoc "Single bounded worker lane for provider event polling and processing."

  use Supervisor

  alias Cadence.GroundNetworks.{ProviderEventPoller, ProviderEventProcessor}

  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    children = [
      {ProviderEventPoller, Keyword.get(opts, :poller, [])},
      {ProviderEventProcessor, Keyword.get(opts, :processor, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
