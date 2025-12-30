defmodule CadenceWeb.UserRegistrationController do
  use CadenceWeb, :controller

  alias Cadence.Accounts
  alias Cadence.Accounts.User

  def new(conn, _params) do
    changeset = Accounts.change_user_email(%User{})
    render(conn, :new, form: Phoenix.Component.to_form(changeset))
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = %{changeset | action: :insert}
        render(conn, :new, form: Phoenix.Component.to_form(changeset))

      {:error, _reason} ->
        changeset =
          %User{}
          |> Accounts.change_user_email(user_params)
          |> then(&%{&1 | action: :insert})

        render(conn, :new, form: Phoenix.Component.to_form(changeset))
    end
  end
end
