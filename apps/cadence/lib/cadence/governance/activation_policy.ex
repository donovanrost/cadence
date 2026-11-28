defmodule Cadence.Governance.ActivationPolicy do
  @moduledoc "Organization approval requirements, mission overrides, and exact policy evidence."
  alias Cadence.Auth.{Policy, SettingsAccess}
  alias Cadence.Governance.ApprovalTightening
  alias Cadence.Missions
  alias Cadence.Platform.ScopedSettings

  @behaviour Cadence.Applications.SettingsProvider
  @section "cadence.governance"
  def section_id, do: @section

  def load(organization_id, mission_id),
    do: ScopedSettings.load(organization_id, mission_id, @section, default())

  @doc """
  Runs `operation` with the policy held STABLE: the policy lock taken shared (first in
  `Cadence.Governance.ActivationLocks`' order). Approvals, decisions and applies don't block each
  other on it; a policy save (`save/4`, exclusive) waits for them.
  """
  def with_stable_policy(organization_id, operation),
    do: ScopedSettings.with_shared_lock(organization_id, @section, operation)

  def settings_snapshot(organization_id, nil) do
    missions = Missions.settings_overview(organization_id)

    snapshots =
      ScopedSettings.load_many(
        organization_id,
        [nil | Enum.map(missions.items, & &1.id)],
        @section,
        default()
      )

    Map.fetch!(snapshots, nil)
    |> Map.put(:missions_total, missions.total)
    |> Map.put(
      :missions,
      Enum.map(missions.items, fn mission ->
        Map.put(mission, :override, Map.fetch!(snapshots, mission.id).saved)
      end)
    )
  end

  def settings_snapshot(organization_id, mission_id), do: load(organization_id, mission_id)

  @doc """
  Saves the approval setting for the organization (`mission_id` nil) or a mission (DECISIONS #111,
  the user's rule, board #233). Who may change it, decided under the section lock against what the
  save replaces:
    * the organization's setting (its default and whether missions may override): an organization
      admin only, in either direction;
    * a mission's setting: LOOSENING (its effective requirement goes from 'independent' to
      'direct') or pinning its own 'direct' (even while 'direct' is inherited) needs an
      organization admin; TIGHTENING or leaving it as it is needs that mission's admin (or an
      organization admin). Operators can't change it at all.
  Every change records who, when, and the effective setting before and after (`audit`); a refused
  change records nothing.
  """
  def save(scope, mission_id, token, input, opts \\ []) do
    # Reading the section is any member's; who may CHANGE it is this section's own rule
    # (`may_change/4`, below), which answers with its own refusal (#1159: the generic settings
    # gate for an organization's settings is now an organization admin, which would pre-empt it).
    with :ok <- SettingsAccess.authorize(scope, :read_settings, mission_id),
         {:ok, document} <- decode(mission_id, input) do
      org = scope.organization_id
      acknowledged = Keyword.get(opts, :acknowledged_suspensions)
      tightening_opts = Keyword.take(opts, [:now])

      ScopedSettings.save(
        org,
        mission_id,
        @section,
        default(),
        token,
        document,
        SettingsAccess.actor(scope),
        check: fn current ->
          with :ok <- may_change(scope, mission_id, current, document),
               do:
                 preview(
                   org,
                   tightened(org, mission_id, current, document),
                   acknowledged,
                   tightening_opts
                 )
        end,
        audit: &audit(org, mission_id, &1, document),
        after_write: fn current, revision ->
          tightened = tightened(org, mission_id, current, document)
          suspend(scope, tightened, revision, mission_id, tightening_opts)
        end
      )
    end
  end

  # #499: the missions this save tightens ('direct' to 'independent', by ScopedSettings' one
  # rule): the mission itself on a mission save; on an organization save, each mission #430's
  # list moved that way. Read under the save's lock, so the preview and the suspension agree.
  defp tightened(org, nil = _mission, current, document) do
    for %{"before" => "direct", "after" => "independent", "mission_id" => id} <-
          moved_missions(org, current, document),
        do: id
  end

  defp tightened(_org, mission_id, current, document) do
    before = requirement(current.effective)
    after_value = requirement(after_effective(current, document))
    if before == "direct" and after_value == "independent", do: [mission_id], else: []
  end

  defp preview(_org, [], _acknowledged, _opts), do: :ok

  # ca-security: with nothing registered a tightening is refused, never let through unchecked
  # (fail closed: a missing config line must not switch the control off).
  defp preview(org, mission_ids, acknowledged, opts) do
    case ApprovalTightening.implementation() do
      nil -> {:error, :approval_tightening_unavailable}
      tightening -> tightening.preview(org, mission_ids, acknowledged, opts)
    end
  end

  defp suspend(_scope, [], _revision, _mission_id, _opts), do: :ok

  defp suspend(scope, mission_ids, revision, mission_id, opts) do
    level = if mission_id, do: "mission", else: "organization"

    case ApprovalTightening.implementation() do
      nil ->
        {:error, :approval_tightening_unavailable}

      tightening ->
        with {:ok, _suspended} <-
               tightening.apply(
                 scope,
                 scope.organization_id,
                 mission_ids,
                 revision.revision_id,
                 level,
                 opts
               ),
             do: :ok
    end
  end

  # todo(authz): these named Policy actions are the boundary Cedar will decide (organization admin,
  # mission admin); the direction rule stays here.
  defp may_change(scope, nil, _current, _document),
    do: organization_admin(scope)

  # Pinning a mission's own 'direct' is reserved for an organization admin even when 'direct' is
  # already in effect (inherited): it's a loosening in advance, since the organization's later
  # tightening would never reach that mission (api-ops, lead 11-18).
  defp may_change(scope, mission_id, current, document) do
    if loosens?(current.effective, after_effective(current, document)) or pins_direct?(document),
      do: organization_admin(scope),
      else: mission_admin(scope, mission_id)
  end

  defp pins_direct?(%{"value" => %{"approval_requirement" => "direct"}}), do: true
  defp pins_direct?(_document), do: false

  defp organization_admin(scope) do
    case Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) do
      :ok -> :ok
      _refused -> {:error, :approval_policy_change_requires_organization_admin}
    end
  end

  defp mission_admin(scope, mission_id) do
    case Policy.authorize(scope, :manage_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission_id
         }) do
      :ok -> :ok
      _refused -> {:error, :approval_policy_change_requires_mission_admin}
    end
  end

  defp loosens?(before, after_value),
    do: requirement(before) == "independent" and requirement(after_value) == "direct"

  defp requirement(effective), do: (effective || %{})["approval_requirement"]

  # A mission's effective setting after the save, by ScopedSettings' one rule (#430): the
  # organization's value with the new override merged in, or the organization's when the override
  # is nil (a mission save only runs while overrides are allowed).
  defp after_effective(current, document),
    do:
      ScopedSettings.effective_for(
        current.organization_default,
        current.allow_override,
        document["value"]
      )

  defp audit(organization_id, nil, current, document) do
    %{
      "scope" => "organization",
      "before" => %{
        "value" => current.organization_default,
        "allow_override" => current.allow_override
      },
      "after" => %{"value" => document["value"], "allow_override" => document["allow_override"]},
      "missions" => moved_missions(organization_id, current, document)
    }
  end

  defp audit(_organization_id, _mission_id, current, document) do
    %{
      "scope" => "mission",
      "before" => %{"effective" => current.effective, "override" => current.saved},
      "after" => %{
        "effective" => after_effective(current, document),
        "override" => document["value"]
      }
    }
  end

  # #430: every mission of the organization whose effective requirement this organization save
  # changes (turning overrides off or on, or a default change reaching inheriting missions), each
  # with its raw requirement before and after. Read under the save's own section lock, which
  # mission saves also take, so it is exactly what the save changed. Missions have no archived
  # state: every mission row of the organization is read, unpaged.
  defp moved_missions(organization_id, current, document) do
    ids = organization_id |> Missions.list_missions() |> Enum.map(& &1.mission_id)
    snapshots = ScopedSettings.load_many(organization_id, ids, @section, default())

    Enum.flat_map(ids, fn id ->
      saved = Map.fetch!(snapshots, id).saved

      before =
        current.organization_default
        |> ScopedSettings.effective_for(current.allow_override, saved)
        |> requirement()

      after_value =
        document["value"]
        |> ScopedSettings.effective_for(document["allow_override"], saved)
        |> requirement()

      if before == after_value,
        do: [],
        else: [%{"mission_id" => id, "before" => before, "after" => after_value}]
    end)
  end

  def evidence(organization_id, mission_id) do
    current = load(organization_id, mission_id)
    required = current.effective["approval_requirement"] == "independent"

    %{
      "policy" => "scoped_activation_approvals_v1",
      "settings_token" => current.token,
      "approval_required" => required,
      "required_human_approvals" => if(required, do: 1, else: 0),
      "separation_of_duties" => required
    }
  end

  def current?(organization_id, mission_id, policy),
    do: policy == evidence(organization_id, mission_id)

  def validate(organization_id, mission_id, policy) do
    if current?(organization_id, mission_id, policy),
      do: :ok,
      else: {:error, :activation_policy_changed}
  end

  defp default do
    required =
      Application.get_env(:cadence, :activation_governance, [])
      |> Keyword.get(:approval_required, true)

    %{
      "value" => %{"approval_requirement" => if(required, do: "independent", else: "direct")},
      "allow_override" => true
    }
  end

  defp decode(nil, %{"value" => value, "allow_override" => allowed} = input)
       when map_size(input) == 2 and is_boolean(allowed) do
    with :ok <- value(value),
         true <- allowed or value["approval_requirement"] == "independent" do
      {:ok, input}
    else
      _ -> {:error, :invalid_settings}
    end
  end

  defp decode(mission, %{"value" => nil} = input)
       when is_binary(mission) and map_size(input) == 1, do: {:ok, input}

  defp decode(mission, %{"value" => value} = input)
       when is_binary(mission) and map_size(input) == 1 do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(_, _), do: {:error, :invalid_settings}

  defp value(%{"approval_requirement" => requirement} = value)
       when map_size(value) == 1 and requirement in ["direct", "independent"], do: :ok

  defp value(_), do: {:error, :invalid_settings}
end
