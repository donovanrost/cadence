defmodule CadenceWeb.CommsLinkTemplateNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias Cadence.Contacts.PathTemplate

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    spacecraft_context =
      load_spacecraft_context(params, scope.organization_id, mission.mission_id)

    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    socket =
      socket
      |> assign(:nav_item, :comms_link_templates)
      |> assign(
        :provider_profiles_by_id,
        Map.new(provider_profiles, &{&1.provider_profile_id, &1})
      )
      |> assign(
        :transport_profiles_by_id,
        Map.new(transport_profiles, &{&1.transport_profile_id, &1})
      )
      |> assign_form_mode(params, spacecraft_context)
      |> assign_profile_options()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"path_template" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :path_template))}
  end

  @impl true
  def handle_event("save", %{"path_template" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    provider_profile_id = normalize_text(params["provider_profile_id"])
    transport_profile_id = normalize_text(params["transport_profile_id"])
    display_name = normalize_text(params["display_name"])

    if is_nil(display_name) do
      {:noreply, put_flash(socket, :error, "Display name is required.")}
    else
      attrs =
        path_template_attrs(
          socket,
          mission,
          params,
          display_name,
          provider_profile_id,
          transport_profile_id
        )

      case save_path_template(socket, scope.organization_id, mission, attrs) do
        {:ok, _path_template} ->
          {:noreply,
           push_navigate(socket,
             to: socket.assigns.return_to
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-link-template-new-page" class="space-y-6 max-w-2xl">
      <div>
        <.link
          navigate={@return_to}
          class="text-sm text-primary hover:underline"
        >
          &larr; {back_label(@spacecraft_context)}
        </.link>
        <h1 class="mt-1 text-2xl font-bold text-base-content">{@heading}</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Define the reusable mission network path once. Spacecraft use it through explicit
          link assignments from readiness, apply-template, or spacecraft link workflows.
        </p>
      </div>

      <div
        :if={@spacecraft_context.spacecraft}
        id="link-template-spacecraft-context"
        class="rounded border border-primary/20 bg-primary/5 p-4 text-sm"
      >
        <p class="hud-label mb-1">Spacecraft Assignment</p>
        <p class="font-semibold">{@spacecraft_context.spacecraft.display_name}</p>
        <p class="mt-1 font-mono text-xs text-base-content/60">
          SCID {format_context_scid(@spacecraft_context.spacecraft.scid)}
        </p>
        <p class="mt-2 text-xs text-base-content/60">
          This page creates a reusable mission link template. Assign it to this spacecraft from
          spacecraft links after saving.
        </p>
      </div>

      <section
        :if={@pending_profile_upgrades != []}
        id="link-template-version-upgrade-preview"
        class="rounded border border-warning/30 bg-warning/10 p-4 text-sm"
      >
        <p class="hud-label mb-2 text-warning">Version Update Preview</p>
        <p class="font-semibold">This new link template version will move pinned profiles forward.</p>
        <div class="mt-3 space-y-2">
          <p :for={upgrade <- @pending_profile_upgrades}>
            {upgrade.label} will update from v{upgrade.current_version} to v{upgrade.latest_version}.
          </p>
        </div>
      </section>

      <.form
        for={@form}
        id="link-template-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <fieldset class="space-y-4 rounded border border-base-300 bg-base-100/40 p-4">
          <legend class="px-1 hud-label">Template</legend>
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
          <.input
            field={@form[:direction]}
            type="select"
            label="Direction"
            options={direction_options()}
            required
          />
          <.input
            field={@form[:selection_role]}
            type="select"
            label="Assignment Role"
            options={selection_role_options()}
            required
          />
        </fieldset>

        <fieldset class="space-y-4 rounded border border-base-300 bg-base-100/40 p-4">
          <legend class="px-1 hud-label">Network Path</legend>
          <.input
            field={@form[:provider_profile_id]}
            type="select"
            label="Provider"
            placeholder="Select a provider"
            options={@provider_profile_options}
            required
          />
          <.input
            field={@form[:transport_profile_id]}
            type="select"
            label="Protocol Behavior"
            placeholder="No protocol behavior"
            options={@transport_profile_options}
          />
          <.input field={@form[:provider_path_ref]} type="text" label="Provider Path Ref" />
        </fieldset>

        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">{@submit_label}</button>
          <.link
            navigate={@return_to}
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form(spacecraft_context) do
    to_form(
      empty_form_params(spacecraft_context),
      as: :path_template
    )
  end

  defp empty_form_params(_spacecraft_context) do
    %{
      "display_name" => "",
      "direction" => "downlink",
      "selection_role" => "selected",
      "provider_path_ref" => "",
      "provider_profile_id" => "",
      "transport_profile_id" => ""
    }
  end

  defp form_from_path_template(path_template) do
    to_form(path_template_form_params(path_template), as: :path_template)
  end

  defp path_template_form_params(path_template) do
    %{
      "display_name" => display_name(path_template, :path_id),
      "direction" => Atom.to_string(path_template.direction),
      "selection_role" => Atom.to_string(path_template.selection_role),
      "provider_path_ref" => path_template.provider_path_ref || "",
      "provider_profile_id" =>
        first_ref_id(path_template.provider_profile_refs, "provider_profile_id"),
      "transport_profile_id" =>
        first_ref_id(path_template.transport_profile_refs, "transport_profile_id")
    }
  end

  defp assign_profile_options(socket) do
    %{
      path_template: path_template,
      provider_profiles_by_id: provider_profiles_by_id,
      transport_profiles_by_id: transport_profiles_by_id
    } = socket.assigns

    socket
    |> assign(
      :provider_profile_options,
      profile_options(provider_profiles_by_id, path_template, "provider_profile_id")
    )
    |> assign(
      :transport_profile_options,
      profile_options(transport_profiles_by_id, path_template, "transport_profile_id")
    )
    |> assign(
      :pending_profile_upgrades,
      pending_profile_upgrades(path_template, provider_profiles_by_id, transport_profiles_by_id)
    )
  end

  defp profile_options(profiles_by_id, nil, _id_key) do
    profiles_by_id
    |> Map.values()
    |> Enum.map(fn profile ->
      {"#{display_name(profile, profile_fallback_field(profile))} v#{profile.version}",
       profile_id(profile)}
    end)
  end

  defp profile_options(profiles_by_id, path_template, id_key) do
    pinned_versions = pinned_versions(path_template, id_key)

    profiles_by_id
    |> Map.values()
    |> Enum.map(fn profile ->
      profile_id = profile_id(profile)
      label = display_name(profile, profile_fallback_field(profile))

      {
        profile_option_label(label, Map.get(pinned_versions, profile_id), profile.version),
        profile_id
      }
    end)
  end

  defp profile_option_label(label, nil, latest_version), do: "#{label} v#{latest_version}"

  defp profile_option_label(label, pinned_version, latest_version)
       when pinned_version < latest_version do
    "#{label} · current v#{pinned_version} -> latest v#{latest_version}"
  end

  defp profile_option_label(label, pinned_version, _latest_version) do
    "#{label} · current v#{pinned_version} (latest)"
  end

  defp pending_profile_upgrades(nil, _provider_profiles_by_id, _transport_profiles_by_id), do: []

  defp pending_profile_upgrades(path_template, provider_profiles_by_id, transport_profiles_by_id) do
    provider_upgrades =
      profile_upgrades(
        path_template.provider_profile_refs,
        provider_profiles_by_id,
        "provider_profile_id",
        :provider_profile_id
      )

    transport_upgrades =
      profile_upgrades(
        path_template.transport_profile_refs,
        transport_profiles_by_id,
        "transport_profile_id",
        :transport_profile_id
      )

    provider_upgrades ++ transport_upgrades
  end

  defp profile_upgrades(refs, profiles_by_id, id_key, fallback_field) do
    Enum.flat_map(refs, fn ref ->
      profile_id = Map.get(ref, id_key)
      current_version = ref_version(ref)

      case Map.fetch(profiles_by_id, profile_id) do
        {:ok, %{version: latest_version} = profile} when current_version < latest_version ->
          [
            %{
              label: display_name(profile, fallback_field),
              current_version: current_version,
              latest_version: latest_version
            }
          ]

        _other ->
          []
      end
    end)
  end

  defp pinned_versions(nil, _id_key), do: %{}

  defp pinned_versions(path_template, "provider_profile_id") do
    Map.new(path_template.provider_profile_refs, fn ref ->
      {Map.get(ref, "provider_profile_id"), ref_version(ref)}
    end)
  end

  defp pinned_versions(path_template, "transport_profile_id") do
    Map.new(path_template.transport_profile_refs, fn ref ->
      {Map.get(ref, "transport_profile_id"), ref_version(ref)}
    end)
  end

  defp profile_id(%{provider_profile_id: provider_profile_id}), do: provider_profile_id
  defp profile_id(%{transport_profile_id: transport_profile_id}), do: transport_profile_id

  defp profile_fallback_field(%{provider_profile_id: _provider_profile_id}),
    do: :provider_profile_id

  defp profile_fallback_field(%{transport_profile_id: _transport_profile_id}),
    do: :transport_profile_id

  defp profile_refs(nil, _profiles_by_id, _id_key), do: []

  defp profile_refs(profile_id, profiles_by_id, id_key) do
    case Map.fetch(profiles_by_id, profile_id) do
      {:ok, %{version: version}} ->
        [%{id_key => profile_id, "version" => version}]

      :error ->
        []
    end
  end

  defp load_spacecraft_context(%{"spacecraft_id" => spacecraft_id}, organization_id, mission_id)
       when is_binary(spacecraft_id) and spacecraft_id != "" do
    case Cadence.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      {:ok, spacecraft} ->
        %{spacecraft: spacecraft}

      {:error, _reason} ->
        %{spacecraft: nil}
    end
  end

  defp load_spacecraft_context(_params, _organization_id, _mission_id) do
    %{spacecraft: nil}
  end

  defp return_to(mission_id, %{spacecraft: nil}),
    do: ~p"/missions/#{mission_id}/comms/link-templates"

  defp return_to(mission_id, %{spacecraft: _spacecraft}), do: ~p"/missions/#{mission_id}/comms"

  defp back_label(%{spacecraft: nil}), do: "Link Templates"
  defp back_label(%{spacecraft: _spacecraft}), do: "Comms readiness"

  defp format_context_scid(nil), do: "not set"
  defp format_context_scid(scid), do: Integer.to_string(scid)

  defp assign_form_mode(
         %{assigns: %{live_action: :version, current_scope: scope, current_mission: mission}} =
           socket,
         %{"path_template_id" => path_template_id},
         spacecraft_context
       ) do
    case Cadence.fetch_path_template(scope.organization_id, mission.mission_id, path_template_id) do
      {:ok, path_template} ->
        socket
        |> assign(:page_title, "New Link Template Version")
        |> assign(:path_template, path_template)
        |> assign(:spacecraft_context, spacecraft_context)
        |> assign(
          :return_to,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{path_template_id}"
        )
        |> assign(:heading, "New Link Template Version")
        |> assign(:submit_label, "Create New Version")
        |> assign(:form, form_from_path_template(path_template))

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Link template not found.")
        |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/link-templates")
    end
  end

  defp assign_form_mode(socket, _params, spacecraft_context) do
    %{current_mission: mission} = socket.assigns

    socket
    |> assign(:page_title, "New Link Template")
    |> assign(:path_template, nil)
    |> assign(:spacecraft_context, spacecraft_context)
    |> assign(:return_to, return_to(mission.mission_id, spacecraft_context))
    |> assign(:heading, "New Link Template")
    |> assign(:submit_label, "Create Link Template")
    |> assign(:form, empty_form(spacecraft_context))
  end

  defp path_template_attrs(
         socket,
         mission,
         params,
         display_name,
         provider_profile_id,
         transport_profile_id
       ) do
    %{
      mission_id: mission.mission_id,
      direction: direction(params["direction"]),
      selection_role: selection_role(params["selection_role"]),
      source_endpoint_ref: nil,
      provider_path_ref: normalize_text(params["provider_path_ref"]),
      provider_profile_refs:
        profile_refs(
          provider_profile_id,
          socket.assigns.provider_profiles_by_id,
          "provider_profile_id"
        ),
      transport_profile_refs:
        profile_refs(
          transport_profile_id,
          socket.assigns.transport_profiles_by_id,
          "transport_profile_id"
        ),
      metadata: %{"display_name" => display_name}
    }
  end

  defp save_path_template(
         %{assigns: %{live_action: :version, path_template: path_template}},
         organization_id,
         mission,
         attrs
       ) do
    Cadence.version_path_template(
      organization_id,
      mission.mission_id,
      path_template.path_template_id,
      Map.drop(attrs, [:mission_id])
    )
  end

  defp save_path_template(_socket, organization_id, _mission, attrs) do
    Cadence.persist_path_template(organization_id, PathTemplate.new(attrs))
  end

  defp ref_version(ref) do
    case Map.get(ref, "version") do
      version when is_integer(version) -> version
      version when is_binary(version) -> parse_ref_version(version)
      _other -> 1
    end
  end

  defp parse_ref_version(value) do
    case Integer.parse(value) do
      {version, ""} -> version
      _other -> 1
    end
  end

  defp first_ref_id([ref | _rest], id_key), do: Map.get(ref, id_key) || ""
  defp first_ref_id([], _id_key), do: ""

  defp direction("downlink"), do: :downlink
  defp direction("uplink"), do: :uplink

  defp selection_role("selected"), do: :selected
  defp selection_role("candidate"), do: :candidate
  defp selection_role("contributing"), do: :contributing
end
