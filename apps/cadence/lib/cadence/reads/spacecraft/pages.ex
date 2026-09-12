defmodule Cadence.Reads.Spacecraft.Pages do
  @moduledoc "Authorized host reads for core spacecraft features, independent of frontend delivery."

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  alias Cadence.Reads.Spacecraft.{
    Directory,
    IdentityForm,
    Overview,
    ProfileForm,
    Profiles,
    Readiness
  }

  def load(%Scope{mission_id: scoped_mission_id} = scope, page, mission_id, params)
      when is_binary(mission_id) and is_map(params) and
             (is_nil(scoped_mission_id) or scoped_mission_id == mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, data} <- read(scope, mission, page, params) do
      JSONBoundary.safe(data)
    end
  rescue
    _exception -> {:error, :spacecraft_page_unavailable}
  end

  def load(_scope, _page, _mission_id, _params), do: {:error, :invalid_spacecraft_page}

  defp read(_scope, mission, "spacecraft_list", params) do
    with :ok <- Directory.validate_params(params), do: Directory.load(mission, params)
  end

  defp read(_scope, mission, "profile_list", params) when map_size(params) == 0,
    do: {:ok, Profiles.directory(mission)}

  defp read(_scope, mission, "spacecraft_new", params) when map_size(params) == 0,
    do: {:ok, IdentityForm.new(mission)}

  defp read(_scope, mission, "profile_new", params) when map_size(params) == 0,
    do: {:ok, ProfileForm.new(mission)}

  defp read(_scope, mission, "spacecraft_edit", %{"spacecraft_id" => id} = params)
       when map_size(params) == 1 and is_binary(id), do: IdentityForm.edit(mission, id)

  defp read(_scope, mission, "profile_show", %{"profile_id" => profile_id} = params)
       when map_size(params) == 1 and is_binary(profile_id) and byte_size(profile_id) in 1..255,
       do: Profiles.detail(mission, profile_id)

  defp read(_scope, _mission, "profile_show", _params), do: {:error, :invalid_application_request}

  defp read(scope, mission, "spacecraft_show", %{"spacecraft_id" => id} = params)
       when map_size(params) == 1 and is_binary(id),
       do: Overview.load(scope, mission, id)

  defp read(scope, mission, "spacecraft_readiness", %{"spacecraft_id" => id} = params)
       when map_size(params) == 1 and is_binary(id),
       do: Readiness.load(scope, mission, id)

  defp read(_scope, _mission, _page, _params), do: {:error, :invalid_spacecraft_page}
end
