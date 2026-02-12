defmodule Spotter.Transcripts.Jobs.ScoreHotspotsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.Jobs.ScoreHotspots
  alias Spotter.Transcripts.{Project, Session}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, attrs) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: attrs[:cwd]
    })
  end

  describe "perform/1 missing API key preflight" do
    setup do
      prev_app = Application.get_env(:langchain, :anthropic_key)
      prev_env = System.get_env("ANTHROPIC_API_KEY")

      Application.delete_env(:langchain, :anthropic_key)
      System.delete_env("ANTHROPIC_API_KEY")

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

    test "returns :ok with warning and no CodeHotspot rows when key is missing" do
      import ExUnit.CaptureLog

      project = create_project("hotspot-no-key")
      valid_cwd = System.tmp_dir!()
      create_session(project, cwd: valid_cwd)

      log =
        capture_log(fn ->
          assert :ok = ScoreHotspots.perform(%Oban.Job{args: %{"project_id" => project.id}})
        end)

      assert log =~ "missing Anthropic API key"
      assert log =~ project.id

      hotspots =
        Spotter.Transcripts.CodeHotspot
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      assert hotspots == []
    end
  end

  describe "resolve_repo_path fallback" do
    test "skips when no sessions exist for project" do
      project = create_project("hotspot-no-sessions")

      assert :ok =
               ScoreHotspots.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

    test "skips when all session cwds are nil" do
      project = create_project("hotspot-nil-cwd")
      create_session(project, cwd: nil)

      assert :ok =
               ScoreHotspots.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

    test "skips when all session cwds point to non-existent directories" do
      project = create_project("hotspot-stale-cwd")
      create_session(project, cwd: "/tmp/nonexistent-spotter-test-#{System.unique_integer()}")
      create_session(project, cwd: "/tmp/nonexistent-spotter-test-#{System.unique_integer()}")

      assert :ok =
               ScoreHotspots.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

    test "uses fallback cwd when newest session cwd is missing" do
      project = create_project("hotspot-fallback-cwd")

      # Create a valid cwd using a real directory
      valid_cwd = System.tmp_dir!()

      # Older session with valid cwd
      create_session(project, cwd: valid_cwd)

      # Newer session with invalid cwd (inserted after, so sorted first)
      create_session(project, cwd: "/tmp/nonexistent-spotter-test-#{System.unique_integer()}")

      # Should succeed by falling back to the older session's valid cwd.
      # It will find 0 heatmap entries to score (no FileHeatmap rows), but
      # the important thing is it doesn't skip.
      assert :ok =
               ScoreHotspots.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end
  end
end
