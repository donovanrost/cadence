defmodule CadenceWeb.SpacecraftConfigurationPage do
  @moduledoc "Authenticated transport adapter for the spacecraft configuration workspace."
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs

  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Control.SpacecraftConfiguration, as: ConfigurationControl
  alias Cadence.Platform.ScopedReadUpdates
  import Phoenix.Component, only: [assign: 3]

  @route "/missions/:mission_id/spacecraft/:spacecraft_id"
  @usage_routes [
    @route,
    "/missions/:mission_id/catalog",
    "/missions/:mission_id/catalog/databases/:catalog_database_id",
    "/missions/:mission_id/catalog/revisions/:catalog_revision_id"
  ]
  def route?(route), do: route == @route

  def subscribe(socket, %{route: route, params: params}) when route in @usage_routes do
    identity = {socket.assigns.current_scope.organization_id, params["mission_id"]}

    if socket.assigns[:spacecraft_configuration_subscription] == identity do
      socket
    else
      socket = unsubscribe(socket)
      {org, mission} = identity

      if Phoenix.LiveView.connected?(socket),
        do: ScopedReadUpdates.subscribe(:spacecraft_configuration_changed, org, mission)

      assign(socket, :spacecraft_configuration_subscription, identity)
    end
  end

  def subscribe(socket, _info), do: unsubscribe(socket)

  defp unsubscribe(socket) do
    case socket.assigns[:spacecraft_configuration_subscription] do
      {org, mission} ->
        ScopedReadUpdates.unsubscribe(:spacecraft_configuration_changed, org, mission)

      _ ->
        :ok
    end

    assign(socket, :spacecraft_configuration_subscription, nil)
  end

  def action(scope, params, event, input) do
    case execute(scope, params, event, input) do
      {:ok, data} when event == "catalog" ->
        %{status: "ok", data: data}

      {:ok, %{"outcome" => "application_needs_review"}} ->
        %{
          status: "ok",
          message:
            "Approval recorded. Runtime application could not be confirmed. Check mission runtime status before making another change."
        }

      {:ok, _} ->
        %{status: "ok", message: success_message(event, input)}

      {:error, reason} ->
        %{status: "rejected", message: message(reason)}
    end
  end

  defp execute(scope, params, "save", %{"token" => token, "document" => document} = input)
       when map_size(input) == 2,
       do:
         ConfigurationDrafts.save(
           scope,
           params["mission_id"],
           params["spacecraft_id"],
           token,
           document
         )

  defp execute(scope, params, event, %{"token" => token, "policy_token" => policy} = input)
       when event in ["review", "activate"] and map_size(input) == 2,
       do:
         ConfigurationControl.submit(
           scope,
           params["mission_id"],
           params["spacecraft_id"],
           token,
           policy,
           if(event == "review", do: :review, else: :activate)
         )

  defp execute(
         scope,
         params,
         "decide",
         %{"token" => token, "request_id" => request, "reason" => reason, "decision" => decision} =
           input
       )
       when map_size(input) == 4,
       do:
         ConfigurationControl.decide(
           scope,
           params["mission_id"],
           params["spacecraft_id"],
           token,
           request,
           reason,
           decision
         )

  defp execute(scope, params, "catalog", %{"id" => id} = input) when map_size(input) == 1,
    do:
      ConfigurationCatalogs.packets(
        scope,
        params["mission_id"],
        params["spacecraft_id"],
        id
      )

  defp execute(_, _, _, _), do: {:error, :invalid_spacecraft_configuration}

  defp success_message("save", _), do: "Draft saved. Active configuration remains in use."

  defp success_message("review", _),
    do: "Submitted for review. Another person can approve this revision from the Changes page."

  defp success_message("activate", _), do: "Configuration activated."

  defp success_message("decide", %{"decision" => "rejected"}),
    do: "Review rejected. Update the draft before submitting again."

  defp success_message("decide", _), do: "Configuration approved and activated."

  defp message(:spacecraft_configuration_changed),
    do:
      "This spacecraft changed since you started editing. Compare the latest saved configuration before saving again."

  defp message(:activation_policy_changed),
    do:
      "Approval settings changed. Review the current requirements and submit this revision again."

  defp message(:activation_self_approval_forbidden),
    do: "A different person must review this configuration."

  defp message(:spacecraft_catalog_required),
    do: "Choose a catalog before submitting this configuration."

  defp message(:spacecraft_packet_inputs_required),
    do: "Connect a packet source and select packets for Telemetry Decom."

  defp message(:spacecraft_configuration_review_unavailable),
    do: "Save your current configuration and resolve external changes before submitting it."

  defp message(:spacecraft_configuration_review_stale),
    do: "The active fleet configuration changed. Review the latest state and submit again."

  defp message(_),
    do:
      "This change could not be accepted. Check the catalog, packet inputs, and your mission access."
end
