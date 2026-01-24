defmodule Cadence.Runtime.Links.Supervisor do
  @moduledoc """
  Dynamic supervisor for LinkController processes per SCID.
  """

  use DynamicSupervisor

  alias Cadence.Runtime.Links.LinkController

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @impl true
  def init(_mission_id) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec ensure_link(String.t(), non_neg_integer(), map()) :: :ok
  def ensure_link(mission_id, scid, protocol_config \\ %{}) do
    case lookup_link(mission_id, scid) do
      {:ok, _pid} ->
        :ok

      :error ->
        child_spec =
          {LinkController, mission_id: mission_id, scid: scid, protocol_config: protocol_config}

        case DynamicSupervisor.start_child(via_tuple(mission_id), child_spec) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :ok
        end
    end
  end

  @spec lookup_link(String.t(), non_neg_integer()) :: {:ok, pid()} | :error
  def lookup_link(mission_id, scid) do
    case Registry.lookup(Cadence.MissionRegistry, {:link_controller, mission_id, scid}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:links_supervisor, mission_id}}}
  end
end
