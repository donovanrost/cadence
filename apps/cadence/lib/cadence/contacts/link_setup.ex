defmodule Cadence.Contacts.LinkSetup do
  @moduledoc """
  Creates shared links and applies reusable link templates to spacecraft.
  """

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.LinkAssignmentStore
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Contacts.TransportProfile
  alias Cadence.Repo
  alias Cadence.SourceEndpoints

  @type shared_link_direction :: :downlink | :uplink | :bidirectional

  @spec create_shared_link(binary(), binary(), map()) ::
          {:ok,
           %{
             provider: ProviderProfile.t(),
             transport: TransportProfile.t() | nil,
             path_templates: [PathTemplate.t()]
           }}
          | {:error, term()}
  def create_shared_link(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    with {:ok, context} <- shared_link_context(organization_id, mission_id, attrs) do
      Repo.transaction(fn ->
        context
        |> persist_shared_link_records()
        |> unwrap_transaction_result()
      end)
    end
  end

  @spec apply_link_template(binary(), binary(), PathTemplate.t(), [map()], map()) ::
          {:ok,
           %{
             rows: [map()],
             applied_count: non_neg_integer(),
             skipped_count: non_neg_integer(),
             failed_count: non_neg_integer()
           }}
  def apply_link_template(
        organization_id,
        mission_id,
        %PathTemplate{} = source_template,
        spacecraft,
        attrs
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft) and
             is_map(attrs) do
    source_endpoints = SourceEndpoints.list_source_endpoints(organization_id, mission_id)
    path_templates = PathTemplateStore.list(organization_id, mission_id)
    link_assignments = LinkAssignmentStore.list(organization_id, mission_id)

    result_rows =
      Enum.map(spacecraft, fn spacecraft ->
        apply_link_template_row(
          organization_id,
          mission_id,
          source_template,
          spacecraft,
          attrs,
          source_endpoints,
          path_templates,
          link_assignments
        )
      end)

    {:ok,
     %{
       rows: result_rows,
       applied_count: Enum.count(result_rows, &(&1.kind == :applied)),
       skipped_count: Enum.count(result_rows, &(&1.kind == :skipped)),
       failed_count: Enum.count(result_rows, &(&1.kind == :failed))
     }}
  end

  defp shared_link_context(organization_id, mission_id, attrs) do
    with {:ok, display_name} <- required_text(attrs["display_name"], "Link name is required."),
         {:ok, direction} <- shared_link_direction(attrs["direction"]),
         {:ok, selection_role} <- selection_role(attrs["selection_role"]),
         {:ok, provider_configuration} <- provider_configuration(attrs, direction),
         {:ok, heartbeat_enabled} <- boolean(attrs["heartbeat_enabled"]),
         {:ok, heartbeat_interval_ms} <-
           heartbeat_interval(attrs["heartbeat_interval_ms"], heartbeat_enabled) do
      {:ok,
       %{
         organization_id: organization_id,
         mission_id: mission_id,
         display_name: display_name,
         direction: direction,
         selection_role: selection_role,
         provider_configuration: provider_configuration,
         heartbeat_enabled: heartbeat_enabled,
         heartbeat_interval_ms: heartbeat_interval_ms,
         attrs: attrs
       }}
    end
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result({:error, reason}), do: Repo.rollback(reason)

  defp persist_shared_link_records(context) do
    %{
      organization_id: organization_id,
      mission_id: mission_id,
      display_name: display_name,
      direction: direction,
      selection_role: selection_role,
      provider_configuration: provider_configuration,
      heartbeat_enabled: heartbeat_enabled,
      heartbeat_interval_ms: heartbeat_interval_ms,
      attrs: attrs
    } = context

    with {:ok, provider} <-
           persist_shared_link_provider(
             organization_id,
             mission_id,
             display_name,
             provider_configuration
           ),
         {:ok, transport} <-
           maybe_persist_heartbeat(
             organization_id,
             mission_id,
             display_name,
             heartbeat_enabled,
             heartbeat_interval_ms
           ),
         {:ok, path_templates} <-
           persist_shared_link_path_templates(
             organization_id,
             mission_id,
             display_name,
             direction,
             selection_role,
             provider,
             transport,
             attrs
           ) do
      {:ok, %{provider: provider, transport: transport, path_templates: path_templates}}
    end
  end

  defp persist_shared_link_provider(organization_id, mission_id, display_name, configuration) do
    provider =
      ProviderProfile.new(%{
        mission_id: mission_id,
        adapter_key: :tcp_socket,
        configuration: configuration,
        metadata: %{"display_name" => "#{display_name} Provider"}
      })

    ProfileStore.persist_provider_profile(organization_id, provider)
  end

  defp maybe_persist_heartbeat(
         organization_id,
         mission_id,
         display_name,
         true,
         heartbeat_interval_ms
       ) do
    transport =
      TransportProfile.new(%{
        mission_id: mission_id,
        family_key: :heartbeat_monitor,
        target_scope: :path,
        configuration: %{"heartbeat_interval_ms" => heartbeat_interval_ms},
        metadata: %{"display_name" => "#{display_name} Heartbeat"}
      })

    ProfileStore.persist_transport_profile(organization_id, transport)
  end

  defp maybe_persist_heartbeat(_organization_id, _mission_id, _display_name, false, _interval) do
    {:ok, nil}
  end

  defp persist_shared_link_path_templates(
         organization_id,
         mission_id,
         display_name,
         direction,
         selection_role,
         provider,
         transport,
         attrs
       ) do
    direction
    |> path_directions()
    |> Enum.reduce_while({:ok, []}, fn path_direction, {:ok, path_templates} ->
      path_template =
        PathTemplate.new(%{
          mission_id: mission_id,
          direction: path_direction,
          selection_role: selection_role,
          source_endpoint_ref: nil,
          provider_path_ref: provider_path_ref(attrs, display_name, path_direction),
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          transport_profile_refs: transport_refs(transport),
          metadata: %{
            "display_name" => path_display_name(display_name, direction, path_direction),
            "created_from_link_builder" => true
          }
        })

      case PathTemplateStore.persist(organization_id, path_template) do
        {:ok, path_template} -> {:cont, {:ok, [path_template | path_templates]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, path_templates} -> {:ok, Enum.reverse(path_templates)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_link_template_row(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         source_endpoints,
         path_templates,
         link_assignments
       ) do
    endpoint_refs = endpoint_refs_for_spacecraft(spacecraft, source_endpoints)

    cond do
      is_nil(spacecraft.scid) ->
        application_row(
          spacecraft,
          :skipped,
          :info,
          "Skipped",
          "Set SCID before Cadence can generate a spacecraft telemetry identity."
        )

      assigned_path_exists?(endpoint_refs, link_assignments, source_template) ->
        application_row(
          spacecraft,
          :skipped,
          :info,
          "Skipped",
          "#{source_template.direction |> Atom.to_string() |> String.upcase()} #{human_atom(source_template.selection_role)} link already exists."
        )

      true ->
        apply_available_link_template_row(
          organization_id,
          mission_id,
          source_template,
          spacecraft,
          attrs,
          path_templates,
          link_assignments
        )
    end
  end

  defp apply_available_link_template_row(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         path_templates,
         link_assignments
       ) do
    provider_path_ref =
      render_pattern(attrs["provider_path_ref_pattern"], spacecraft, source_template.direction)

    if provider_path_ref_collision?(provider_path_ref, path_templates, link_assignments) do
      application_row(
        spacecraft,
        :skipped,
        :attention,
        "Conflict",
        "Provider path ref #{provider_path_ref} is already used by another link template."
      )
    else
      persist_spacecraft_link_assignment(
        organization_id,
        mission_id,
        source_template,
        spacecraft,
        attrs,
        provider_path_ref
      )
    end
  end

  defp persist_spacecraft_link_assignment(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         provider_path_ref
       ) do
    with {:ok, endpoint} <-
           SourceEndpoints.ensure_managed_source_endpoint(organization_id, spacecraft),
         {:ok, _assignment} <-
           LinkAssignmentStore.persist(
             organization_id,
             LinkAssignment.new(%{
               mission_id: mission_id,
               spacecraft_id: spacecraft.spacecraft_id,
               path_template_id: source_template.path_template_id,
               path_template_version: source_template.version,
               direction: source_template.direction,
               selection_role: source_template.selection_role,
               source_endpoint_ref: endpoint.source_endpoint_id,
               provider_path_ref: provider_path_ref,
               provider_profile_refs: source_template.provider_profile_refs,
               transport_profile_refs: source_template.transport_profile_refs,
               metadata:
                 Map.merge(source_template.metadata, %{
                   "display_name" =>
                     render_pattern(
                       attrs["display_name_pattern"],
                       spacecraft,
                       source_template.direction
                     ),
                   "applied_from_template_ui" => true,
                   "source_path_template_id" => source_template.path_template_id,
                   "source_path_template_version" => source_template.version
                 })
             })
           ) do
      application_row(spacecraft, :applied, :ready, "Applied", "Link assignment was created.")
    else
      {:error, reason} ->
        application_row(spacecraft, :failed, :blocked, "Failed", inspect(reason))
    end
  end

  defp application_row(spacecraft, kind, status, label, detail) do
    %{
      id: spacecraft.spacecraft_id,
      spacecraft: spacecraft,
      kind: kind,
      status: status,
      label: label,
      detail: detail
    }
  end

  defp endpoint_refs_for_spacecraft(spacecraft, source_endpoints) do
    managed_id = "spacecraft_runtime:" <> spacecraft.spacecraft_id

    endpoint_refs =
      Enum.flat_map(source_endpoints, fn endpoint ->
        if endpoint.spacecraft_id == spacecraft.spacecraft_id do
          [endpoint.source_endpoint_id]
        else
          []
        end
      end)

    Enum.uniq([managed_id | endpoint_refs])
  end

  defp assigned_path_exists?(endpoint_refs, link_assignments, source_template) do
    Enum.any?(link_assignments, fn assignment ->
      assignment.source_endpoint_ref in endpoint_refs and
        assignment.direction == source_template.direction and
        assignment.selection_role == source_template.selection_role and
        assignment.provider_profile_refs != []
    end)
  end

  defp provider_path_ref_collision?(nil, _path_templates, _link_assignments), do: false

  defp provider_path_ref_collision?(provider_path_ref, path_templates, link_assignments) do
    Enum.any?(path_templates, &(&1.provider_path_ref == provider_path_ref)) or
      Enum.any?(link_assignments, &(&1.provider_path_ref == provider_path_ref))
  end

  defp provider_configuration(attrs, direction) do
    with {:ok, mode} <- tcp_mode(attrs["tcp_mode"]),
         {:ok, provider_direction} <- provider_direction(direction),
         {:ok, host} <- required_text(attrs["host"], "Host is required."),
         {:ok, port} <- port(attrs["port"]),
         {:ok, framing_mode} <- framing_mode(attrs["framing_mode"]),
         {:ok, frame_size} <- frame_size(attrs["frame_size"], framing_mode),
         {:ok, tls_enabled} <- boolean(attrs["tls_enabled"]) do
      {:ok,
       %{
         "adapter" => "tcp_socket",
         "mode" => mode,
         "direction" => provider_direction,
         "host" => host,
         "port" => port,
         "framing" => compact(%{"mode" => framing_mode, "fixed_message_bytes" => frame_size}),
         "tls" => %{"enabled" => tls_enabled},
         "reconnect" => reconnect_configuration(mode)
       }
       |> maybe_put_fixed_message_bytes(frame_size)}
    end
  end

  defp required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

  defp render_pattern(pattern, spacecraft, direction) do
    (normalize_text(pattern) || "{spacecraft_name} {direction}")
    |> String.replace("{spacecraft_id}", spacecraft.spacecraft_id)
    |> String.replace("{spacecraft_name}", spacecraft.display_name)
    |> String.replace("{scid}", Integer.to_string(spacecraft.scid))
    |> String.replace("{direction}", Atom.to_string(direction))
  end

  defp heartbeat_interval(_value, false), do: {:ok, nil}

  defp heartbeat_interval(value, true) do
    case parse_integer(value) do
      {:ok, interval} when interval > 0 -> {:ok, interval}
      _other -> {:error, "Heartbeat interval must be a positive integer."}
    end
  end

  defp tcp_mode("listen"), do: {:ok, "listen"}
  defp tcp_mode("connect"), do: {:ok, "connect"}
  defp tcp_mode(_value), do: {:error, "TCP mode is invalid."}

  defp shared_link_direction("downlink"), do: {:ok, :downlink}
  defp shared_link_direction("uplink"), do: {:ok, :uplink}
  defp shared_link_direction("bidirectional"), do: {:ok, :bidirectional}
  defp shared_link_direction(_value), do: {:error, "Direction is invalid."}

  defp provider_direction(:downlink), do: {:ok, "downlink"}
  defp provider_direction(:uplink), do: {:ok, "uplink"}
  defp provider_direction(:bidirectional), do: {:ok, "bidirectional"}

  defp selection_role("selected"), do: {:ok, :selected}
  defp selection_role("candidate"), do: {:ok, :candidate}
  defp selection_role("contributing"), do: {:ok, :contributing}
  defp selection_role(_value), do: {:error, "Assignment role is invalid."}

  defp port(value) do
    case parse_integer(value) do
      {:ok, port} when port >= 1 and port <= 65_535 -> {:ok, port}
      _other -> {:error, "Port must be an integer from 1 to 65535."}
    end
  end

  defp framing_mode("raw"), do: {:ok, "raw"}
  defp framing_mode("fixed_size"), do: {:ok, "fixed_size"}
  defp framing_mode("line_delimited"), do: {:ok, "line_delimited"}
  defp framing_mode(_value), do: {:error, "Framing mode is invalid."}

  defp frame_size(value, "fixed_size") do
    case parse_integer(value) do
      {:ok, frame_size} when frame_size > 0 -> {:ok, frame_size}
      _other -> {:error, "Fixed frame size must be a positive integer."}
    end
  end

  defp frame_size(_value, _framing_mode), do: {:ok, nil}

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_value), do: {:error, "Boolean option is invalid."}

  defp reconnect_configuration("connect"), do: %{"policy" => "always"}
  defp reconnect_configuration("listen"), do: %{"policy" => "on_disconnect"}

  defp maybe_put_fixed_message_bytes(configuration, nil), do: configuration

  defp maybe_put_fixed_message_bytes(configuration, frame_size) do
    Map.put(configuration, "fixed_message_bytes", frame_size)
  end

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value), do: :error

  defp path_directions(:bidirectional), do: [:downlink, :uplink]
  defp path_directions(direction), do: [direction]

  defp path_display_name(display_name, :bidirectional, direction) do
    "#{display_name} #{human_atom(direction)}"
  end

  defp path_display_name(display_name, _builder_direction, _path_direction), do: display_name

  defp provider_path_ref(attrs, display_name, direction) do
    case normalize_text(attrs["provider_path_ref"]) do
      nil -> "#{slug(display_name)}-#{Atom.to_string(direction)}"
      value -> value
    end
  end

  defp transport_refs(nil), do: []

  defp transport_refs(transport) do
    [%{"transport_profile_id" => transport.transport_profile_id, "version" => transport.version}]
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp human_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end
end
