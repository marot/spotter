defmodule SpotterWeb.SessionHookController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Services.SessionRegistry
  alias Spotter.Transcripts.Sessions

  require Logger

  def session_start(conn, %{"session_id" => session_id, "pane_id" => pane_id} = params)
      when is_binary(session_id) and is_binary(pane_id) do
    SessionRegistry.register(pane_id, session_id)

    case Sessions.find_or_create(session_id, cwd: params["cwd"]) do
      {:ok, _session} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to create session #{session_id}: #{inspect(reason)}")
    end

    json(conn, %{ok: true})
  end

  def session_start(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "session_id and pane_id are required"})
  end
end
