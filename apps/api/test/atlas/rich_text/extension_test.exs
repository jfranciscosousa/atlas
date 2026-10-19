defmodule Atlas.RichText.ExtensionTest do
  use ExUnit.Case, async: true

  alias Atlas.Campaigns.Campaign

  test "each section generates its columns and a narrow save action" do
    for section <- [:description, :progress_rewards] do
      for suffix <- ~w(json schema_version revision) do
        attr = Ash.Resource.Info.attribute(Campaign, :"#{section}_#{suffix}")
        assert attr, "#{section}_#{suffix} missing"
        refute attr.writable?
      end

      action = Ash.Resource.Info.action(Campaign, :"save_#{section}")
      assert action.accept == []
      assert Enum.map(action.arguments, & &1.name) == [:json, :schema_version, :expected_revision]
    end
  end

  test "a generated name that already exists fails at compile time" do
    assert_raise Spark.Error.DslError, ~r/already exists/, fn ->
      Code.compile_string("""
      defmodule Atlas.RichText.ExtensionTest.Clash do
        use Ash.Resource, domain: nil, extensions: [Atlas.RichText]

        attributes do
          uuid_primary_key :id
          attribute :notes_revision, :integer, public?: true
        end

        rich_text do
          section :notes
        end
      end
      """)
    end
  end
end
