defmodule Cadence.Dashboards.AuthoringErrors do
  @moduledoc "Finite error vocabulary shared by immediate commands and staged authoring."

  def normalize({:error, {:dashboard_version_conflict, _}}), do: {:error, :conflict}
  def normalize({:error, {:invalid_dashboard_document, _}}), do: {:error, :invalid_document}

  def normalize({:error, {code, _}})
      when code in [:invalid_type, :invalid_title, :invalid_options, :invalid_binding],
      do: {:error, code}

  def normalize({:error, code})
      when code in [
             :forbidden,
             :invalid_input,
             :invalid_defaults,
             :conflict,
             :missing_section,
             :missing_placement,
             :unsupported_widget,
             :invalid_widget,
             :capacity
           ],
      do: {:error, code}

  def normalize({:error, code})
      when code in [:dashboard_not_found, :dashboard_archived, :dashboard_version_not_found],
      do: {:error, :unavailable}

  def normalize(_), do: {:error, :unknown}
end
