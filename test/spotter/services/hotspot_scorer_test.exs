defmodule Spotter.Services.HotspotScorerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Spotter.Services.HotspotScorer

  setup do
    prev_app = Application.get_env(:langchain, :anthropic_key)
    prev_env = System.get_env("ANTHROPIC_API_KEY")

    on_exit(fn ->
      if prev_app,
        do: Application.put_env(:langchain, :anthropic_key, prev_app),
        else: Application.delete_env(:langchain, :anthropic_key)

      if prev_env,
        do: System.put_env("ANTHROPIC_API_KEY", prev_env),
        else: System.delete_env("ANTHROPIC_API_KEY")
    end)

    :ok
  end

  describe "score/3 with missing API key" do
    setup do
      Application.delete_env(:langchain, :anthropic_key)
      System.delete_env("ANTHROPIC_API_KEY")
      :ok
    end

    test "returns {:error, :missing_api_key} without making outbound call" do
      log =
        capture_log(fn ->
          assert {:error, :missing_api_key} =
                   HotspotScorer.score(
                     "lib/example.ex",
                     "defmodule Example do\n  def x, do: :ok\nend"
                   )
        end)

      refute log =~ "x-api-key header is required"
    end
  end
end
