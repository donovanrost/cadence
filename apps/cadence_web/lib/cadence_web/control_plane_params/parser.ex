defmodule CadenceWeb.ControlPlaneParams.Parser do
  @moduledoc false

  @service_identity_lifecycle_states [:active, :disabled]
  @direction_values [:uplink, :downlink]
  @selection_role_values [:selected, :candidate, :contributing]
  @transport_target_scope_values [:path, :transport]

  def capabilities(params, default) when is_map(params) and is_list(default) do
    case Map.get(params, "capabilities", default) do
      values when is_list(values) ->
        reduce_ok(values, &normalize_capability/1)

      _other ->
        {:error, {:invalid_param, "capabilities", :list}}
    end
  end

  def service_identity_lifecycle_state(params) when is_map(params) do
    allowed_atom_param(params, "lifecycle_state", :active, @service_identity_lifecycle_states)
  end

  def required_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:invalid_param, key, :required}}
    end
  end

  def required_json_term(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> {:ok, value}
    end
  end

  def string_value(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  def required_integer(params, key) do
    case integer_from_value(Map.get(params, key)) do
      {:ok, integer} -> {:ok, integer}
      :error -> {:error, {:invalid_param, key, :integer}}
    end
  end

  def optional_positive_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  def required_datetime(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        datetime_from_value(value) |> wrap_datetime_result(key)

      _missing ->
        {:error, {:invalid_param, key, :required}}
    end
  end

  def optional_datetime(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> datetime_from_value(value) |> wrap_datetime_result(key)
    end
  end

  def optional_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> wrap_integer_result(key)
    end
  end

  def positive_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  def non_neg_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:ok, default}
      value -> integer_from_value(value) |> ensure_non_neg_integer(key)
    end
  end

  def wrap_integer_result({:ok, integer}, _key), do: {:ok, integer}
  def wrap_integer_result(:error, key), do: {:error, {:invalid_param, key, :integer}}

  def wrap_datetime_result({:ok, datetime}, _key), do: {:ok, datetime}
  def wrap_datetime_result(:error, key), do: {:error, {:invalid_param, key, :datetime}}

  def ensure_positive_integer({:ok, integer}, _key) when integer > 0, do: {:ok, integer}

  def ensure_positive_integer(_result, key),
    do: {:error, {:invalid_param, key, :positive_integer}}

  def ensure_non_neg_integer({:ok, integer}, _key) when integer >= 0, do: {:ok, integer}
  def ensure_non_neg_integer(_result, key), do: {:error, {:invalid_param, key, :non_neg_integer}}

  def integer_from_value(value) when is_integer(value), do: {:ok, value}

  def integer_from_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  def integer_from_value(_value), do: :error

  def datetime_from_value(%DateTime{} = datetime), do: {:ok, datetime}

  def datetime_from_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> :error
    end
  end

  def datetime_from_value(_value), do: :error

  def existing_atom(params, key, default) do
    case Map.get(params, key, default) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) ->
        try do
          {:ok, String.to_existing_atom(value)}
        rescue
          ArgumentError -> {:error, {:invalid_param, key, :unknown_atom}}
        end

      _other ->
        {:error, {:invalid_param, key, :atom}}
    end
  end

  def maybe_existing_atom(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      existing_atom(params, key, nil)
    else
      {:ok, nil}
    end
  end

  def allowed_atom_param(params, key, default, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    parse_allowed_atom(Map.get(params, key, default), key, allowed)
  end

  def optional_allowed_atom_param(params, key, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    parse_allowed_atom(Map.get(params, key), key, allowed)
  end

  def optional_allowed_atom_list(params, key, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        reduce_ok(values, &parse_allowed_atom(&1, key, allowed))

      _other ->
        {:error, {:invalid_param, key, :list}}
    end
  end

  def required_allowed_atom_param(params, key, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> parse_allowed_atom(value, key, allowed)
    end
  end

  def parse_allowed_atom(nil, _key, _allowed), do: {:ok, nil}

  def parse_allowed_atom(value, key, allowed) when is_atom(value) do
    if Enum.member?(allowed, value) do
      {:ok, value}
    else
      {:error, {:invalid_param, key, :unknown_atom}}
    end
  end

  def parse_allowed_atom(value, key, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:invalid_param, key, :unknown_atom}}
      atom -> {:ok, atom}
    end
  end

  def parse_allowed_atom(_value, key, _allowed),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  def normalize_capability(value) do
    case value do
      :organization_admin -> {:ok, :organization_admin}
      "organization_admin" -> {:ok, :organization_admin}
      :mission_admin -> {:ok, :mission_admin}
      "mission_admin" -> {:ok, :mission_admin}
      _other -> {:error, {:invalid_param, "capabilities", :unknown_atom}}
    end
  end

  def required_catalog_family(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> catalog_family_from_value(value, key)
    end
  end

  def optional_catalog_family(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> catalog_family_from_value(value, key)
    end
  end

  def catalog_family_from_value(:telemetry, _key), do: {:ok, :telemetry}
  def catalog_family_from_value("telemetry", _key), do: {:ok, :telemetry}
  def catalog_family_from_value(:command, _key), do: {:ok, :command}
  def catalog_family_from_value("command", _key), do: {:ok, :command}
  def catalog_family_from_value(:combined, _key), do: {:ok, :combined}
  def catalog_family_from_value("combined", _key), do: {:ok, :combined}

  def catalog_family_from_value(_other, key),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  def optional_import_run_status(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> import_run_status_from_value(value, key)
    end
  end

  def import_run_status_from_value(:running, _key), do: {:ok, :running}
  def import_run_status_from_value("running", _key), do: {:ok, :running}
  def import_run_status_from_value(:completed, _key), do: {:ok, :completed}
  def import_run_status_from_value("completed", _key), do: {:ok, :completed}
  def import_run_status_from_value(:failed, _key), do: {:ok, :failed}
  def import_run_status_from_value("failed", _key), do: {:ok, :failed}

  def import_run_status_from_value(_other, key),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  def mission_event_cursor(params) when is_map(params) do
    with {:ok, occurred_at} <- optional_datetime(params, "cursor_occurred_at") do
      case {occurred_at, string_value(params, "cursor_mission_event_id")} do
        {nil, nil} ->
          {:ok, nil}

        {nil, _event_id} ->
          {:error, {:invalid_param, "cursor_occurred_at", :required}}

        {%DateTime{} = cursor_time, nil} ->
          {:ok, %{occurred_at: cursor_time}}

        {%DateTime{} = cursor_time, event_id} ->
          {:ok, %{occurred_at: cursor_time, mission_event_id: event_id}}
      end
    end
  end

  def telemetry_history_order(params) when is_map(params) do
    case Map.get(params, "order") do
      nil -> {:ok, nil}
      :asc -> {:ok, :asc}
      "asc" -> {:ok, :asc}
      :desc -> {:ok, :desc}
      "desc" -> {:ok, :desc}
      _other -> {:error, {:invalid_param, "order", :unknown_atom}}
    end
  end

  def string_or_string_list(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) and value != "" ->
        {:ok, value}

      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_or_string_list}}
    end
  end

  def clock_mode(params) when is_map(params) do
    case Map.get(params, "clock_mode") do
      nil -> {:ok, nil}
      :live -> {:ok, :live}
      "live" -> {:ok, :live}
      :replay -> {:ok, :replay}
      "replay" -> {:ok, :replay}
      _other -> {:error, {:invalid_param, "clock_mode", :unknown_atom}}
    end
  end

  def direction(params) when is_map(params) do
    required_allowed_atom_param(params, "direction", @direction_values)
  end

  def optional_direction(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @direction_values)
  end

  def optional_selection_role(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @selection_role_values)
  end

  def selection_role(params) when is_map(params) do
    allowed_atom_param(params, "selection_role", :candidate, @selection_role_values)
  end

  def link_template_application_target_mode(params) when is_map(params) do
    case Map.get(params, "target_mode", "matching") do
      "matching" -> {:ok, "matching"}
      "selected" -> {:ok, "selected"}
      _other -> {:error, {:invalid_param, "target_mode", :unknown_atom}}
    end
  end

  def transport_target_scope(params) when is_map(params) do
    allowed_atom_param(params, "target_scope", :path, @transport_target_scope_values)
  end

  def validate_password_confirmation(password, password_confirmation)
      when is_binary(password) and is_binary(password_confirmation) do
    if password == password_confirmation do
      :ok
    else
      {:error, {:invalid_param, "password_confirmation", :mismatch}}
    end
  end

  def optional_transport_target_scope(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @transport_target_scope_values)
  end

  def transport_family_key(params) when is_map(params) do
    case Map.get(params, "family_key") do
      nil -> {:error, {:invalid_param, "family_key", :required}}
      value when is_atom(value) -> {:ok, value}
      value when is_binary(value) -> existing_atom(%{"family_key" => value}, "family_key", nil)
      _other -> {:error, {:invalid_param, "family_key", :atom}}
    end
  end

  def optional_transport_family_key(params, key) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) ->
        existing_atom(%{key => value}, key, nil)

      _other ->
        {:error, {:invalid_param, key, :atom}}
    end
  end

  def map_value(params, key) do
    case Map.get(params, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  def optional_map(params, key), do: optional_map(params, key, nil)

  def optional_map(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:ok, nil}
      value when is_map(value) -> {:ok, value}
      _other -> {:error, {:invalid_param, key, :map}}
    end
  end

  def list_value(params, key) do
    case Map.get(params, key, []) do
      value when is_list(value) -> value
      _other -> []
    end
  end

  def required_string_list(params, key) do
    case Map.get(params, key) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_list}}
    end
  end

  def optional_string_list(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_list}}
    end
  end

  def optional_patch_string_list(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      optional_string_list(params, key)
    else
      {:ok, nil}
    end
  end

  def optional_versioned_ref_list(params, key, id_key)
      when is_map(params) and is_binary(key) and is_binary(id_key) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      refs when is_list(refs) ->
        reduce_ok(refs, &versioned_ref(&1, id_key))

      _other ->
        {:error, {:invalid_param, key, :list}}
    end
  end

  def optional_ref_list(params, key, id_key)
      when is_map(params) and is_binary(key) and is_binary(id_key) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      refs when is_list(refs) ->
        reduce_ok(refs, &unversioned_ref(&1, id_key))

      _other ->
        {:error, {:invalid_param, key, :list}}
    end
  end

  def optional_patch_versioned_ref_list(params, key, id_key)
      when is_map(params) and is_binary(key) and is_binary(id_key) do
    if Map.has_key?(params, key) do
      optional_versioned_ref_list(params, key, id_key)
    else
      {:ok, nil}
    end
  end

  def reduce_ok(values, mapper) when is_list(values) and is_function(mapper, 1) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case mapper.(value) do
        {:ok, normalized_value} -> {:cont, {:ok, acc ++ [normalized_value]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def versioned_ref(ref, id_key) when is_map(ref) and is_binary(id_key) do
    ref_id =
      case Map.get(ref, id_key) do
        value when is_binary(value) and value != "" -> value
        _other -> nil
      end

    with {:ok, version} <- positive_integer(ref, "version", 1),
         true <- is_binary(ref_id) and ref_id != "" do
      {:ok, %{id_key => ref_id, "version" => version}}
    else
      false -> {:error, {:invalid_param, id_key, :required}}
      {:error, reason} -> {:error, reason}
    end
  end

  def unversioned_ref(ref, id_key) when is_map(ref) and is_binary(id_key) do
    case Map.get(ref, id_key) do
      value when is_binary(value) and value != "" -> {:ok, %{id_key => value}}
      _other -> {:error, {:invalid_param, id_key, :required}}
    end
  end

  def optional_patch_map(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      optional_map(params, key, %{})
    else
      {:ok, nil}
    end
  end

  def required_packet_binary(params) when is_map(params) do
    packet_hex = string_value(params, "packet_hex")
    packet_base64 = string_value(params, "packet_base64")

    cond do
      is_binary(packet_hex) and is_binary(packet_base64) ->
        {:error, {:invalid_param, "packet_hex", :mutually_exclusive_with_packet_base64}}

      is_binary(packet_hex) ->
        decode_packet_hex(packet_hex)

      is_binary(packet_base64) ->
        decode_packet_base64(packet_base64)

      true ->
        {:error, {:invalid_param, "packet_hex_or_packet_base64", :required}}
    end
  end

  def required_frame_binary(params) when is_map(params) do
    frame_hex = string_value(params, "frame_hex")
    frame_base64 = string_value(params, "frame_base64")

    cond do
      is_binary(frame_hex) and is_binary(frame_base64) ->
        {:error, {:invalid_param, "frame_hex", :mutually_exclusive_with_frame_base64}}

      is_binary(frame_hex) ->
        decode_packet_hex(frame_hex)

      is_binary(frame_base64) ->
        decode_packet_base64(frame_base64)

      true ->
        {:error, {:invalid_param, "frame_hex_or_frame_base64", :required}}
    end
  end

  def decode_packet_hex(packet_hex) when is_binary(packet_hex) do
    normalized_hex =
      packet_hex
      |> String.replace(~r/[\s_]/u, "")
      |> String.replace_prefix("0x", "")
      |> String.replace_prefix("0X", "")

    case Base.decode16(normalized_hex, case: :mixed) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_hex", :hex}}
    end
  end

  def decode_packet_base64(packet_base64) when is_binary(packet_base64) do
    normalized_base64 = String.replace(packet_base64, ~r/\s+/u, "")

    case Base.decode64(normalized_base64) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_base64", :base64}}
    end
  end

  def maybe_put_opt(opts, _key, nil), do: opts
  def maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  def maybe_put_attr(map, _key, nil), do: map
  def maybe_put_attr(map, key, value), do: Map.put(map, key, value)

  def maybe_string_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      string_value(params, key) || existing_value
    else
      existing_value
    end
  end

  def maybe_nullable_string_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      string_value(params, key)
    else
      existing_value
    end
  end

  def maybe_map_value(params, key, existing_value) do
    if Map.has_key?(params, key) do
      map_value(params, key)
    else
      existing_value
    end
  end

  def maybe_map_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      optional_map(params, key, existing_value)
    else
      {:ok, existing_value}
    end
  end

  def optional_patch_nullable_string(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      {:ok, string_value(params, key)}
    else
      {:ok, nil}
    end
  end

  def maybe_non_neg_integer(params, key, existing_value) do
    if Map.has_key?(params, key) do
      non_neg_integer(params, key, existing_value)
    else
      {:ok, existing_value}
    end
  end

  def maybe_optional_datetime(params, key, existing_value) do
    if Map.has_key?(params, key) do
      optional_datetime(params, key)
    else
      {:ok, existing_value}
    end
  end

  def resolve_spacecraft_id(params, nil), do: {:ok, string_value(params, "spacecraft_id")}

  def resolve_spacecraft_id(params, scoped_spacecraft_id) when is_binary(scoped_spacecraft_id) do
    case string_value(params, "spacecraft_id") do
      nil -> {:ok, scoped_spacecraft_id}
      ^scoped_spacecraft_id -> {:ok, scoped_spacecraft_id}
      _other -> {:error, :scope_mismatch}
    end
  end

  def resolve_scoped_command_stage_id(params, scoped_command_stage_id)
      when is_binary(scoped_command_stage_id) do
    case string_value(params, "command_stage_id") do
      nil -> {:ok, scoped_command_stage_id}
      ^scoped_command_stage_id -> {:ok, scoped_command_stage_id}
      _other -> {:error, :scope_mismatch}
    end
  end
end
