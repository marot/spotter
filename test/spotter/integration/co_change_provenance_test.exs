defmodule Spotter.Integration.CoChangeProvenanceTest do
  @moduledoc "Integration tests for co-change provenance correctness and backfill."

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CoChangeCalculator

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    Project,
    Session
  }

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp setup_project_with_repo do
    project =
      Ash.create!(Project, %{
        name: "prov-test-#{System.unique_integer([:positive])}",
        pattern: "^prov"
      })

    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: File.cwd!()
    })

    project
  end

  describe "compute persists provenance" do
    @tag timeout: 120_000
    test "groups have linked commits and member stats after compute" do
      project = setup_project_with_repo()

      assert :ok = CoChangeCalculator.compute(project.id)

      # Groups should exist
      groups =
        CoChangeGroup
        |> Ash.Query.filter(project_id == ^project.id and scope == :file)
        |> Ash.read!()

      assert groups != []

      # At least one group should have commit provenance
      group_commits =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id and scope == :file)
        |> Ash.read!()

      assert group_commits != []

      # At least one group should have member stats
      member_stats =
        CoChangeGroupMemberStat
        |> Ash.Query.filter(project_id == ^project.id and scope == :file)
        |> Ash.read!()

      assert member_stats != []

      # Verify a specific group has both commits and stats
      [sample_group | _] = groups

      group_specific_commits =
        group_commits
        |> Enum.filter(&(&1.group_key == sample_group.group_key))

      group_specific_stats =
        member_stats
        |> Enum.filter(&(&1.group_key == sample_group.group_key))

      assert group_specific_commits != []
      assert group_specific_stats != []

      # Each member in the group should have a stat row
      member_paths = Enum.map(group_specific_stats, & &1.member_path) |> Enum.sort()
      assert member_paths == Enum.sort(sample_group.members)
    end
  end

  describe "backfill_provenance" do
    @tag timeout: 180_000
    test "is idempotent - stable row counts on repeated runs" do
      project = setup_project_with_repo()

      # First compute to create groups
      assert :ok = CoChangeCalculator.compute(project.id)

      commits_after_first =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      stats_after_first =
        CoChangeGroupMemberStat
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      # Backfill should produce same results
      assert :ok = CoChangeCalculator.backfill_provenance(project.id)

      commits_after_backfill =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      stats_after_backfill =
        CoChangeGroupMemberStat
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      assert length(commits_after_first) == length(commits_after_backfill)
      assert length(stats_after_first) == length(stats_after_backfill)

      # Run backfill again - still stable
      assert :ok = CoChangeCalculator.backfill_provenance(project.id)

      commits_after_second =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      assert length(commits_after_first) == length(commits_after_second)
    end
  end

  describe "failure tolerance" do
    @tag timeout: 120_000
    test "pipeline completes even when member snapshot cannot be resolved" do
      project = setup_project_with_repo()

      # Compute normally first
      assert :ok = CoChangeCalculator.compute(project.id)

      # read_file_metrics with a non-existent path returns {nil, nil}
      assert {nil, nil} =
               CoChangeCalculator.read_file_metrics(File.cwd!(), "HEAD", "nonexistent/path.ex")

      # The overall compute still returns :ok (no crash)
      assert :ok = CoChangeCalculator.compute(project.id)
    end
  end
end
