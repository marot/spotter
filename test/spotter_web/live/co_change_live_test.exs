defmodule SpotterWeb.CoChangeLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{CoChangeGroup, CoChangeGroupCommit, CoChangeGroupMemberStat, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_group(project, opts) do
    Ash.create!(CoChangeGroup, %{
      project_id: project.id,
      scope: opts[:scope] || :file,
      group_key: opts[:group_key],
      members: opts[:members],
      frequency_30d: opts[:frequency] || 1,
      last_seen_at: opts[:last_seen_at] || ~U[2026-02-10 12:00:00Z]
    })
  end

  describe "global route" do
    test "renders co-change page at /co-change" do
      {:ok, _view, html} = live(build_conn(), "/co-change")

      assert html =~ "Co-change Groups"
    end

    test "shows select project prompt without project" do
      {:ok, _view, html} = live(build_conn(), "/co-change")

      assert html =~ "Select a project to view co-change groups"
    end

    test "renders with project filter via query param" do
      project = create_project("cochange-qp")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, _view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
    end

    test "filter_project event navigates via push_patch" do
      project = create_project("cochange-filter")

      create_group(project,
        group_key: "lib/x.ex|lib/y.ex",
        members: ["lib/x.ex", "lib/y.ex"],
        frequency: 3
      )

      {:ok, view, _html} = live(build_conn(), "/co-change")

      html = render_click(view, "filter_project", %{"project-id" => project.id})

      assert html =~ "lib/x.ex"
    end
  end

  describe "project-scoped route" do
    test "renders rows sorted by max frequency" do
      project = create_project("cochange-pop")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      create_group(project,
        group_key: "lib/b.ex|lib/c.ex",
        members: ["lib/b.ex", "lib/c.ex"],
        frequency: 3
      )

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
      assert html =~ "lib/c.ex"
      assert html =~ ~s(\u00d75)
      assert html =~ ~s(\u00d73)

      # b.ex has max freq 5 (from a|b), c.ex has max freq 3 (from b|c)
      # Verify rows are present with correct data
      assert html =~ "lib/b.ex"
      assert html =~ "lib/c.ex"

      # Check expand buttons appear in frequency-descending order
      # a.ex and b.ex both have max freq 5, c.ex has max freq 3
      expand_positions =
        Regex.scan(~r/toggle_expand.*?phx-value-member="([^"]+)"/, html)
        |> Enum.map(fn [_, member] -> member end)

      c_idx = Enum.find_index(expand_positions, &(&1 == "lib/c.ex"))
      a_idx = Enum.find_index(expand_positions, &(&1 == "lib/a.ex"))
      assert a_idx < c_idx
    end
  end

  describe "directory scope toggle" do
    test "switches to directory scope on toggle" do
      project = create_project("cochange-dir")

      create_group(project,
        scope: :directory,
        group_key: "lib|test",
        members: ["lib", "test"],
        frequency: 8
      )

      {:ok, view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      # Initially file scope, no directory groups visible
      refute html =~ ~s(\u00d78)

      # Toggle to directory scope
      html = render_click(view, "toggle_scope", %{"scope" => "directory"})

      assert html =~ "lib"
      assert html =~ "test"
      assert html =~ ~s(\u00d78)
    end
  end

  describe "empty state" do
    test "renders empty message for project with no groups" do
      project = create_project("cochange-empty")

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      assert html =~ "No co-change groups for"
    end
  end

  describe "invalid project" do
    test "renders not found for invalid project id" do
      {:ok, _view, html} =
        live(build_conn(), "/projects/019c0000-0000-7000-8000-000000000000/co-change")

      assert html =~ "Project not found"
    end
  end

  describe "sorting" do
    test "sort toggles direction on same field" do
      project = create_project("cochange-sort")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      # Click max_frequency_30d again to toggle to asc
      html = render_click(view, "sort", %{"field" => "max_frequency_30d"})
      assert html =~ "↑"

      # Click again to toggle back to desc
      html = render_click(view, "sort", %{"field" => "max_frequency_30d"})
      assert html =~ "↓"
    end

    test "sort by member field" do
      project = create_project("cochange-sort-member")

      create_group(project,
        group_key: "lib/a.ex|lib/z.ex",
        members: ["lib/a.ex", "lib/z.ex"],
        frequency: 3
      )

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      html = render_click(view, "sort", %{"field" => "member"})
      assert html =~ "lib/a.ex"
    end
  end

  describe "expand/collapse" do
    test "expand shows detail panel" do
      project = create_project("cochange-expand")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      # Not expanded initially
      refute html =~ "Members"

      # Expand
      html = render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      assert html =~ "Members"
      assert html =~ "Relevant Commits"
    end

    test "collapse hides detail panel" do
      project = create_project("cochange-collapse")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      html = render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      refute html =~ "Relevant Commits"
    end

    test "expand shows member stats when available" do
      project = create_project("cochange-stats")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        member_path: "lib/a.ex",
        size_bytes: 2048,
        loc: 75,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      html = render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      assert html =~ "2.0 KB"
      assert html =~ "75"
    end

    test "expand shows empty state when no provenance" do
      project = create_project("cochange-no-prov")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      html = render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      assert html =~ "No file metrics available"
      assert html =~ "No commit provenance recorded"
    end
  end

  describe "commit detail" do
    test "toggle_commit_detail shows commit info when in database" do
      project = create_project("cochange-commit-detail")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      hash = String.duplicate("f", 40)

      Ash.create!(CoChangeGroupCommit, %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        commit_hash: hash,
        committed_at: ~U[2026-02-10 12:00:00Z]
      })

      Ash.create!(Spotter.Transcripts.Commit, %{
        commit_hash: hash,
        git_branch: "main",
        changed_files: ["lib/a.ex", "lib/b.ex"]
      })

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      # Expand the row first
      render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})

      # Click commit detail
      html = render_click(view, "toggle_commit_detail", %{"hash" => hash})
      assert html =~ "Branch:"
      assert html =~ "main"
      assert html =~ "Changed files"
    end

    test "toggle_commit_detail shows fallback when commit not in database" do
      project = create_project("cochange-commit-missing")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      hash = String.duplicate("e", 40)

      Ash.create!(CoChangeGroupCommit, %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        commit_hash: hash,
        committed_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, view, _html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
      html = render_click(view, "toggle_commit_detail", %{"hash" => hash})
      assert html =~ "Commit details not available"
    end
  end

  describe "cross-links" do
    test "shows heatmap and hotspots links when project selected" do
      project = create_project("cochange-links")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 2
      )

      {:ok, _view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      assert html =~ "Heatmap"
      assert html =~ "Hotspots"
    end
  end
end
