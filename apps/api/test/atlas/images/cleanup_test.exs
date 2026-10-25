defmodule Atlas.Images.CleanupTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Images.{Cleanup, Image}

  setup do
    gm = user()
    campaign = campaign(gm)

    note =
      Ash.create!(Atlas.Content.Note, %{campaign_id: campaign.id, title: "Images"}, actor: gm)

    session = Ash.create!(Atlas.Campaigns.Session, %{campaign_id: campaign.id}, actor: gm)

    %{gm: gm, campaign: campaign, note: note, session: session}
  end

  defp image(gm, old? \\ true) do
    key = "images/#{Ecto.UUID.generate()}.webp"
    :ok = Atlas.Storage.put(key, "webp", "image/webp")

    image =
      Ash.create!(Image, %{storage_key: key, byte_size: 4, width: 1, height: 1}, actor: gm)

    if old? do
      Repo.query!("UPDATE images SET inserted_at = now() - interval '2 days' WHERE id = $1", [
        Ecto.UUID.dump!(image.id)
      ])
    end

    on_exit(fn -> Atlas.Storage.delete(key) end)
    image
  end

  defp block(image) do
    %{
      "id" => "image",
      "type" => "image",
      "props" => %{"url" => "atlas-image:#{image.id}"},
      "children" => []
    }
  end

  defp stored?(image),
    do: Ash.get(Image, image.id, authorize?: false, not_found_error?: false) != {:ok, nil}

  defp file?(image) do
    url = Atlas.Storage.signed_url(image.storage_key)
    token = String.replace_prefix(url, "/api/images/", "")
    match?({:ok, _}, Atlas.Storage.LocalDisk.read_signed(token))
  end

  test "deletes removed images from storage and the database; repeated runs succeed", ctx do
    image = image(ctx.gm)
    save_section!(Atlas.Content.Note, ctx.note.id, :body, [block(image)], ctx.gm)
    save_section!(Atlas.Content.Note, ctx.note.id, :body, [], ctx.gm)

    assert :ok = Cleanup.perform(%Oban.Job{})
    refute stored?(image)
    refute file?(image)
    assert :ok = Cleanup.perform(%Oban.Job{})

    assert {:error, _} =
             save_section(Atlas.Content.Note, ctx.note.id, :body, [block(image)], ctx.gm)
  end

  test "keeps recent uploads and images referenced by nested blocks in archived notes", ctx do
    recent = image(ctx.gm, false)
    referenced = image(ctx.gm)
    blocks = [Map.put(paragraph("Parent"), "children", [block(referenced)])]
    save_section!(Atlas.Content.Note, ctx.note.id, :body, blocks, ctx.gm)
    ctx.note |> Ash.Changeset.for_update(:archive, %{}, actor: ctx.gm) |> Ash.update!()

    assert :ok = Cleanup.perform(%Oban.Job{})

    for image <- [recent, referenced] do
      assert stored?(image)
      assert file?(image)
    end
  end

  test "keeps shared images until the last reference is removed, including GM-only prep", ctx do
    image = image(ctx.gm)
    save_section!(Atlas.Content.Note, ctx.note.id, :body, [block(image)], ctx.gm)
    save_section!(Atlas.Campaigns.Session, ctx.session.id, :prep, [block(image)], ctx.gm)
    save_section!(Atlas.Content.Note, ctx.note.id, :body, [], ctx.gm)
    assert :ok = Cleanup.perform(%Oban.Job{})
    assert stored?(image)
    assert file?(image)

    save_section!(Atlas.Campaigns.Session, ctx.session.id, :prep, [], ctx.gm)
    assert :ok = Cleanup.perform(%Oban.Job{})
    refute stored?(image)
    refute file?(image)
  end

  test "keeps the portrait of an entry, and deletes it once the entry drops it", ctx do
    image = image(ctx.gm)

    entry =
      Ash.create!(
        Atlas.Content.Entry,
        %{campaign_id: ctx.campaign.id, kind: :npc, name: "Vex", image_id: image.id},
        actor: ctx.gm
      )

    assert :ok = Cleanup.perform(%Oban.Job{})
    assert stored?(image)
    assert file?(image)

    entry
    |> Ash.Changeset.for_update(:update_details, %{image_id: nil}, actor: ctx.gm)
    |> Ash.update!()

    assert :ok = Cleanup.perform(%Oban.Job{})
    refute stored?(image)
  end

  test "missing objects do not prevent metadata cleanup", ctx do
    image = image(ctx.gm)
    assert :ok = Atlas.Storage.delete(image.storage_key)
    assert :ok = Cleanup.perform(%Oban.Job{})
    refute stored?(image)
  end

  test "storage failures keep metadata for a retry", ctx do
    image = image(ctx.gm)
    root = Application.fetch_env!(:atlas, Atlas.Storage) |> Keyword.fetch!(:root)
    path = Path.join(root, image.storage_key)
    File.rm!(path)
    File.mkdir!(path)
    on_exit(fn -> File.rmdir(path) end)

    assert {:error, :eperm} = Cleanup.perform(%Oban.Job{})
    assert stored?(image)
    File.rmdir!(path)
    assert :ok = Cleanup.perform(%Oban.Job{})
    refute stored?(image)
  end

  test "cron runs at midnight UTC" do
    config = Application.fetch_env!(:atlas, Oban)
    assert config[:cron][:timezone] == "Etc/UTC"
    assert {"0 0 * * *", Cleanup} in config[:cron][:crontab]
  end
end
