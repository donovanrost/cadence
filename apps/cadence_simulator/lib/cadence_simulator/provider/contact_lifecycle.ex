defmodule CadenceSimulator.Provider.ContactLifecycle do
  @moduledoc "Persists Contact lifecycle changes and emits versioned advisory events."

  alias CadenceSimulator.Provider.{Contract, Store}

  @spec create(map(), binary() | nil) :: {:ok, map()}
  def create(contact, request_id \\ nil) do
    contact = Map.put_new(contact, "revision", 1)

    with {:ok, stored} <- Store.put(:contact, contact) do
      emit(stored, "contact.status_changed", request_id, %{
        "from" => nil,
        "to" => stored["status"],
        "reason" => stored["status_reason"]
      })

      emit(stored, "contact.pass_phase_changed", request_id, %{
        "from" => nil,
        "to" => stored["pass_phase"]
      })

      emit(stored, "delivery.status_changed", request_id, %{
        "from" => nil,
        "to" => get_in(stored, ["delivery", "status"])
      })

      {:ok, stored}
    end
  end

  @spec update(map(), map(), binary() | nil) :: {:ok, map()}
  def update(contact, changes, request_id \\ nil) when is_map(changes) do
    if changed?(contact, changes) do
      updated =
        contact
        |> Map.merge(changes)
        |> Map.put("revision", Map.get(contact, "revision", 1) + 1)
        |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

      with {:ok, stored} <- Store.put(:contact, updated) do
        emit_changes(contact, stored, request_id)
        {:ok, stored}
      end
    else
      {:ok, contact}
    end
  end

  defp emit_changes(previous, current, request_id) do
    modification_fields =
      changed_fields(previous, current, [
        "starts_at",
        "ends_at",
        "ground_station_ref",
        "antenna_or_service_pool_ref"
      ])

    if modification_fields != %{} do
      emit(current, "contact.modified", request_id, %{
        "provider_revision" => current["revision"],
        "changed_fields" => modification_fields
      })
    end

    if previous["status"] != current["status"] do
      emit(current, "contact.status_changed", request_id, %{
        "from" => previous["status"],
        "to" => current["status"],
        "reason" => current["status_reason"]
      })
    end

    if previous["pass_phase"] != current["pass_phase"] do
      emit(current, "contact.pass_phase_changed", request_id, %{
        "from" => previous["pass_phase"],
        "to" => current["pass_phase"]
      })
    end

    previous_delivery = get_in(previous, ["delivery", "status"])
    current_delivery = get_in(current, ["delivery", "status"])

    if previous_delivery != current_delivery do
      emit(current, "delivery.status_changed", request_id, %{
        "from" => previous_delivery,
        "to" => current_delivery,
        "reason" => get_in(current, ["delivery", "reason"])
      })
    end

    if previous["result"] != current["result"] and not is_nil(current["result"]) do
      emit(current, "contact.result_updated", request_id, %{
        "contact_status" => current["status"],
        "delivery_status" => current_delivery
      })
    end
  end

  defp emit(contact, type, request_id, data) do
    data =
      data
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Store.append_event(%{
      "schema_version" => Contract.version(),
      "type" => type,
      "resource_type" => resource_type(type),
      "resource_id" => contact["id"],
      "resource_revision" => contact["revision"],
      "client_reference" => contact["client_reference"],
      "run_id" => contact["run_id"],
      "request_id" => request_id,
      "data" => data
    })
  end

  defp resource_type("delivery." <> _rest), do: "delivery"
  defp resource_type(_type), do: "contact"

  defp changed?(contact, changes) do
    Enum.any?(changes, fn {key, value} -> Map.get(contact, key) != value end)
  end

  defp changed_fields(previous, current, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      before = previous[key]
      after_value = current[key]

      if before == after_value do
        acc
      else
        Map.put(acc, key, %{"before" => before, "after" => after_value})
      end
    end)
  end
end
