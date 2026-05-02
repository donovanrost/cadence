defmodule CadenceWeb.CommsSourceEndpointNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias Cadence.SourceEndpoints.SourceEndpoint

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Runtime Identity")
     |> assign(:nav_item, :comms)
     |> assign(:spacecraft_options, spacecraft_options(spacecraft))
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"source_endpoint" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :source_endpoint))}
  end

  @impl true
  def handle_event("save", %{"source_endpoint" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    display_name = normalize_text(params["display_name"])

    spacecraft_id = normalize_text(params["spacecraft_id"])

    with true <- not is_nil(display_name),
         {:ok, scid} <- source_endpoint_scid(socket.assigns, spacecraft_id, params["scid"]) do
      source_endpoint =
        SourceEndpoint.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: spacecraft_id,
          source_ref: normalize_text(params["source_ref"]),
          scid: scid,
          display_name: display_name,
          metadata: %{}
        })

      case Cadence.persist_source_endpoint(scope.organization_id, source_endpoint) do
        {:ok, _source_endpoint} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/comms/advanced/runtime-identities"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      false ->
        {:noreply, put_flash(socket, :error, "Display name is required.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-source-endpoint-new-page" class="space-y-6 max-w-2xl">
      <div>
        <.link
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/comms/advanced/runtime-identities"
          }
          class="text-sm text-primary hover:underline"
        >
          &larr; Runtime Identities
        </.link>
        <h1 class="mt-1 text-2xl font-bold text-base-content">New Runtime Identity</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Define the ground-side identity Cadence uses to resolve incoming bytes to mission or
          spacecraft ownership.
        </p>
      </div>

      <.form
        for={@form}
        id="source-endpoint-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <.input
          field={@form[:spacecraft_id]}
          type="select"
          label="Spacecraft"
          placeholder="Mission-wide endpoint"
          options={@spacecraft_options}
        />
        <.input field={@form[:source_ref]} type="text" label="Source Ref" />
        <.input field={@form[:scid]} type="text" label="SCID" />

        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">Create Runtime Identity</button>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/advanced/runtime-identities"
            }
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form do
    to_form(
      %{"display_name" => "", "spacecraft_id" => "", "source_ref" => "", "scid" => ""},
      as: :source_endpoint
    )
  end

  defp spacecraft_options(spacecraft) do
    Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})
  end

  defp source_endpoint_scid(assigns, spacecraft_id, scid_param) when is_binary(scid_param) do
    case normalize_text(scid_param) do
      nil -> source_endpoint_scid(assigns, spacecraft_id, nil)
      _scid -> parse_optional_integer(scid_param)
    end
  end

  defp source_endpoint_scid(%{current_scope: scope, current_mission: mission}, spacecraft_id, nil)
       when is_binary(spacecraft_id) do
    case Cadence.fetch_spacecraft(scope.organization_id, mission.mission_id, spacecraft_id) do
      {:ok, spacecraft} -> {:ok, spacecraft.scid}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp source_endpoint_scid(_assigns, _spacecraft_id, scid_param),
    do: parse_optional_integer(scid_param)
end
