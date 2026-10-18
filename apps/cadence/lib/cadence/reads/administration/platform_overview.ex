defmodule Cadence.Reads.Administration.PlatformOverview do
  @moduledoc "Authorized platform counts; no presentation or unsupported management actions."
  alias Cadence.{Accounts, Organizations}
  alias Cadence.Administration.Access

  def load(scope) do
    with {:ok, user} <- Access.authorize(scope) do
      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "counts" => %{
           "organizations" => Organizations.count_organizations(),
           "active_users" => Accounts.count_users()
         }
       }}
    end
  end
end
