defmodule Cadence.ConfigurationFixtures do
  @moduledoc "Missions, member scopes and governance settings for change-set tests."

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  @doc "Persists an organization + mission and returns their ids."
  def configuration_mission(prefix \\ "cfg") do
    organization_id = unique("org-#{prefix}")
    mission_id = unique("mission-#{prefix}")
    Cadence.DataCase.persist_mission_scope(organization_id, mission_id)
    %{organization_id: organization_id, mission_id: mission_id}
  end

  @doc "A user scope with an active membership in the organization."
  def member_scope(organization_id, role \\ :member, name \\ nil) do
    user_id = unique("user")

    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: name || user_id
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user_id,
        organization_id: organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_membership: membership,
      organization_id: organization_id
    })
  end

  @doc "Sets the deployment default approval requirement for the duration of a test."
  def with_approval_required(required?) do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: required?)
    fn -> Application.put_env(:cadence, :activation_governance, previous) end
  end

  def station_op(name, attrs \\ %{}) do
    %{
      kind: "ground_station",
      action: :create,
      document: Map.merge(%{"display_name" => name, "region" => "Arctic"}, attrs)
    }
  end

  def transport_doc(name) do
    %{
      "display_name" => name,
      "configuration" => %{
        "mode" => "listen",
        "direction_capability" => "inbound",
        "host" => "0.0.0.0",
        "port" => "5000",
        "framing_mode" => "raw",
        "tls_enabled" => "false"
      }
    }
  end

  def profile_doc(name, frame \\ %{}) do
    %{
      "display_name" => name,
      "downlink_protocol" => "tm",
      "uplink_protocol" => "tc",
      "frame_parameters" => Map.merge(%{"frame_size" => 1115, "ocf_length" => 4}, frame)
    }
  end

  def spacecraft_doc(name, scid, pin \\ nil) do
    {type_id, version} = pin || {nil, nil}

    %{
      "display_name" => name,
      "scid" => scid,
      "spacecraft_type_id" => type_id,
      "spacecraft_type_version" => version
    }
  end

  def unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
