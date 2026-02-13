defmodule Spotter.Transcripts.TestCase do
  @moduledoc "A test case extracted from a file at a specific commit."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "test_cases"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relative_path,
        :framework,
        :describe_path,
        :test_name,
        :line_start,
        :line_end,
        :given,
        :when,
        :then,
        :confidence,
        :metadata
      ]

      argument :project_id, :uuid_v7, allow_nil?: false
      argument :source_commit_id, :uuid_v7

      change manage_relationship(:project_id, :project, type: :append_and_remove)
      change manage_relationship(:source_commit_id, :source_commit, type: :append_and_remove)

      upsert? true
      upsert_identity :unique_test_case
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :framework,
        :describe_path,
        :test_name,
        :line_start,
        :line_end,
        :given,
        :when,
        :then,
        :confidence,
        :metadata
      ]

      argument :source_commit_id, :uuid_v7
      change manage_relationship(:source_commit_id, :source_commit, type: :append_and_remove)
    end
  end

  validations do
    validate {Spotter.Transcripts.TestCase.LineRangeValidation, []}
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false
    attribute :framework, :string, allow_nil?: false
    attribute :describe_path, {:array, :string}, allow_nil?: false, default: []
    attribute :test_name, :string, allow_nil?: false

    attribute :line_start, :integer
    attribute :line_end, :integer

    attribute :given, {:array, :string}, allow_nil?: false, default: []
    attribute :when, {:array, :string}, allow_nil?: false, default: []
    attribute :then, {:array, :string}, allow_nil?: false, default: []

    attribute :confidence, :float do
      constraints min: 0.0, max: 1.0
    end

    attribute :metadata, :map, allow_nil?: false, default: %{}

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project, allow_nil?: false
    belongs_to :source_commit, Spotter.Transcripts.Commit, allow_nil?: true
  end

  identities do
    identity :unique_test_case, [
      :project_id,
      :relative_path,
      :framework,
      :describe_path,
      :test_name
    ]
  end
end

defmodule Spotter.Transcripts.TestCase.LineRangeValidation do
  @moduledoc false
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    line_start = Ash.Changeset.get_attribute(changeset, :line_start)
    line_end = Ash.Changeset.get_attribute(changeset, :line_end)

    cond do
      is_nil(line_start) or is_nil(line_end) ->
        :ok

      line_start < 1 ->
        {:error, field: :line_start, message: "must be greater than 0"}

      line_end < 1 ->
        {:error, field: :line_end, message: "must be greater than 0"}

      line_end < line_start ->
        {:error, field: :line_end, message: "must be greater than or equal to line_start"}

      true ->
        :ok
    end
  end
end
