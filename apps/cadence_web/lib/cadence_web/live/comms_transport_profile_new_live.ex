defmodule CadenceWeb.CommsTransportProfileNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias Cadence.Contacts.TransportProfile
  alias Phoenix.HTML.Form

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_form_state(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"transport_profile" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :transport_profile))}
  end

  @impl true
  def handle_event("save", %{"transport_profile" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    display_name = normalize_text(params["display_name"])

    with true <- not is_nil(display_name),
         {:ok, family_key} <- family_key(params["family_key"]),
         {:ok, target_scope} <- target_scope(params["target_scope"]),
         {:ok, configuration} <- transport_configuration(family_key, params) do
      case save_transport_profile(
             socket,
             scope.organization_id,
             mission,
             display_name,
             family_key,
             target_scope,
             configuration
           ) do
        {:ok, _transport_profile} ->
          {:noreply,
           push_navigate(socket,
             to: transport_profile_return_path(socket, mission.mission_id)
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
    <div id="comms-transport-profile-new-page" class="space-y-6 max-w-3xl">
      <div>
        <.link navigate={@return_to} class="text-sm text-primary hover:underline">
          &larr; {@back_label}
        </.link>
        <h1 class="mt-1 text-2xl font-bold text-base-content">{@heading}</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Configure reusable protocol behavior for mission links. Keep spacecraft-specific
          interpretation with the spacecraft unless this behavior is intentionally dedicated.
        </p>
      </div>

      <.form
        for={@form}
        id="transport-profile-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-5"
      >
        <section class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-4">
            <div>
              <p class="hud-label mb-2">Profile Identity</p>
              <p class="text-sm text-base-content/60">
                Name the reusable protocol behavior and choose where the runtime will attach it.
              </p>
            </div>

            <.input field={@form[:display_name]} type="text" label="Display Name" required />
            <.input
              field={@form[:family_key]}
              type="select"
              label="Transport Family"
              options={transport_family_options()}
              required
            />
            <.input
              field={@form[:target_scope]}
              type="select"
              label="Target Scope"
              options={target_scope_options()}
              required
            />
          </div>
        </section>

        <section :if={family_value(@form) == "heartbeat_monitor"} class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-4">
            <div>
              <p class="hud-label mb-2">Heartbeat Monitor</p>
              <h2 class="font-semibold">Detect quiet or stalled contact paths</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Schedules deterministic heartbeat timers under the realized path or transport.
              </p>
            </div>

            <.input
              field={@form[:heartbeat_interval_ms]}
              type="number"
              label="Heartbeat Interval (ms)"
              required
            />
          </div>
        </section>

        <section :if={family_value(@form) == "uplink_gateway"} class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-5">
            <div>
              <p class="hud-label mb-2">Uplink Gateway</p>
              <h2 class="font-semibold">Frame command releases into CCSDS TC transfer frames</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Keep SCID blank for reusable constellation-wide profiles. The spacecraft/path
                identity remains the source of truth for spacecraft routing.
              </p>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input field={@form[:service_name]} type="text" label="Service Name (optional)" />
              <.input field={@form[:frame_size]} type="number" label="TC Frame Size (bytes)" required />
              <.input field={@form[:scid]} type="number" label="SCID Override (optional)" />
              <.input field={@form[:vcid]} type="number" label="VCID" required />
              <.input
                field={@form[:bypass_flag]}
                type="select"
                label="Bypass Flag"
                options={flag_options()}
                required
              />
              <.input
                field={@form[:control_command_flag]}
                type="select"
                label="Control Command Flag"
                options={flag_options()}
                required
              />
              <.input
                field={@form[:segment_header_flag]}
                type="select"
                label="Segment Header Flag"
                options={flag_options()}
                required
              />
              <.input
                field={@form[:initial_frame_seq]}
                type="number"
                label="Initial Frame Sequence"
                required
              />
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:cop1_mode]}
                type="select"
                label="COP-1 Mode"
                options={cop1_mode_options()}
                required
              />
              <.input
                field={@form[:cop1_timeout_ms]}
                type="number"
                label="COP-1 Timeout (ms)"
                required
              />
              <.input
                field={@form[:cop1_max_retransmit]}
                type="number"
                label="COP-1 Max Retransmit"
                required
              />
              <.input
                field={@form[:cop1_window_size]}
                type="select"
                label="COP-1 Window Size"
                options={[{"1 frame", "1"}]}
                required
              />
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:simulated_start_delay_ms]}
                type="number"
                label="Simulated Start Delay (ms, optional)"
              />
              <.input
                field={@form[:simulated_completion_delay_ms]}
                type="number"
                label="Simulated Completion Delay (ms, optional)"
              />
            </div>
          </div>
        </section>

        <details class="rounded border border-base-300 bg-base-100/40 p-4 text-sm">
          <summary class="cursor-pointer hud-label">Advanced Configuration Preview</summary>
          <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(preview_configuration(@form), pretty: true)}</pre>
        </details>

        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">{@submit_label}</button>
          <.link navigate={@return_to} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form, do: to_form(empty_form_params(), as: :transport_profile)

  defp empty_form_params do
    %{
      "display_name" => "",
      "family_key" => "heartbeat_monitor",
      "target_scope" => "path",
      "heartbeat_interval_ms" => "1000",
      "service_name" => "",
      "frame_size" => "32",
      "scid" => "",
      "vcid" => "0",
      "bypass_flag" => "0",
      "control_command_flag" => "0",
      "segment_header_flag" => "0",
      "initial_frame_seq" => "0",
      "cop1_mode" => "disabled",
      "cop1_timeout_ms" => "5000",
      "cop1_max_retransmit" => "3",
      "cop1_window_size" => "1",
      "simulated_start_delay_ms" => "",
      "simulated_completion_delay_ms" => ""
    }
  end

  defp form_from_transport_profile(transport_profile) do
    to_form(transport_profile_form_params(transport_profile), as: :transport_profile)
  end

  defp transport_profile_form_params(transport_profile) do
    configuration = transport_profile.configuration

    empty_form_params()
    |> Map.merge(%{
      "display_name" => display_name(transport_profile, :transport_profile_id),
      "family_key" => Atom.to_string(transport_profile.family_key),
      "target_scope" => Atom.to_string(transport_profile.target_scope)
    })
    |> Map.merge(configuration_form_params(transport_profile.family_key, configuration))
  end

  defp configuration_form_params(:heartbeat_monitor, configuration) do
    %{
      "heartbeat_interval_ms" =>
        string_value(Map.get(configuration, "heartbeat_interval_ms", "1000"))
    }
  end

  defp configuration_form_params(:uplink_gateway, configuration) do
    %{
      "service_name" => Map.get(configuration, "service_name", ""),
      "frame_size" => string_value(Map.get(configuration, "frame_size", "32")),
      "scid" => string_value(Map.get(configuration, "scid", "")),
      "vcid" => string_value(Map.get(configuration, "vcid", "0")),
      "bypass_flag" => string_value(Map.get(configuration, "bypass_flag", "0")),
      "control_command_flag" => string_value(Map.get(configuration, "control_command_flag", "0")),
      "segment_header_flag" => string_value(Map.get(configuration, "segment_header_flag", "0")),
      "initial_frame_seq" => string_value(Map.get(configuration, "initial_frame_seq", "0")),
      "cop1_mode" => Map.get(configuration, "cop1_mode", "disabled"),
      "cop1_timeout_ms" => string_value(Map.get(configuration, "cop1_timeout_ms", "5000")),
      "cop1_max_retransmit" => string_value(Map.get(configuration, "cop1_max_retransmit", "3")),
      "cop1_window_size" => string_value(Map.get(configuration, "cop1_window_size", "1")),
      "simulated_start_delay_ms" =>
        string_value(Map.get(configuration, "simulated_start_delay_ms", "")),
      "simulated_completion_delay_ms" =>
        string_value(Map.get(configuration, "simulated_completion_delay_ms", ""))
    }
  end

  defp configuration_form_params(_family_key, _configuration), do: %{}

  defp transport_configuration("heartbeat_monitor", params) do
    with {:ok, interval_ms} <-
           positive_integer(params["heartbeat_interval_ms"], "Heartbeat interval") do
      {:ok, %{"heartbeat_interval_ms" => interval_ms}}
    end
  end

  defp transport_configuration("uplink_gateway", params) do
    with {:ok, frame_size} <- integer_in_range(params["frame_size"], 6, nil, "Frame size"),
         {:ok, scid} <- optional_integer_in_range(params["scid"], 0, 1023, "SCID"),
         {:ok, vcid} <- integer_in_range(params["vcid"], 0, 63, "VCID"),
         {:ok, bypass_flag} <- flag(params["bypass_flag"], "Bypass flag"),
         {:ok, control_command_flag} <-
           flag(params["control_command_flag"], "Control command flag"),
         {:ok, segment_header_flag} <- flag(params["segment_header_flag"], "Segment header flag"),
         {:ok, initial_frame_seq} <-
           integer_in_range(params["initial_frame_seq"], 0, 255, "Initial frame sequence"),
         {:ok, cop1_mode} <- cop1_mode(params["cop1_mode"]),
         {:ok, cop1_timeout_ms} <- positive_integer(params["cop1_timeout_ms"], "COP-1 timeout"),
         {:ok, cop1_max_retransmit} <-
           non_negative_integer(params["cop1_max_retransmit"], "COP-1 max retransmit"),
         {:ok, cop1_window_size} <- cop1_window_size(params["cop1_window_size"]),
         {:ok, simulated_start_delay_ms} <-
           optional_positive_integer(params["simulated_start_delay_ms"], "Simulated start delay"),
         {:ok, simulated_completion_delay_ms} <-
           optional_positive_integer(
             params["simulated_completion_delay_ms"],
             "Simulated completion delay"
           ) do
      {:ok,
       %{
         "transport_profile" => "tc",
         "service_name" => normalize_text(params["service_name"]),
         "frame_size" => frame_size,
         "scid" => scid,
         "vcid" => vcid,
         "bypass_flag" => bypass_flag,
         "control_command_flag" => control_command_flag,
         "segment_header_flag" => segment_header_flag,
         "initial_frame_seq" => initial_frame_seq,
         "cop1_mode" => cop1_mode,
         "cop1_timeout_ms" => cop1_timeout_ms,
         "cop1_max_retransmit" => cop1_max_retransmit,
         "cop1_window_size" => cop1_window_size,
         "simulated_start_delay_ms" => simulated_start_delay_ms,
         "simulated_completion_delay_ms" => simulated_completion_delay_ms
       }
       |> compact()}
    end
  end

  defp transport_configuration(_family_key, _params), do: {:error, "Transport family is invalid."}

  defp family_key("heartbeat_monitor"), do: {:ok, "heartbeat_monitor"}
  defp family_key("uplink_gateway"), do: {:ok, "uplink_gateway"}
  defp family_key(_value), do: {:error, "Transport family is invalid."}

  defp target_scope("path"), do: {:ok, :path}
  defp target_scope("transport"), do: {:ok, :transport}
  defp target_scope(_value), do: {:error, "Target scope is invalid."}

  defp positive_integer(value, label), do: integer_in_range(value, 1, nil, label)
  defp non_negative_integer(value, label), do: integer_in_range(value, 0, nil, label)

  defp optional_positive_integer(value, label) do
    case normalize_text(value) do
      nil -> {:ok, nil}
      _text -> positive_integer(value, label)
    end
  end

  defp optional_integer_in_range(value, min, max, label) do
    case normalize_text(value) do
      nil -> {:ok, nil}
      _text -> integer_in_range(value, min, max, label)
    end
  end

  defp integer_in_range(value, min, nil, label) do
    case parse_integer(value) do
      {:ok, integer} when integer >= min -> {:ok, integer}
      _other -> {:error, "#{label} must be an integer greater than or equal to #{min}."}
    end
  end

  defp integer_in_range(value, min, max, label) do
    case parse_integer(value) do
      {:ok, integer} when integer >= min and integer <= max -> {:ok, integer}
      _other -> {:error, "#{label} must be an integer from #{min} to #{max}."}
    end
  end

  defp flag(value, label) do
    case parse_integer(value) do
      {:ok, flag} when flag in [0, 1] -> {:ok, flag}
      _other -> {:error, "#{label} must be 0 or 1."}
    end
  end

  defp cop1_mode("disabled"), do: {:ok, "disabled"}
  defp cop1_mode("fop"), do: {:ok, "fop"}
  defp cop1_mode(_value), do: {:error, "COP-1 mode is invalid."}

  defp cop1_window_size("1"), do: {:ok, 1}
  defp cop1_window_size(1), do: {:ok, 1}
  defp cop1_window_size(_value), do: {:error, "COP-1 window size must be 1."}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value), do: :error

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp flag_options, do: [{"0", "0"}, {"1", "1"}]
  defp cop1_mode_options, do: [{"Disabled", "disabled"}, {"FOP", "fop"}]

  defp family_value(form), do: form_value(form, :family_key)

  defp preview_configuration(form) do
    family_key = family_value(form)

    params =
      empty_form_params()
      |> Map.merge(%{
        "family_key" => family_key,
        "heartbeat_interval_ms" => form_value(form, :heartbeat_interval_ms),
        "service_name" => form_value(form, :service_name),
        "frame_size" => form_value(form, :frame_size),
        "scid" => form_value(form, :scid),
        "vcid" => form_value(form, :vcid),
        "bypass_flag" => form_value(form, :bypass_flag),
        "control_command_flag" => form_value(form, :control_command_flag),
        "segment_header_flag" => form_value(form, :segment_header_flag),
        "initial_frame_seq" => form_value(form, :initial_frame_seq),
        "cop1_mode" => form_value(form, :cop1_mode),
        "cop1_timeout_ms" => form_value(form, :cop1_timeout_ms),
        "cop1_max_retransmit" => form_value(form, :cop1_max_retransmit),
        "cop1_window_size" => form_value(form, :cop1_window_size),
        "simulated_start_delay_ms" => form_value(form, :simulated_start_delay_ms),
        "simulated_completion_delay_ms" => form_value(form, :simulated_completion_delay_ms)
      })

    case transport_configuration(family_key, params) do
      {:ok, configuration} -> configuration
      {:error, _message} -> %{}
    end
  end

  defp form_value(form, field), do: Form.input_value(form, field)

  defp assign_form_state(%{assigns: %{live_action: :version}} = socket, %{
         "transport_profile_id" => transport_profile_id
       }) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_transport_profile(
           scope.organization_id,
           mission.mission_id,
           transport_profile_id
         ) do
      {:ok, transport_profile} ->
        socket
        |> assign(:page_title, "New Protocol Behavior Version")
        |> assign(:nav_item, :comms)
        |> assign(:transport_profile, transport_profile)
        |> assign(
          :return_to,
          ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{transport_profile_id}"
        )
        |> assign(:back_label, display_name(transport_profile, :transport_profile_id))
        |> assign(:heading, "New Protocol Behavior Version")
        |> assign(:submit_label, "Create New Version")
        |> assign(:form, form_from_transport_profile(transport_profile))

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Transport profile not found.")
        |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors")
    end
  end

  defp assign_form_state(socket, _params) do
    %{current_mission: mission} = socket.assigns

    socket
    |> assign(:page_title, "New Protocol Behavior")
    |> assign(:nav_item, :comms)
    |> assign(:transport_profile, nil)
    |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors")
    |> assign(:back_label, "Protocol Behaviors")
    |> assign(:heading, "New Protocol Behavior")
    |> assign(:submit_label, "Create Protocol Behavior")
    |> assign(:form, empty_form())
  end

  defp save_transport_profile(
         %{assigns: %{live_action: :version, transport_profile: transport_profile}},
         organization_id,
         mission,
         display_name,
         family_key,
         target_scope,
         configuration
       ) do
    Cadence.version_transport_profile(
      organization_id,
      mission.mission_id,
      transport_profile.transport_profile_id,
      %{
        family_key: family_atom(family_key),
        target_scope: target_scope,
        configuration: configuration,
        metadata: %{"display_name" => display_name}
      }
    )
  end

  defp save_transport_profile(
         _socket,
         organization_id,
         mission,
         display_name,
         family_key,
         target_scope,
         configuration
       ) do
    transport_profile =
      TransportProfile.new(%{
        mission_id: mission.mission_id,
        family_key: family_key,
        target_scope: target_scope,
        configuration: configuration,
        metadata: %{"display_name" => display_name}
      })

    Cadence.persist_transport_profile(organization_id, transport_profile)
  end

  defp transport_profile_return_path(
         %{assigns: %{live_action: :version, transport_profile: profile}},
         mission_id
       ) do
    ~p"/missions/#{mission_id}/comms/protocol-behaviors/#{profile.transport_profile_id}"
  end

  defp transport_profile_return_path(_socket, mission_id) do
    ~p"/missions/#{mission_id}/comms/protocol-behaviors"
  end

  defp string_value(nil), do: ""
  defp string_value(value), do: to_string(value)

  defp family_atom("heartbeat_monitor"), do: :heartbeat_monitor
  defp family_atom("uplink_gateway"), do: :uplink_gateway
end
