defmodule SpotterWeb.SessionHookControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.ActiveSessionRegistry

  @endpoint SpotterWeb.Endpoint
  @active_table Spotter.Services.ActiveSessionRegistry

  @valid_traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  @malformed_traceparent "not-a-valid-traceparent"

  setup do
    Sandbox.checkout(Spotter.Repo)
    :ets.delete_all_objects(@active_table)
    :ok
  end

  defp post_session_start(params, headers \\ []) do
    post_hook("/api/hooks/session-start", params, headers)
  end

  defp post_session_end(params, headers \\ []) do
    post_hook("/api/hooks/session-end", params, headers)
  end

  defp post_hook(path, params, headers) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, path, params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp valid_params do
    %{
      "session_id" => Ash.UUID.generate(),
      "pane_id" => "%1",
      "cwd" => "/home/user/project"
    }
  end

  describe "POST /api/hooks/session-start" do
    test "succeeds with valid params" do
      {status, body, _conn} = post_session_start(valid_params())

      assert status == 200
      assert body["ok"] == true
    end

    test "registers session in ActiveSessionRegistry" do
      params = valid_params()
      post_session_start(params)

      info = ActiveSessionRegistry.status(params["session_id"])
      assert info != nil
      assert info.status == :active
    end

    test "returns 400 for missing session_id" do
      {status, body, _conn} = post_session_start(%{"pane_id" => "%1"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 400 for missing pane_id" do
      {status, body, _conn} =
        post_session_start(%{"session_id" => Ash.UUID.generate()})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "succeeds with valid traceparent header" do
      {status, body, conn} =
        post_session_start(valid_params(), [{"traceparent", @valid_traceparent}])

      assert status == 200
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end

    test "succeeds with malformed traceparent header" do
      {status, body, _conn} =
        post_session_start(valid_params(), [{"traceparent", @malformed_traceparent}])

      assert status == 200
      assert body["ok"] == true
    end

    test "succeeds without traceparent header" do
      {status, body, _conn} = post_session_start(valid_params())

      assert status == 200
      assert body["ok"] == true
    end
  end

  describe "POST /api/hooks/session-end" do
    test "succeeds with valid session_id" do
      session_id = Ash.UUID.generate()
      {status, body, _conn} = post_session_end(%{"session_id" => session_id})

      assert status == 200
      assert body["ok"] == true
    end

    test "marks session as ended in registry" do
      params = valid_params()
      post_session_start(params)

      post_session_end(%{"session_id" => params["session_id"], "reason" => "user_exit"})

      info = ActiveSessionRegistry.status(params["session_id"])
      assert info.status == :ended
      assert info.ended_reason == "user_exit"
    end

    test "is idempotent for duplicate end requests" do
      session_id = Ash.UUID.generate()

      {status1, body1, _} = post_session_end(%{"session_id" => session_id, "reason" => "first"})
      {status2, body2, _} = post_session_end(%{"session_id" => session_id, "reason" => "second"})

      assert status1 == 200
      assert body1["ok"] == true
      assert status2 == 200
      assert body2["ok"] == true
    end

    test "handles unknown session without crashing" do
      {status, body, _conn} =
        post_session_end(%{"session_id" => Ash.UUID.generate()})

      assert status == 200
      assert body["ok"] == true
    end

    test "handles missing optional fields gracefully" do
      session_id = Ash.UUID.generate()
      {status, body, _conn} = post_session_end(%{"session_id" => session_id})

      assert status == 200
      assert body["ok"] == true

      info = ActiveSessionRegistry.status(session_id)
      assert info.ended_reason == nil
    end

    test "returns 400 for missing session_id" do
      {status, body, _conn} = post_session_end(%{})

      assert status == 400
      assert body["error"] =~ "session_id is required"
    end

    test "succeeds with valid traceparent header" do
      {status, body, conn} =
        post_session_end(
          %{"session_id" => Ash.UUID.generate()},
          [{"traceparent", @valid_traceparent}]
        )

      assert status == 200
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end
  end
end
