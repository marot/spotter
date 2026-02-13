defmodule SpotterWeb.HotspotsLiveTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, CommitHotspot, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_hotspot(project, path, opts) do
    commit =
      Ash.create!(Commit, %{
        commit_hash: opts[:hash] || String.duplicate("a", 40),
        subject: opts[:subject] || "Test commit"
      })

    Ash.create!(CommitHotspot, %{
      project_id: project.id,
      commit_id: commit.id,
      relative_path: path,
      snippet: opts[:snippet] || "defmodule Foo do\nend",
      line_start: 1,
      line_end: 10,
      overall_score: opts[:score] || 50.0,
      reason: "Complex logic",
      rubric: opts[:rubric] || %{"complexity" => 50, "change_frequency" => 40},
      model_used: "claude-opus-4-6",
      analyzed_at: DateTime.utc_now()
    })
  end

  describe "global route" do
    test "renders hotspots page at /hotspots" do
      {:ok, _view, html} = live(build_conn(), "/hotspots")

      assert html =~ "Commit Hotspots"
    end

    test "renders with project filter via query param" do
      project = create_project("hotspots-qp")
      create_hotspot(project, "lib/scored.ex", score: 65.0)

      {:ok, _view, html} = live(build_conn(), "/hotspots?project_id=#{project.id}")

      assert html =~ "lib/scored.ex"
    end

    test "empty state without project selected" do
      {:ok, _view, html} = live(build_conn(), "/hotspots")

      assert html =~ "No commit hotspots yet"
    end
  end

  describe "project-scoped route" do
    test "renders hotspots for project" do
      project = create_project("hotspots-proj")
      create_hotspot(project, "lib/proj_file.ex", score: 70.0)

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/hotspots")

      assert html =~ "lib/proj_file.ex"
    end
  end

  describe "project filtering" do
    test "filter_project event navigates via push_patch" do
      project = create_project("hotspots-filter")
      create_hotspot(project, "lib/only.ex", score: 55.0)

      {:ok, view, _html} = live(build_conn(), "/hotspots")

      html = render_click(view, "filter_project", %{"project-id" => project.id})

      assert html =~ "lib/only.ex"
    end
  end

  describe "cross-links" do
    test "shows heatmap and co-change links when project selected" do
      project = create_project("hotspots-links")
      create_hotspot(project, "lib/linked.ex", score: 60.0)

      {:ok, _view, html} = live(build_conn(), "/hotspots?project_id=#{project.id}")

      assert html =~ "Heatmap"
      assert html =~ "Co-change"
      assert html =~ "Analyze recent commits"
    end

    test "hides analyze button when no project selected" do
      {:ok, _view, html} = live(build_conn(), "/hotspots")
      refute html =~ "phx-click=\"analyze_commits\""
    end
  end

  describe "analyze commits trigger" do
    test "analyze_commits event enqueues IngestRecentCommits for selected project" do
      project = create_project("hotspots-analyze")
      project_id = project.id

      {:ok, view, _html} = live(build_conn(), "/hotspots?project_id=#{project_id}")
      _html = render_click(view, "analyze_commits", %{})

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Spotter.Transcripts.Jobs.IngestRecentCommits",
            where: j.state == "available"
          )
        )

      assert Enum.any?(jobs, &(&1.args["project_id"] == project_id))
    end
  end
end
