defmodule Cadence.Runtime.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Telemetry.{CurrentValueStore, Storage}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [Cadence.Telemetry.Profiler] ++
        ingress_archive_children() ++
        protocol_record_archive_children() ++
        telemetry_backend_children() ++
        [
          {Cadence.Runtime.CapabilityRegistry, []},
          {Registry, keys: :unique, name: Cadence.Runtime.Registry},
          {DynamicSupervisor, strategy: :one_for_one, name: Cadence.Runtime.MissionSupervisor}
        ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp telemetry_backend_children do
    [
      CurrentValueStore.child_spec(),
      Storage.child_spec()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp ingress_archive_children do
    [IngressArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end

  defp protocol_record_archive_children do
    [RecordArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end
end
