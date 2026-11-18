defmodule Cadence.Control.ActivationRequests.Rows do
  @moduledoc """
  Activation request rows for the console (L10, activations.md `<row>`): what it activates
  (`Description`), who asked and when, its state and latest decision, its execution in the console's
  words (`ApplyAttention.execution_view/2`, the same sentences as the Now item) and whether the viewer
  may decide it. `detail/3` adds server-made facts and the decom comparison report.
  """

  alias Cadence.Accounts
  alias Cadence.Control.ActivationRequests.ConfigurationChanges
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.{ApplyAttention, Description}
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.Directory
  alias Cadence.SpacecraftStore

  @states %{
    approval_pending: "approval_pending",
    approved: "approved",
    rejected: "rejected",
    withdrawn: "withdrawn",
    superseded: "superseded"
  }
  @decisions %{approved: "approved", rejected: "rejected", withdrawn: "withdrawn"}
  @shown_spacecraft 5

  @spec rows(map(), binary(), list()) :: [map()]
  def rows(scope, mission_id, requests) do
    org = scope.organization_id

    decisions =
      Directory.decisions(org, mission_id, Enum.map(requests, & &1.activation_request_id))

    approver? = ManagementActivations.authorize_review(scope, mission_id) == :ok
    viewer = scope.user && scope.user.user_id
    now = DateTime.utc_now()

    names =
      requests
      |> Enum.map(& &1.requester_actor_document)
      |> Kernel.++(Enum.map(Map.values(decisions), & &1.actor))
      |> user_names()

    Enum.map(requests, fn request ->
      description = Description.describe(request.metadata || %{})
      decision = Map.get(decisions, request.activation_request_id)

      %{
        id: request.activation_request_id,
        kind: description.kind,
        app: description.app,
        summary: description.summary,
        binding_set: %{id: request.binding_set_id, version: request.binding_set_version},
        requested_by: actor(request.requester_actor_document, names),
        requested_at: request.requested_at,
        state: Map.fetch!(@states, request.state),
        superseded_by: Map.get(request, :superseded_by),
        superseded_at: Map.get(request, :superseded_at),
        decision: decision(decision, names),
        execution: execution(request, now),
        can_decide:
          request.state == :approval_pending and approver? and
            request.requester_actor_id != viewer
      }
    end)
  end

  @spec detail(map(), binary(), map()) :: map()
  def detail(scope, mission_id, request) do
    [row] = rows(scope, mission_id, [request])
    description = Description.describe(request.metadata || %{})
    mission = mission(scope.organization_id, mission_id)
    reviewed = (mission && ConfigurationChanges.reviewed(mission, request)) || %{}

    Map.merge(row, %{
      details: details(scope.organization_id, mission_id, request, description),
      comparison: comparison(request.metadata || %{}),
      # #235: what a pending spacecraft configuration request changes, grouped, and its
      # reviewed craft on every state; nil for other kinds.
      configuration_changes: configuration_changes(mission, request),
      spacecraft: reviewed[:spacecraft],
      spacecraft_total: reviewed[:spacecraft_total],
      permissions: permissions(scope, mission_id)
    })
  end

  @doc "`[\"activations.approve\"]` for people who may approve, decide and retry."
  def permissions(scope, mission_id) do
    if ManagementActivations.authorize_review(scope, mission_id) == :ok,
      do: ["activations.approve"],
      else: []
  end

  @doc "The opaque `next` cursor after `request`."
  def cursor(request) do
    Base.url_encode64(
      DateTime.to_iso8601(request.requested_at) <> "|" <> request.activation_request_id,
      padding: false
    )
  end

  def decode_cursor(nil), do: {:ok, nil}

  def decode_cursor(value) when is_binary(value) do
    with {:ok, raw} <- Base.url_decode64(value, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, 0} <- DateTime.from_iso8601(at) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, {:invalid_params, %{before: "is not a cursor from this list"}}}
    end
  end

  def decode_cursor(_value),
    do: {:error, {:invalid_params, %{before: "is not a cursor from this list"}}}

  defp execution(request, now) do
    case ControlActivations.fetch_execution(request.activation_request_id) do
      {:ok, execution} -> ApplyAttention.execution_view(execution, now)
      {:error, _none} -> nil
    end
  end

  defp decision(nil, _names), do: nil

  defp decision(decision, names),
    do: %{
      state: Map.fetch!(@decisions, decision.decision),
      by: actor(decision.actor, names),
      at: decision.decided_at,
      reason: decision.reason
    }

  defp actor(%{} = document, names) do
    id = document["id"]
    kind = document["kind"] || "user"
    name = document["display_name"] || document["name"] || Map.get(names, id)
    %{kind: kind, id: id, name: name}
  end

  defp actor(_none, _names), do: nil

  defp user_names(documents) do
    for %{"id" => id} = document <- documents,
        is_binary(id),
        (document["kind"] || "user") == "user",
        is_nil(document["display_name"] || document["name"]),
        uniq: true,
        into: %{} do
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _missing -> {id, nil}
      end
    end
  end

  defp details(org, mission_id, request, description) do
    [
      %{label: "Activates", value: description.summary},
      %{
        label: "Binding set",
        value: "#{request.binding_set_id} v#{request.binding_set_version}"
      },
      spacecraft(org, mission_id, description.spacecraft_ids),
      %{
        label: "Content",
        value: "sha256 " <> String.slice(request.binding_set_content_sha256 || "", 0, 12)
      }
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp spacecraft(_org, _mission_id, []), do: nil

  defp spacecraft(org, mission_id, ids) do
    {:ok, found} =
      SpacecraftStore.fetch_spacecrafts(org, mission_id, Enum.take(ids, @shown_spacecraft))

    shown =
      Enum.map(Enum.take(ids, @shown_spacecraft), &((found[&1] && found[&1].display_name) || &1))

    more = length(ids) - length(shown)
    suffix = if more > 0, do: " and #{more} more", else: ""
    %{label: "Spacecraft", value: Enum.join(shown, ", ") <> suffix}
  end

  defp comparison(%{"mission_model_comparison" => %{"comparison_report_id" => id}})
       when is_binary(id),
       do: %{report_id: id, label: "Mission-model comparison"}

  defp comparison(_metadata), do: nil

  defp configuration_changes(nil, _request), do: nil

  defp configuration_changes(mission, request),
    do: ConfigurationChanges.for_request(mission, request)

  defp mission(org, mission_id) do
    case Cadence.Missions.fetch_mission(org, mission_id) do
      {:ok, mission} -> mission
      {:error, _} -> nil
    end
  end
end
