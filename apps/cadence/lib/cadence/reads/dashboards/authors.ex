defmodule Cadence.Reads.Dashboards.Authors do
  @moduledoc """
  Names of the people who saved, shared, published or changed dashboards (#469, #146): a person
  is named only while they hold an active membership in the dashboard's organization, checked at
  read time (`Accounts.MemberNames`). Someone who has left, or a platform admin from another
  organization, gets no name: never their email, never their id.
  """
  alias Cadence.Accounts.MemberNames

  @doc "`%{user_id => display_name}` for the ids that are named; any other id is absent."
  @spec names(binary(), [binary() | nil]) :: %{binary() => binary()}
  def names(organization_id, ids),
    do: MemberNames.display_names(organization_id, Enum.filter(ids, &is_binary/1))
end
