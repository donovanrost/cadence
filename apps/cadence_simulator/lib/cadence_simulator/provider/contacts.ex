defmodule CadenceSimulator.Provider.Contacts do
  @moduledoc "Provider Contract v1 Contact creation, lookup, recovery, and cancellation."

  alias CadenceSimulator.Provider.{
    ContactLifecycle,
    DeliveryProfiles,
    Ids,
    Opportunities,
    ServiceProfiles,
    Store
  }

  @terminal_statuses ["rejected", "canceled", "completed", "failed"]
  @forbidden_request_keys ["host", "port", "tm_frame_size", "definitions_path", "data_plane"]
  @required_request_keys [
    "opportunity_ref",
    "spacecraft_ref",
    "service_profile_ref",
    "delivery_profile_ref",
    "client_reference"
  ]
  @internal_keys [
    "run_id",
    "configuration_snapshot",
    "service_profile_snapshot",
    "delivery_profile_snapshot",
    "idempotency_key",
    "modification_history",
    "result"
  ]
  @modification_fields [
    "starts_at",
    "ends_at",
    "ground_station_ref",
    "antenna_or_service_pool_ref"
  ]
  @modification_request_keys ["client_reference", "expected_revision", "reason"] ++
                               @modification_fields

  @spec create(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(run, attrs, opts \\ []) when is_map(run) and is_map(attrs) do
    idempotency_key = Keyword.get(opts, :idempotency_key)
    request_id = Keyword.get(opts, :request_id)

    with :ok <- reject_raw_transport(attrs),
         {:ok, request} <- normalize_request(attrs),
         {:ok, opportunity} <- Opportunities.fetch(run, request["opportunity_ref"]),
         :ok <- validate_opportunity(opportunity, request),
         {:ok, service_profile} <- fetch_service_profile(run, request["service_profile_ref"]),
         {:ok, delivery_profile} <-
           DeliveryProfiles.fetch_internal(run, request["delivery_profile_ref"]),
         :ok <- validate_delivery_profile(delivery_profile, service_profile),
         :ok <- validate_idempotency_key(run, idempotency_key) do
      create_or_recover(
        run,
        request,
        opportunity,
        service_profile,
        delivery_profile,
        idempotency_key,
        request_id
      )
    end
  end

  @spec fetch(map(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(run, id) when is_binary(id) do
    expected_run_id = run["id"]

    case fetch_internal(id) do
      {:ok, %{"run_id" => ^expected_run_id} = contact} ->
        {:ok, public(contact)}

      _other ->
        {:error, :not_found}
    end
  end

  @spec fetch_internal(binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch_internal(id), do: Store.fetch(:contact, id)

  @spec list(map(), map()) :: [map()]
  def list(run, filters \\ %{}) do
    Store.list(:contact)
    |> Enum.filter(fn contact ->
      contact["run_id"] == run["id"] and
        Enum.all?(["client_reference", "status"], fn key ->
          filter = filters[key]
          is_nil(filter) or filter == "" or contact[key] == filter
        end)
    end)
    |> Enum.map(&public/1)
  end

  @spec list_internal(map()) :: [map()]
  def list_internal(filters \\ %{}) do
    Store.list(:contact)
    |> Enum.filter(fn contact ->
      Enum.all?(["run_id", "client_reference", "status"], fn key ->
        filter = filters[key]
        is_nil(filter) or filter == "" or contact[key] == filter
      end)
    end)
  end

  @spec cancel(map(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel(run, id, opts \\ []) do
    with {:ok, contact} <- fetch_internal(id),
         true <- contact["run_id"] == run["id"],
         false <- terminal_status?(contact["status"]) do
      delivery_status =
        if contact["delivery"]["status"] in ["failed", "ended"],
          do: contact["delivery"]["status"],
          else: "ended"

      changes = %{
        "status" => "canceled",
        "status_reason" => "operator_canceled",
        "pass_phase" => "closed",
        "delivery" => Map.put(contact["delivery"], "status", delivery_status)
      }

      with {:ok, updated} <-
             ContactLifecycle.update(contact, changes, Keyword.get(opts, :request_id)) do
        {:ok, public(updated)}
      end
    else
      false -> {:error, :not_found}
      true -> {:error, {:conflict, "contact is already terminal"}}
      error -> error
    end
  end

  @spec modify(map(), binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def modify(run, id, attrs, opts \\ []) when is_map(run) and is_binary(id) and is_map(attrs) do
    idempotency_key = Keyword.get(opts, :idempotency_key)

    with {:ok, contact} <- fetch_internal(id),
         true <- contact["run_id"] == run["id"],
         :ok <- ensure_modifiable(contact),
         {:ok, request} <- normalize_modification_request(contact, attrs),
         :ok <- validate_idempotency_key(run, idempotency_key) do
      modify_or_recover(
        run,
        contact,
        request,
        idempotency_key,
        Keyword.get(opts, :request_id)
      )
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  @spec public(map()) :: map()
  def public(contact), do: Map.drop(contact, @internal_keys)

  def terminal_status?(status), do: status in @terminal_statuses

  defp create_or_recover(
         run,
         request,
         opportunity,
         service_profile,
         delivery_profile,
         idempotency_key,
         request_id
       ) do
    case existing_contact(run, request, idempotency_key) do
      nil ->
        with :ok <- ensure_capacity(run, opportunity),
             contact <-
               build_contact(
                 run,
                 request,
                 opportunity,
                 service_profile,
                 delivery_profile,
                 idempotency_key
               ),
             {:ok, stored} <- ContactLifecycle.create(contact, request_id) do
          {:ok, public(stored)}
        end

      existing ->
        if existing["configuration_snapshot"] == request do
          {:ok, public(existing)}
        else
          {:error, {:conflict, "idempotency identity already has a different Contact request"}}
        end
    end
  end

  defp build_contact(
         run,
         request,
         opportunity,
         service_profile,
         delivery_profile,
         idempotency_key
       ) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    rejected? = scheduling_rejected?(run, opportunity)

    delivery =
      delivery_descriptor(delivery_profile, opportunity)
      |> Map.put("status", if(rejected?, do: "failed", else: "pending"))

    %{
      "id" => Ids.new("contact"),
      "run_id" => run["id"],
      "client_reference" => request["client_reference"],
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "ground_station_ref" => opportunity["ground_station_ref"],
      "antenna_or_service_pool_ref" => opportunity["antenna_or_service_pool_ref"],
      "service_profile_ref" => service_profile["id"],
      "delivery_profile_ref" => delivery_profile["id"],
      "revision" => 1,
      "starts_at" => opportunity["starts_at"],
      "ends_at" => opportunity["ends_at"],
      "status" => if(rejected?, do: "rejected", else: "pending"),
      "pass_phase" => "scheduled",
      "delivery" => delivery,
      "status_reason" => if(rejected?, do: "simulated_scheduling_rejection", else: nil),
      "tags" => request["tags"],
      "extensions" => %{"synthetic" => true},
      "configuration_snapshot" => request,
      "service_profile_snapshot" => service_profile,
      "delivery_profile_snapshot" => delivery_profile,
      "idempotency_key" => idempotency_key,
      "modification_history" => [],
      "result" => nil,
      "created_at" => now,
      "updated_at" => now
    }
  end

  defp delivery_descriptor(profile, opportunity) do
    framing = profile["framing"] || %{}

    %{
      "status" => "pending",
      "direction" => profile["direction"],
      "delivery_kind" => profile["delivery_kind"],
      "mode" => get_in(profile, ["target", "mode"]),
      "protocol" => get_in(profile, ["target", "protocol"]),
      "endpoint_ref" => profile["id"],
      "framing" => framing,
      "allowed_source_refs" => [opportunity["spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => shift_time(opportunity["starts_at"], -30),
        "ends_at" => shift_time(opportunity["ends_at"], 30)
      },
      "credential_ref" => nil,
      "diagnostics" => %{"endpoint_health" => "healthy"}
    }
  end

  defp reject_raw_transport(attrs) do
    case Enum.find(@forbidden_request_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:invalid, "#{key} is setup data and is not allowed in a Contact request"}}
    end
  end

  defp normalize_request(attrs) do
    with :ok <- require_text_fields(attrs, @required_request_keys),
         {:ok, tags} <- tags(attrs["tags"]) do
      {:ok,
       attrs
       |> Map.take(@required_request_keys)
       |> Map.put("tags", tags)}
    end
  end

  defp require_text_fields(attrs, keys) do
    case Enum.find(keys, fn key -> not (is_binary(attrs[key]) and attrs[key] != "") end) do
      nil -> :ok
      key -> {:error, {:invalid, "#{key} is required"}}
    end
  end

  defp tags(nil), do: {:ok, %{}}
  defp tags(value) when is_map(value), do: {:ok, value}
  defp tags(_value), do: {:error, {:invalid, "tags must be an object"}}

  defp validate_opportunity(opportunity, request) do
    cond do
      opportunity["spacecraft_ref"] != request["spacecraft_ref"] ->
        {:error, {:invalid, "spacecraft_ref does not match opportunity_ref"}}

      opportunity["service_profile_ref"] != request["service_profile_ref"] ->
        {:error, {:invalid, "service_profile_ref does not match opportunity_ref"}}

      true ->
        :ok
    end
  end

  defp fetch_service_profile(run, id) do
    case Enum.find(ServiceProfiles.for_run(run), &(&1["id"] == id and &1["state"] == "active")) do
      nil -> {:error, {:invalid, "service_profile_ref is invalid"}}
      profile -> {:ok, profile}
    end
  end

  defp validate_delivery_profile(profile, service_profile) do
    cond do
      profile["state"] != "ready" ->
        {:error, {:conflict, "delivery profile is not ready"}}

      service_profile["id"] not in profile["supported_service_profile_refs"] ->
        {:error, {:invalid, "delivery profile does not support the selected service profile"}}

      get_in(profile, ["target", "protocol"]) != "tcp" ->
        {:error, {:invalid, "delivery profile has no executable TCP target"}}

      true ->
        :ok
    end
  end

  defp validate_idempotency_key(run, value) do
    mode = get_in(run, ["scenario_snapshot", "provider_behavior", "idempotency"])

    if mode == "native" and not (is_binary(value) and value != ""),
      do: {:error, {:invalid, "Idempotency-Key header is required by this environment"}},
      else: :ok
  end

  defp ensure_modifiable(%{"status" => status}) when status in ["pending", "confirmed"], do: :ok

  defp ensure_modifiable(%{"status" => status}) do
    if terminal_status?(status),
      do: {:error, {:conflict, "contact is already terminal"}},
      else: {:error, {:conflict, "contact can no longer be modified"}}
  end

  defp normalize_modification_request(contact, attrs) do
    unknown_keys = Map.keys(attrs) -- @modification_request_keys

    with true <- unknown_keys == [],
         :ok <- require_text_fields(attrs, ["client_reference"]),
         :ok <- validate_expected_revision(attrs["expected_revision"]),
         :ok <-
           validate_optional_text(attrs, ["ground_station_ref", "antenna_or_service_pool_ref"]),
         :ok <- validate_optional_timestamp(attrs, "starts_at"),
         :ok <- validate_optional_timestamp(attrs, "ends_at"),
         :ok <- validate_optional_reason(attrs["reason"]),
         changes = Map.take(attrs, @modification_fields),
         true <- map_size(changes) > 0,
         :ok <- validate_modified_window(contact, changes) do
      {:ok, Map.take(attrs, @modification_request_keys)}
    else
      false when unknown_keys != [] ->
        {:error,
         {:invalid, "unsupported Contact modification field: #{List.first(unknown_keys)}"}}

      false ->
        {:error, {:invalid, "at least one Contact modification field is required"}}

      error ->
        error
    end
  end

  defp validate_expected_revision(value) when is_integer(value) and value > 0, do: :ok

  defp validate_expected_revision(_value),
    do: {:error, {:invalid, "expected_revision is required"}}

  defp validate_optional_text(attrs, keys) do
    case Enum.find(keys, fn key ->
           Map.has_key?(attrs, key) and not (is_binary(attrs[key]) and attrs[key] != "")
         end) do
      nil -> :ok
      key -> {:error, {:invalid, "#{key} must be non-empty text"}}
    end
  end

  defp validate_optional_timestamp(attrs, key) do
    case Map.fetch(attrs, key) do
      :error ->
        :ok

      {:ok, value} when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, _datetime, _offset} -> :ok
          _error -> {:error, {:invalid, "#{key} must be an ISO 8601 timestamp"}}
        end

      {:ok, _value} ->
        {:error, {:invalid, "#{key} must be an ISO 8601 timestamp"}}
    end
  end

  defp validate_optional_reason(nil), do: :ok
  defp validate_optional_reason(value) when is_binary(value) and value != "", do: :ok
  defp validate_optional_reason(_value), do: {:error, {:invalid, "reason must be non-empty text"}}

  defp validate_modified_window(contact, changes) do
    with {:ok, starts_at, _offset} <-
           DateTime.from_iso8601(Map.get(changes, "starts_at", contact["starts_at"])),
         {:ok, ends_at, _offset} <-
           DateTime.from_iso8601(Map.get(changes, "ends_at", contact["ends_at"])),
         true <- DateTime.before?(starts_at, ends_at) do
      :ok
    else
      _error -> {:error, {:invalid, "modified ends_at must be after starts_at"}}
    end
  end

  defp modify_or_recover(run, contact, request, idempotency_key, request_id) do
    case existing_modification(run, contact, request, idempotency_key) do
      nil -> apply_modification(run, contact, request, idempotency_key, request_id)
      existing -> recover_modification(contact, request, existing)
    end
  end

  defp existing_modification(run, contact, request, idempotency_key) do
    mode = get_in(run, ["scenario_snapshot", "provider_behavior", "idempotency"])

    Enum.find(contact["modification_history"] || [], fn modification ->
      case mode do
        "native" -> modification["idempotency_key"] == idempotency_key
        "client_reference" -> modification["client_reference"] == request["client_reference"]
        "none" -> false
      end
    end)
  end

  defp recover_modification(contact, request, existing) do
    if existing["request"] == request do
      {:ok, public(contact)}
    else
      {:error, {:conflict, "idempotency identity already has a different modification request"}}
    end
  end

  defp apply_modification(run, contact, request, idempotency_key, request_id) do
    with true <- request["expected_revision"] == contact["revision"],
         changes = Map.take(request, @modification_fields),
         candidate = Map.merge(contact, changes),
         :ok <- ensure_modified_capacity(run, candidate, contact["id"]) do
      modification = %{
        "client_reference" => request["client_reference"],
        "idempotency_key" => idempotency_key,
        "request" => request,
        "from_revision" => contact["revision"],
        "to_revision" => contact["revision"] + 1,
        "applied_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      history = (contact["modification_history"] || []) ++ [modification]

      with {:ok, updated} <-
             ContactLifecycle.update(
               contact,
               Map.put(changes, "modification_history", history),
               request_id
             ) do
        {:ok, public(updated)}
      end
    else
      false -> {:error, {:conflict, "expected_revision does not match current Contact revision"}}
      error -> error
    end
  end

  defp ensure_modified_capacity(run, candidate, contact_id) do
    conflict? =
      Store.list(:contact)
      |> Enum.any?(fn other ->
        other["id"] != contact_id and
          other["run_id"] == run["id"] and
          other["antenna_or_service_pool_ref"] == candidate["antenna_or_service_pool_ref"] and
          not terminal_status?(other["status"]) and intervals_overlap?(other, candidate)
      end)

    if conflict?,
      do: {:error, {:no_capacity, "modified antenna or service pool is already reserved"}},
      else: :ok
  end

  defp existing_contact(run, request, idempotency_key) do
    mode = get_in(run, ["scenario_snapshot", "provider_behavior", "idempotency"])

    case mode do
      "native" ->
        Enum.find(Store.list(:contact), fn contact ->
          contact["run_id"] == run["id"] and contact["idempotency_key"] == idempotency_key
        end)

      "client_reference" ->
        Enum.find(Store.list(:contact), fn contact ->
          contact["run_id"] == run["id"] and
            contact["client_reference"] == request["client_reference"]
        end)

      "none" ->
        nil
    end
  end

  defp ensure_capacity(run, opportunity) do
    contact_conflict? =
      Store.list(:contact)
      |> Enum.any?(&capacity_conflict?(&1, run["id"], opportunity))

    reservation_conflict? =
      Store.list(:reservation)
      |> Enum.any?(&legacy_capacity_conflict?(&1, run["id"], opportunity))

    if contact_conflict? or reservation_conflict?,
      do: {:error, {:no_capacity, "selected antenna or service pool is already reserved"}},
      else: :ok
  end

  defp capacity_conflict?(contact, run_id, opportunity) do
    contact["run_id"] == run_id and
      contact["antenna_or_service_pool_ref"] == opportunity["antenna_or_service_pool_ref"] and
      not terminal_status?(contact["status"]) and intervals_overlap?(contact, opportunity)
  end

  defp legacy_capacity_conflict?(reservation, run_id, opportunity) do
    reservation["run_id"] == run_id and
      reservation["antenna_id"] == opportunity["antenna_or_service_pool_ref"] and
      reservation["status"] not in [
        "rejected",
        "canceled",
        "completed",
        "failed",
        "terminated_early"
      ] and
      intervals_overlap?(reservation, opportunity)
  end

  defp intervals_overlap?(left, right) do
    with {:ok, left_start, _offset} <- DateTime.from_iso8601(left["starts_at"]),
         {:ok, left_end, _offset} <- DateTime.from_iso8601(left["ends_at"]),
         {:ok, right_start, _offset} <- DateTime.from_iso8601(right["starts_at"]),
         {:ok, right_end, _offset} <- DateTime.from_iso8601(right["ends_at"]) do
      DateTime.compare(left_start, right_end) == :lt and
        DateTime.compare(left_end, right_start) == :gt
    else
      _error -> false
    end
  end

  defp scheduling_rejected?(run, opportunity) do
    fault_profile = run["scenario_snapshot"]["fault_profile"]
    rate = fault_profile["scheduling_rejection_rate"]

    fault_profile["provider_outage"] or rate >= 1 or
      (rate > 0 and
         :erlang.phash2({run["seed"], opportunity["id"], :scheduling_rejection}, 1_000_000) /
           1_000_000 < rate)
  end

  defp shift_time(value, seconds) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
      _error -> value
    end
  end
end
