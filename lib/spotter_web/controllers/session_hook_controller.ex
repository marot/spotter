defmodule SpotterWeb.SessionHookController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Services.ActiveSessionRegistry
  alias Spotter.Services.SessionRegistry
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.Sessions
  alias SpotterWeb.OtelTraceHelpers

  require Logger
  require SpotterWeb.OtelTraceHelpers

  def session_start(conn, %{"session_id" => session_id, "pane_id" => pane_id} = params)
      when is_binary(session_id) and is_binary(pane_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "SessionStart"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.session_start", %{
      "spotter.session_id" => session_id,
      "spotter.pane_id" => pane_id,
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      SessionRegistry.register(pane_id, session_id)
      ActiveSessionRegistry.start_session(session_id, pane_id)

      case Sessions.find_or_create(session_id, cwd: params["cwd"]) do
        {:ok, session} ->
          maybe_bootstrap_sync(session)

        {:error, reason} ->
          Logger.warning("Failed to create session #{session_id}: #{inspect(reason)}")
      end

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true})
    end
  end

  def session_start(conn, _params) do
    OtelTraceHelpers.with_span "spotter.hook.session_start", %{} do
      OtelTraceHelpers.set_error("invalid_params", %{"http.status_code" => 400})

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id and pane_id are required"})
    end
  end

  defp maybe_bootstrap_sync(session) do
    if is_nil(session.message_count) or session.message_count == 0 do
      Task.start(fn -> SyncTranscripts.sync_session_by_id(session.session_id) end)
    end
  end

  def session_end(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "Stop"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.session_end", %{
      "spotter.session_id" => session_id,
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      reason = params["reason"]
      ActiveSessionRegistry.end_session(session_id, reason)

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true})
    end
  end

  def session_end(conn, _params) do
    OtelTraceHelpers.with_span "spotter.hook.session_end", %{} do
      OtelTraceHelpers.set_error("invalid_params", %{"http.status_code" => 400})

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id is required"})
    end
  end
end
