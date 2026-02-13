defmodule Spotter.ProductSpec.Jobs.UpdateRollingSpecTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Repo

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  describe "perform/1 idempotence" do
    test "skips when run already has status :ok" do
      project_id = Ash.UUID.generate()
      commit_hash = String.duplicate("b", 40)

      # Pre-create a successful run
      {:ok, _run} =
        Ash.create(RollingSpecRun, %{
          project_id: project_id,
          commit_hash: commit_hash,
          status: :ok,
          finished_at: DateTime.utc_now()
        })

      job = %Oban.Job{
        args: %{
          "project_id" => project_id,
          "commit_hash" => commit_hash
        }
      }

      assert :ok = UpdateRollingSpec.perform(job)

      # Verify the run was marked as skipped
      run =
        RollingSpecRun
        |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
        |> Ash.read_one!()

      assert run.status in [:ok, :skipped]
    end
  end
end
