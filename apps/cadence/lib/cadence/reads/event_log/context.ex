defmodule Cadence.Reads.EventLog.Context do
  @moduledoc """
  The names a Timeline page's sentences use (`Cadence.Reads.EventLog`): spacecraft always, and
  people, dashboards and stations only when the page's entries mention them.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Dashboards.DocumentStore
  alias Cadence.Reads.EventSentences

  # Names the sentences use: spacecraft always, people and dashboards only when the page has them.
  @spec load(binary(), binary(), list()) :: map()
  def load(organization_id, mission_id, entries) do
    users =
      entries
      |> Enum.map(&EventSentences.actor_id(&1.actor))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Map.new(fn id ->
        case Cadence.Accounts.fetch_user(id) do
          {:ok, user} -> {id, user.display_name || user.email}
          _missing -> {id, nil}
        end
      end)

    dashboards =
      if Enum.any?(entries, &String.starts_with?(to_string(&1.kind), "dashboard_")),
        do:
          organization_id
          |> DocumentStore.list_dashboard_summaries(mission_id)
          |> Map.new(&{&1.dashboard_id, &1.name}),
        else: %{}

    # ux U81 §2: a contact_scid_mismatch title names the pass's station by its code.
    stations =
      if Enum.any?(entries, &(to_string(&1.kind) == "contact_scid_mismatch")),
        do: StationRefs.index(organization_id, mission_id),
        else: %{}

    %{
      spacecraft: spacecraft_names(organization_id, mission_id),
      users: users,
      dashboards: dashboards,
      stations: stations
    }
  end

  defp spacecraft_names(organization_id, mission_id) do
    organization_id
    |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
    |> Map.new(&{&1.spacecraft_id, {&1.display_name, &1.scid}})
  end
end
