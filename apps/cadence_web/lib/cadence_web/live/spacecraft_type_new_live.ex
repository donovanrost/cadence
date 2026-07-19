defmodule CadenceWeb.SpacecraftTypeNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.Catalog, as: ApplicationCatalog
  alias Cadence.SpacecraftType
  alias Phoenix.HTML.Form

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft Profile")
     |> assign(:nav_item, :spacecraft)
     |> assign(:applications, ApplicationCatalog.all())
     |> assign(:form, to_form(empty_form_params(), as: :spacecraft_type))}
  end

  @impl true
  def handle_event("validate", %{"spacecraft_type" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :spacecraft_type))}
  end

  @impl true
  def handle_event("save", %{"spacecraft_type" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, downlink_protocol} <- protocol(params["downlink_protocol"], :downlink),
         {:ok, uplink_protocol} <- protocol(params["uplink_protocol"], :uplink),
         {:ok, frame_parameters} <- frame_parameters(downlink_protocol, params),
         {:ok, applications} <- applications_from_params(params) do
      type =
        SpacecraftType.new(%{
          mission_id: mission.mission_id,
          display_name: display_name,
          downlink_protocol: downlink_protocol,
          uplink_protocol: uplink_protocol,
          packet_protocol: :space_packet,
          frame_parameters: frame_parameters,
          applications: applications
        })

      case Cadence.SpacecraftTypeStore.persist_spacecraft_type(scope.organization_id, type) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{persisted.spacecraft_type_id}"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-profile-new-page" class="space-y-6 max-w-2xl">
      <.page_header
        title="New Spacecraft Profile"
        subtitle="Captures the byte-interpretation contract shared across spacecraft of the same kind — downlink and uplink protocols, frame parameters, and which platform applications run."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {"Spacecraft Profiles", ~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"},
          {"New Spacecraft Profile", nil}
        ]}
      />

      <.form
        for={@form}
        id="spacecraft-profile-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.form_section number="01" title="Identity">
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
        </.form_section>

        <.form_section number="02" title="Data Link Protocols">
          <.input
            field={@form[:downlink_protocol]}
            type="select"
            label="Downlink Protocol"
            options={downlink_protocol_options()}
            required
          />
          <.input
            field={@form[:uplink_protocol]}
            type="select"
            label="Uplink Protocol"
            options={uplink_protocol_options()}
            required
          />
        </.form_section>

        <.frame_parameters_section form={@form} />

        <.applications_section form={@form} applications={@applications} />

        <.form_actions
          submit="Create Profile"
          cancel_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"}
        />
      </.form>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp frame_parameters_section(assigns) do
    ~H"""
    <.form_section number="03" title="Downlink Frame Parameters">
      <p class="text-sm text-base-content/70">
        How the spacecraft frames the bytes it transmits. Fields adapt to the selected downlink protocol.
      </p>

      <.input
        field={@form[:frame_size]}
        type="number"
        label="Transfer Frame Size (bytes)"
        required
      />

      <.input
        :if={frame_field_visible?(@form, :secondary_header_length)}
        field={@form[:secondary_header_length]}
        type="number"
        label="Secondary Header Length (bytes, 0 if absent)"
      />

      <.input
        :if={frame_field_visible?(@form, :insert_zone_length)}
        field={@form[:insert_zone_length]}
        type="number"
        label="Insert Zone Length (bytes, 0 if absent)"
      />

      <.input
        :if={frame_field_visible?(@form, :truncated_primary_header)}
        field={@form[:truncated_primary_header]}
        type="select"
        label="Truncated Primary Header"
        options={[{"No", "false"}, {"Yes", "true"}]}
      />

      <.input
        field={@form[:ocf_length]}
        type="select"
        label="Operational Control Field"
        options={[{"Not present", "0"}, {"Present (4 bytes)", "4"}]}
      />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :applications, :list, required: true

  defp applications_section(assigns) do
    ~H"""
    <.form_section number="04" title="Applications">
      <p class="text-sm text-base-content/70">
        Which platform applications run for spacecraft using this profile. Per-application configuration is set on each spacecraft.
      </p>

      <div class="space-y-3">
        <%!-- bespoke layout: selectable application cards with a raw checkbox (dynamic
        name/checked/disabled that <.input> does not support) --%>
        <label
          :for={app <- @applications}
          class={[
            "flex items-start gap-3 rounded border p-3 transition-colors",
            if(app.available?,
              do:
                "border-base-300 bg-base-100/40 border-l-2 border-l-primary/40 hover:border-l-primary cursor-pointer",
              else: "border-base-300/50 bg-base-100/20 opacity-50 cursor-not-allowed"
            )
          ]}
        >
          <input
            type="checkbox"
            name={"spacecraft_type[applications][#{app.key}]"}
            value="1"
            checked={application_checked?(@form, app.key)}
            disabled={not app.available?}
            class="checkbox checkbox-primary mt-0.5"
          />
          <div>
            <div class="font-medium text-base-content">
              {app.display_name}
              <span :if={not app.available?} class="hud-label ml-2">
                Roadmap
              </span>
            </div>
            <p class="mt-0.5 text-sm text-base-content/70">{app.description}</p>
          </div>
        </label>
      </div>
    </.form_section>
    """
  end

  defp empty_form_params do
    %{
      "display_name" => "",
      "downlink_protocol" => "tm",
      "uplink_protocol" => "tc",
      "frame_size" => "",
      "secondary_header_length" => "0",
      "insert_zone_length" => "0",
      "truncated_primary_header" => "false",
      "ocf_length" => "0",
      "applications" => %{}
    }
  end

  defp downlink_protocol_options do
    [{"TM", "tm"}, {"AOS", "aos"}, {"USLP", "uslp"}]
  end

  defp uplink_protocol_options do
    [{"TC", "tc"}, {"USLP", "uslp"}]
  end

  defp frame_field_visible?(form, :secondary_header_length) do
    Form.input_value(form, :downlink_protocol) in ["tm", :tm]
  end

  defp frame_field_visible?(form, :insert_zone_length) do
    Form.input_value(form, :downlink_protocol) in ["aos", :aos]
  end

  defp frame_field_visible?(form, :truncated_primary_header) do
    Form.input_value(form, :downlink_protocol) in ["uslp", :uslp]
  end

  defp application_checked?(form, key) do
    case Form.input_value(form, :applications) do
      %{} = applications -> Map.has_key?(applications, key)
      _ -> false
    end
  end

  defp protocol("tm", :downlink), do: {:ok, :tm}
  defp protocol("aos", :downlink), do: {:ok, :aos}
  defp protocol("uslp", :downlink), do: {:ok, :uslp}
  defp protocol("tc", :uplink), do: {:ok, :tc}
  defp protocol("uslp", :uplink), do: {:ok, :uslp}
  defp protocol(_, :downlink), do: {:error, "Downlink protocol is invalid."}
  defp protocol(_, :uplink), do: {:error, "Uplink protocol is invalid."}

  defp frame_parameters(:tm, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, secondary_header_length} <-
           non_negative_integer(params["secondary_header_length"], "Secondary header length"),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "secondary_header_length" => secondary_header_length,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp frame_parameters(:aos, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, insert_zone_length} <-
           non_negative_integer(params["insert_zone_length"], "Insert zone length"),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "insert_zone_length" => insert_zone_length,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp frame_parameters(:uslp, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, truncated} <- boolean(params["truncated_primary_header"]),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "truncated_primary_header" => truncated,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp applications_from_params(params) do
    available_by_param =
      ApplicationCatalog.available()
      |> Map.new(fn application -> {application.key, application.key} end)

    applications =
      params
      |> Map.get("applications", %{})
      |> Enum.reduce(%{}, fn {key, _value}, acc ->
        case Map.fetch(available_by_param, key) do
          {:ok, application_key} -> Map.put(acc, application_key, %{})
          :error -> acc
        end
      end)

    {:ok, applications}
  end

  defp required_text(value, message) do
    case normalize(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp positive_integer(value, label) do
    case parse_integer(value) do
      {:ok, integer} when integer > 0 -> {:ok, integer}
      _ -> {:error, "#{label} must be a positive integer."}
    end
  end

  defp non_negative_integer(value, label) do
    case parse_integer(value) do
      {:ok, integer} when integer >= 0 -> {:ok, integer}
      _ -> {:error, "#{label} must be a non-negative integer."}
    end
  end

  defp ocf_length(value) do
    case parse_integer(value) do
      {:ok, 0} -> {:ok, 0}
      {:ok, 4} -> {:ok, 4}
      _ -> {:error, "Operational Control Field must be 0 (absent) or 4 (present)."}
    end
  end

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_), do: {:error, "Truncated primary header must be Yes or No."}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_), do: :error

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_), do: nil

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  defp format_error(reason), do: "Failed to create spacecraft profile: #{inspect(reason)}"
end
