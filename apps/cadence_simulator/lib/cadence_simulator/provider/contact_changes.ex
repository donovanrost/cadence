defmodule CadenceSimulator.Provider.ContactChanges do
  @moduledoc "Provider-initiated Contact changes used by scenarios and administrator controls."

  alias CadenceSimulator.Provider.{ContactLifecycle, Contacts, Contract, Store}

  @schedule_fields ["starts_at", "ends_at"]
  @resource_fields ["ground_station_ref", "antenna_or_service_pool_ref"]
  @snapshot_fields @schedule_fields ++
                     @resource_fields ++ ["status", "status_reason", "extensions"]
  @max_shift_seconds 86_400

  @spec apply(map(), binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def apply(run, contact_id, attrs, opts \\ [])
      when is_map(run) and is_binary(contact_id) and is_map(attrs) do
    with {:ok, contact} <- Contacts.fetch_internal(contact_id),
         true <- contact["run_id"] == run["id"],
         {:ok, action} <- normalize_action(attrs),
         :ok <- ensure_actionable(contact, action.type),
         {:ok, changes, evidence} <- build_changes(run, contact, action, opts),
         candidate = Map.merge(contact, changes),
         :ok <- validate_candidate(run, contact, candidate),
         {:ok, updated} <- persist(contact, changes, evidence, action, opts) do
      {:ok, Contacts.public(updated)}
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp normalize_action(attrs) do
    attrs = Contract.sanitize(attrs)

    case attrs["type"] do
      "timing_shift" -> timing_shift(attrs)
      "antenna_substitution" -> antenna_substitution(attrs)
      "station_substitution" -> station_substitution(attrs)
      "capacity_reduction" -> capacity_reduction(attrs)
      "counteroffer" -> counteroffer(attrs)
      "cancellation" -> cancellation(attrs)
      _other -> {:error, {:invalid, "provider change type is invalid"}}
    end
  end

  defp timing_shift(attrs) do
    allowed = ["type", "start_shift_seconds", "end_shift_seconds", "reason"]

    with :ok <- reject_unknown(attrs, allowed),
         {:ok, start_shift} <- bounded_shift(attrs["start_shift_seconds"] || 0),
         {:ok, end_shift} <- bounded_shift(attrs["end_shift_seconds"] || 0),
         true <- start_shift != 0 or end_shift != 0,
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :timing_shift,
         start_shift_seconds: start_shift,
         end_shift_seconds: end_shift,
         reason: reason,
         request: attrs
       }}
    else
      false -> {:error, {:invalid, "at least one non-zero timing shift is required"}}
      error -> error
    end
  end

  defp antenna_substitution(attrs) do
    allowed = ["type", "antenna_or_service_pool_ref", "reason"]

    with :ok <- reject_unknown(attrs, allowed),
         {:ok, resource_ref} <- required_text(attrs, "antenna_or_service_pool_ref"),
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :antenna_substitution,
         antenna_or_service_pool_ref: resource_ref,
         reason: reason,
         request: attrs
       }}
    end
  end

  defp station_substitution(attrs) do
    allowed = ["type", "ground_station_ref", "antenna_or_service_pool_ref", "reason"]

    with :ok <- reject_unknown(attrs, allowed),
         {:ok, station_ref} <- required_text(attrs, "ground_station_ref"),
         {:ok, resource_ref} <- optional_text(attrs["antenna_or_service_pool_ref"]),
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :station_substitution,
         ground_station_ref: station_ref,
         antenna_or_service_pool_ref: resource_ref || "#{station_ref}-antenna-1",
         reason: reason,
         request: attrs
       }}
    end
  end

  defp capacity_reduction(attrs) do
    allowed = ["type", "ends_at", "estimated_capacity_bytes", "reason"]

    with :ok <- reject_unknown(attrs, allowed),
         {:ok, ends_at} <- optional_timestamp(attrs["ends_at"]),
         {:ok, capacity} <- optional_positive_integer(attrs["estimated_capacity_bytes"]),
         true <- not is_nil(ends_at) or not is_nil(capacity),
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :capacity_reduction,
         ends_at: ends_at,
         estimated_capacity_bytes: capacity,
         reason: reason,
         request: attrs
       }}
    else
      false -> {:error, {:invalid, "capacity reduction requires ends_at or estimated capacity"}}
      error -> error
    end
  end

  defp counteroffer(attrs) do
    allowed =
      ["type", "expires_at", "reason", "estimated_capacity_bytes"] ++
        @schedule_fields ++ @resource_fields

    with :ok <- reject_unknown(attrs, allowed),
         {:ok, expires_at} <- required_timestamp(attrs, "expires_at"),
         {:ok, starts_at} <- optional_timestamp(attrs["starts_at"]),
         {:ok, ends_at} <- optional_timestamp(attrs["ends_at"]),
         {:ok, station_ref} <- optional_text(attrs["ground_station_ref"]),
         {:ok, resource_ref} <- optional_text(attrs["antenna_or_service_pool_ref"]),
         {:ok, capacity} <- optional_positive_integer(attrs["estimated_capacity_bytes"]),
         true <-
           Enum.any?([starts_at, ends_at, station_ref, resource_ref, capacity], &(!is_nil(&1))),
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :counteroffer,
         expires_at: expires_at,
         starts_at: starts_at,
         ends_at: ends_at,
         ground_station_ref: station_ref,
         antenna_or_service_pool_ref: resource_ref,
         estimated_capacity_bytes: capacity,
         reason: reason || "provider_counteroffer",
         request: attrs
       }}
    else
      false -> {:error, {:invalid, "counteroffer requires a proposed operational change"}}
      error -> error
    end
  end

  defp cancellation(attrs) do
    with :ok <- reject_unknown(attrs, ["type", "reason"]),
         {:ok, reason} <- optional_reason(attrs["reason"]) do
      {:ok,
       %{
         type: :cancellation,
         reason: reason || "provider_initiated_cancellation",
         request: attrs
       }}
    end
  end

  defp build_changes(_run, contact, %{type: :timing_shift} = action, opts) do
    starts_at = shift_time(contact["starts_at"], action.start_shift_seconds)
    ends_at = shift_time(contact["ends_at"], action.end_shift_seconds)

    changes = %{"starts_at" => starts_at, "ends_at" => ends_at}
    evidence = change_evidence(contact, changes, action, true, opts)
    {:ok, changes_with_evidence(contact, changes, evidence), evidence}
  end

  defp build_changes(_run, contact, %{type: :antenna_substitution} = action, opts) do
    changes = %{"antenna_or_service_pool_ref" => action.antenna_or_service_pool_ref}
    equivalent? = same_station_resource?(contact, action.antenna_or_service_pool_ref)
    evidence = change_evidence(contact, changes, action, true, opts, equivalent?: equivalent?)
    {:ok, changes_with_evidence(contact, changes, evidence), evidence}
  end

  defp build_changes(_run, contact, %{type: :station_substitution} = action, opts) do
    changes = %{
      "ground_station_ref" => action.ground_station_ref,
      "antenna_or_service_pool_ref" => action.antenna_or_service_pool_ref
    }

    evidence = change_evidence(contact, changes, action, true, opts, equivalent?: false)
    {:ok, changes_with_evidence(contact, changes, evidence), evidence}
  end

  defp build_changes(_run, contact, %{type: :capacity_reduction} = action, opts) do
    with :ok <- ensure_capacity_reduced(contact, action) do
      changes = optional_change(%{}, "ends_at", action.ends_at)
      evidence = change_evidence(contact, changes, action, true, opts)

      {:ok,
       changes_with_evidence(contact, changes, evidence,
         estimated_capacity_bytes: action.estimated_capacity_bytes
       ), evidence}
    end
  end

  defp build_changes(_run, contact, %{type: :counteroffer} = action, opts) do
    changes =
      %{}
      |> optional_change("starts_at", action.starts_at)
      |> optional_change("ends_at", action.ends_at)
      |> optional_change("ground_station_ref", action.ground_station_ref)
      |> optional_change("antenna_or_service_pool_ref", action.antenna_or_service_pool_ref)
      |> Map.put("status_reason", "provider_counteroffer")

    evidence = change_evidence(contact, changes, action, false, opts)

    {:ok,
     changes_with_evidence(contact, changes, evidence,
       estimated_capacity_bytes: action.estimated_capacity_bytes,
       counteroffer: %{"expires_at" => action.expires_at, "reason" => action.reason}
     ), evidence}
  end

  defp build_changes(_run, contact, %{type: :cancellation} = action, opts) do
    delivery =
      if get_in(contact, ["delivery", "status"]) in ["failed", "ended"],
        do: contact["delivery"],
        else: Map.put(contact["delivery"], "status", "ended")

    changes = %{
      "status" => "canceled",
      "status_reason" => action.reason,
      "pass_phase" => "closed",
      "delivery" => delivery
    }

    evidence = change_evidence(contact, changes, action, true, opts)
    {:ok, changes_with_evidence(contact, changes, evidence), evidence}
  end

  defp changes_with_evidence(contact, changes, evidence, opts \\ []) do
    extensions =
      contact
      |> Map.get("extensions", %{})
      |> Map.put("provider_change", evidence)
      |> maybe_put_capacity(Keyword.get(opts, :estimated_capacity_bytes))
      |> maybe_put_counteroffer(Keyword.get(opts, :counteroffer))

    Map.put(changes, "extensions", extensions)
  end

  defp persist(contact, changes, evidence, action, opts) do
    history_entry = %{
      "source" => "provider",
      "type" => Atom.to_string(action.type),
      "from_revision" => contact["revision"],
      "to_revision" => contact["revision"] + 1,
      "request" => action.request,
      "evidence" => evidence,
      "applied_at" => now_iso8601(opts)
    }

    history = (contact["modification_history"] || []) ++ [history_entry]

    ContactLifecycle.update(
      contact,
      Map.put(changes, "modification_history", history),
      Keyword.get(opts, :request_id)
    )
  end

  defp validate_candidate(run, previous, candidate) do
    with :ok <- validate_window(candidate),
         :ok <- validate_resources(run, candidate) do
      validate_capacity(run, previous, candidate)
    end
  end

  defp validate_window(contact) do
    with {:ok, starts_at, _offset} <- DateTime.from_iso8601(contact["starts_at"]),
         {:ok, ends_at, _offset} <- DateTime.from_iso8601(contact["ends_at"]),
         true <- DateTime.before?(starts_at, ends_at) do
      :ok
    else
      _error -> {:error, {:invalid, "provider change produces an invalid Contact window"}}
    end
  end

  defp validate_resources(run, contact) do
    stations = get_in(run, ["scenario_snapshot", "ground_stations"]) || []
    station = Enum.find(stations, &(&1["id"] == contact["ground_station_ref"]))
    resource = contact["antenna_or_service_pool_ref"]

    cond do
      is_nil(station) ->
        {:error, {:invalid, "provider change references an unknown ground station"}}

      valid_antenna?(station, resource) ->
        :ok

      true ->
        {:error, {:invalid, "provider change references an unknown antenna or service pool"}}
    end
  end

  defp validate_capacity(run, previous, candidate) do
    if previous["antenna_or_service_pool_ref"] == candidate["antenna_or_service_pool_ref"] and
         previous["starts_at"] == candidate["starts_at"] and
         previous["ends_at"] == candidate["ends_at"] do
      :ok
    else
      conflict? =
        Store.list(:contact)
        |> Enum.any?(fn other ->
          other["id"] != previous["id"] and other["run_id"] == run["id"] and
            other["antenna_or_service_pool_ref"] == candidate["antenna_or_service_pool_ref"] and
            not Contacts.terminal_status?(other["status"]) and overlaps?(other, candidate)
        end)

      if conflict?,
        do: {:error, {:no_capacity, "provider change conflicts with committed capacity"}},
        else: :ok
    end
  end

  defp ensure_actionable(contact, :cancellation) do
    if Contacts.terminal_status?(contact["status"]),
      do: {:error, {:conflict, "contact is already terminal"}},
      else: :ok
  end

  defp ensure_actionable(%{"status" => status}, _type) when status in ["pending", "confirmed"],
    do: :ok

  defp ensure_actionable(contact, _type) do
    if Contacts.terminal_status?(contact["status"]),
      do: {:error, {:conflict, "contact is already terminal"}},
      else: {:error, {:conflict, "provider can no longer change this Contact"}}
  end

  defp ensure_capacity_reduced(contact, action) do
    current_capacity = get_in(contact, ["extensions", "estimated_capacity", "value"])

    cond do
      not is_nil(action.ends_at) and not before?(action.ends_at, contact["ends_at"]) ->
        {:error, {:invalid, "capacity reduction ends_at must be earlier than the Contact end"}}

      is_integer(action.estimated_capacity_bytes) and is_integer(current_capacity) and
          action.estimated_capacity_bytes >= current_capacity ->
        {:error, {:invalid, "estimated capacity must be reduced"}}

      true ->
        :ok
    end
  end

  defp change_evidence(contact, changes, action, effective?, opts, extra \\ []) do
    %{
      "type" => Atom.to_string(action.type),
      "effective" => effective?,
      "reason" => action.reason,
      "changed_at" => now_iso8601(opts),
      "equivalent_resource" => Keyword.get(extra, :equivalent?),
      "before" => evidence_snapshot(contact),
      "after" => contact |> Map.merge(changes) |> evidence_snapshot()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp evidence_snapshot(contact) do
    contact
    |> Map.take(@snapshot_fields)
    |> Map.update("extensions", %{}, &Map.drop(&1, ["provider_change"]))
  end

  defp same_station_resource?(contact, resource_ref) do
    String.starts_with?(resource_ref, "#{contact["ground_station_ref"]}-antenna-")
  end

  defp valid_antenna?(station, resource_ref) when is_binary(resource_ref) do
    prefix = "#{station["id"]}-antenna-"

    with true <- String.starts_with?(resource_ref, prefix),
         suffix = String.replace_prefix(resource_ref, prefix, ""),
         {number, ""} <- Integer.parse(suffix) do
      number >= 1 and number <= station["antenna_count"]
    else
      _other -> false
    end
  end

  defp valid_antenna?(_station, _resource_ref), do: false

  defp overlaps?(left, right) do
    with {:ok, left_start, _offset} <- DateTime.from_iso8601(left["starts_at"]),
         {:ok, left_end, _offset} <- DateTime.from_iso8601(left["ends_at"]),
         {:ok, right_start, _offset} <- DateTime.from_iso8601(right["starts_at"]),
         {:ok, right_end, _offset} <- DateTime.from_iso8601(right["ends_at"]) do
      DateTime.before?(left_start, right_end) and DateTime.before?(right_start, left_end)
    else
      _error -> false
    end
  end

  defp shift_time(value, seconds) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime |> DateTime.add(seconds, :second) |> DateTime.to_iso8601()

      _error ->
        value
    end
  end

  defp before?(left, right) do
    with {:ok, left_at, _offset} <- DateTime.from_iso8601(left),
         {:ok, right_at, _offset} <- DateTime.from_iso8601(right) do
      DateTime.before?(left_at, right_at)
    else
      _error -> false
    end
  end

  defp bounded_shift(value)
       when is_integer(value) and value >= -@max_shift_seconds and value <= @max_shift_seconds,
       do: {:ok, value}

  defp bounded_shift(_value),
    do: {:error, {:invalid, "timing shifts must be bounded integer seconds"}}

  defp required_text(attrs, key) do
    case attrs[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "#{key} is required"}}
    end
  end

  defp optional_text(nil), do: {:ok, nil}
  defp optional_text(value) when is_binary(value) and value != "", do: {:ok, value}
  defp optional_text(_value), do: {:error, {:invalid, "value must be non-empty text"}}

  defp optional_reason(nil), do: {:ok, nil}
  defp optional_reason(value) when is_binary(value) and value != "", do: {:ok, value}
  defp optional_reason(_value), do: {:error, {:invalid, "reason must be non-empty text"}}

  defp required_timestamp(attrs, key) do
    case optional_timestamp(attrs[key]) do
      {:ok, nil} -> {:error, {:invalid, "#{key} is required"}}
      result -> result
    end
  end

  defp optional_timestamp(nil), do: {:ok, nil}

  defp optional_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_iso8601(datetime)}
      _error -> {:error, {:invalid, "timestamp is invalid"}}
    end
  end

  defp optional_timestamp(_value), do: {:error, {:invalid, "timestamp is invalid"}}

  defp optional_positive_integer(nil), do: {:ok, nil}
  defp optional_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp optional_positive_integer(_value),
    do: {:error, {:invalid, "estimated_capacity_bytes must be positive"}}

  defp reject_unknown(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] -> :ok
      [field | _rest] -> {:error, {:invalid, "unsupported provider change field: #{field}"}}
    end
  end

  defp optional_change(changes, _key, nil), do: changes
  defp optional_change(changes, key, value), do: Map.put(changes, key, value)

  defp maybe_put_capacity(extensions, nil), do: extensions

  defp maybe_put_capacity(extensions, value),
    do: Map.put(extensions, "estimated_capacity", %{"unit" => "bytes", "value" => value})

  defp maybe_put_counteroffer(extensions, nil), do: Map.delete(extensions, "counteroffer")
  defp maybe_put_counteroffer(extensions, value), do: Map.put(extensions, "counteroffer", value)

  defp now_iso8601(opts) do
    opts
    |> Keyword.get(:now, DateTime.utc_now())
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end
end
