defmodule CadenceWeb.API.ReadParams do
  @moduledoc "Projection and telemetry query parsing boundary."

  import CadenceWeb.API.ParamParser

  @spec mission_health_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def mission_health_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))}
  end

  @spec mission_event_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def mission_event_filters(params) when is_map(params) do
    with {:ok, limit} <- optional_positive_integer(params, "limit"),
         {:ok, cursor} <- mission_event_cursor(params),
         {:ok, category} <- string_or_string_list(params, "category"),
         {:ok, kind} <- string_or_string_list(params, "kind"),
         {:ok, severity} <- string_or_string_list(params, "severity") do
      {:ok,
       []
       |> maybe_put_opt(:limit, limit)
       |> maybe_put_opt(:cursor, cursor)
       |> maybe_put_opt(:category, category)
       |> maybe_put_opt(:kind, kind)
       |> maybe_put_opt(:severity, severity)
       |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:scheduled_contact_id, string_value(params, "scheduled_contact_id"))
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> maybe_put_opt(:path_id, string_value(params, "path_id"))
       |> maybe_put_opt(:capability_instance_id, string_value(params, "capability_instance_id"))}
    end
  end

  @spec telemetry_latest_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def telemetry_latest_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))}
  end

  @spec telemetry_history_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def telemetry_history_filters(params) when is_map(params) do
    with {:ok, limit} <- optional_positive_integer(params, "limit"),
         {:ok, order} <- telemetry_history_order(params),
         {:ok, from_receipt_time} <- optional_datetime(params, "from_receipt_time"),
         {:ok, to_receipt_time} <- optional_datetime(params, "to_receipt_time") do
      {:ok,
       []
       |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))
       |> maybe_put_opt(:limit, limit)
       |> maybe_put_opt(:order, order)
       |> maybe_put_opt(:from_receipt_time, from_receipt_time)
       |> maybe_put_opt(:to_receipt_time, to_receipt_time)}
    end
  end
end
