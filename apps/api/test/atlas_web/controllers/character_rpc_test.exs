defmodule AtlasWeb.CharacterRpcTest do
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.RpcHelpers
  import Atlas.Fixtures, only: [paragraph: 1]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    player = register(conn, "player@example.com")
    stranger = register(conn, "stranger@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "The Sunken Keep"}, fields: ["id"]})

    {:ok, gm: gm, player: player, stranger: stranger, campaign_id: campaign_id, conn: conn}
  end

  defp invite(ctx) do
    rpc(ctx.gm, "create_invitation", %{
      input: %{campaignId: ctx.campaign_id},
      fields: ["id", "token"]
    })
  end

  defp join(who, token),
    do: rpc(who, "join_campaign", %{input: %{token: token}, fields: ["id", "campaignId"]})

  defp get_campaign(who, id, fields \\ ["id", "name", "isGm", "gmName"]),
    do: rpc(who, "get_campaign", %{getBy: %{id: id}, fields: fields})

  defp not_found?(%{"success" => false, "errors" => [%{"type" => type} | _]}),
    do: type in ["not_found", "forbidden"]

  defp not_found?(_), do: false

  test "the GM creates one active invitation and can read it again", ctx do
    assert %{"success" => true, "data" => %{"token" => token}} = invite(ctx)

    assert %{"success" => true, "data" => %{"token" => ^token}} =
             rpc(ctx.gm, "get_active_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => false} = invite(ctx)
  end

  test "a player joins with the link, reads the campaign, and cannot change it", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)

    assert not_found?(get_campaign(ctx.player, ctx.campaign_id))

    assert %{"success" => true, "data" => %{"campaignId" => campaign_id}} =
             join(ctx.player, token)

    assert campaign_id == ctx.campaign_id

    assert %{"success" => true, "data" => %{"isGm" => false, "gmName" => "Test User"}} =
             get_campaign(ctx.player, ctx.campaign_id)

    assert %{"success" => true, "data" => [%{"id" => ^campaign_id}]} =
             rpc(ctx.player, "list_campaigns", %{fields: ["id", "isGm"]})

    assert %{"success" => true, "data" => %{"isGm" => true}} =
             get_campaign(ctx.gm, ctx.campaign_id)

    save = fn email ->
      Atlas.Fixtures.save_section(
        Atlas.Campaigns.Campaign,
        ctx.campaign_id,
        :description,
        [paragraph("hi")],
        email
      )
    end

    assert {:error, %Ash.Error.Forbidden{}} = save.("player@example.com")
    assert {:ok, _} = save.("gm@example.com")

    assert %{"success" => true, "data" => [_]} =
             rpc(ctx.player, "list_characters", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id", "playerName", "name"]
             })
  end

  test "joining twice keeps one membership", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true, "data" => %{"id" => id}} = join(ctx.player, token)
    assert %{"success" => true, "data" => %{"id" => ^id}} = join(ctx.player, token)

    assert %{"data" => [_only_one]} =
             rpc(ctx.gm, "list_characters", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end

  test "the GM cannot join their own campaign", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => false} = join(ctx.gm, token)
  end

  test "a revoked link stops new joins but keeps players, and the GM can issue a new link", ctx do
    assert %{"data" => %{"id" => id, "token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    assert %{"success" => true} =
             rpc(ctx.gm, "revoke_invitation", %{identity: id, input: %{}, fields: ["id"]})

    assert %{"success" => false} = join(ctx.stranger, token)
    assert not_found?(get_campaign(ctx.stranger, ctx.campaign_id))
    assert %{"success" => true} = get_campaign(ctx.player, ctx.campaign_id)

    assert %{"success" => true, "data" => nil} =
             rpc(ctx.gm, "get_active_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["token"]
             })

    assert %{"success" => true, "data" => %{"token" => new_token}} = invite(ctx)
    assert new_token != token
    assert %{"success" => true} = join(ctx.stranger, new_token)
  end

  test "an unknown token fails the same way as a revoked one", ctx do
    assert %{"success" => false, "errors" => [%{"message" => message} | _]} =
             join(ctx.player, "nope")

    assert message =~ "no longer valid"
  end

  test "only the GM can create, revoke, or read the link", ctx do
    assert %{"data" => %{"id" => id, "token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    for who <- [ctx.player, ctx.stranger] do
      refute rpc(who, "create_invitation", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })["success"]

      refute rpc(who, "revoke_invitation", %{identity: id, input: %{}, fields: ["id"]})["success"]

      assert %{"success" => true, "data" => nil} =
               rpc(who, "get_active_invitation", %{
                 input: %{campaignId: ctx.campaign_id},
                 fields: ["token"]
               })
    end
  end

  test "a link holder sees the campaign name and GM before joining", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)

    assert %{
             "success" => true,
             "data" => %{"campaignName" => "The Sunken Keep", "gmName" => "Test User"}
           } =
             rpc(ctx.stranger, "get_invitation_by_token", %{
               input: %{token: token},
               fields: ["campaignId", "campaignName", "gmName"]
             })

    assert %{"success" => true, "data" => nil} =
             rpc(ctx.stranger, "get_invitation_by_token", %{
               input: %{token: "nope"},
               fields: ["campaignId"]
             })
  end

  test "a player cannot read a hidden GM note, and non-members cannot list players", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    assert %{"success" => true, "data" => %{"id" => note_id}} =
             rpc(ctx.gm, "create_note", %{
               input: %{campaignId: ctx.campaign_id, title: "Secret plot"},
               fields: ["id"]
             })

    assert %{"success" => true, "data" => []} =
             rpc(ctx.player, "list_notes", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })

    assert not_found?(rpc(ctx.player, "get_note", %{getBy: %{id: note_id}, fields: ["id"]}))

    refute rpc(ctx.stranger, "create_note", %{
             input: %{campaignId: ctx.campaign_id, title: "Mine"},
             fields: ["id"]
           })["success"]

    assert %{"success" => true, "data" => []} =
             rpc(ctx.stranger, "list_characters", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end

  test "every member reads a character's description; its player and the GM write it", ctx do
    other = register(ctx.conn, "other@example.com")
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true, "data" => %{"id" => ann_id}} = join(ctx.player, token)
    assert %{"success" => true} = join(other, token)

    save = fn email, id ->
      Atlas.Fixtures.save_section(
        Atlas.Campaigns.Character,
        id,
        :description,
        [paragraph("A tiefling bard.")],
        email
      )
    end

    assert {:error, %Ash.Error.Forbidden{}} = save.("other@example.com", ann_id)
    assert {:error, %Ash.Error.Forbidden{}} = save.("stranger@example.com", ann_id)
    assert {:ok, %{description_revision: 1}} = save.("gm@example.com", ann_id)
    assert {:ok, %{description_revision: 2}} = save.("player@example.com", ann_id)

    for {reader, mine} <- [{ctx.gm, false}, {ctx.player, true}, {other, false}] do
      assert %{
               "success" => true,
               "data" => %{
                 "isMine" => ^mine,
                 "playerName" => "Test User",
                 "descriptionJson" => [%{"content" => [%{"text" => "A tiefling bard."}]}]
               }
             } =
               rpc(reader, "get_character", %{
                 getBy: %{id: ann_id},
                 fields: ["id", "isMine", "playerName", "descriptionJson"]
               })
    end

    assert not_found?(rpc(ctx.stranger, "get_character", %{getBy: %{id: ann_id}, fields: ["id"]}))
  end

  test "only the GM reads and writes a character's secret notes", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true, "data" => %{"id" => id}} = join(ctx.player, token)

    save = fn email ->
      Atlas.Fixtures.save_section(
        Atlas.Campaigns.Character,
        id,
        :secret_notes,
        [paragraph("Serves the Veiled Alliance.")],
        email
      )
    end

    assert {:error, %Ash.Error.Forbidden{}} = save.("player@example.com")
    assert {:error, %Ash.Error.Forbidden{}} = save.("stranger@example.com")
    assert {:ok, %{secret_notes_revision: 1}} = save.("gm@example.com")

    fields = ["id", "secretNotesJson", "secretNotesRevision"]

    assert %{"success" => true, "data" => %{"secretNotesJson" => [%{"content" => [_]}]}} =
             rpc(ctx.gm, "get_character", %{getBy: %{id: id}, fields: fields})

    assert %{"success" => true, "data" => player_view} =
             rpc(ctx.player, "get_character", %{getBy: %{id: id}, fields: fields})

    assert player_view["secretNotesJson"] == nil
    assert player_view["secretNotesRevision"] == nil
    refute inspect(player_view) =~ "Veiled"
  end

  test "a player adds characters, names them, and only that player or the GM renames them", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true, "data" => %{"id" => first}} = join(ctx.player, token)

    assert %{"success" => true, "data" => %{"id" => second, "name" => nil, "isMine" => true}} =
             rpc(ctx.player, "create_character", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id", "name", "isMine"]
             })

    assert second != first

    rename = fn who, id, name ->
      rpc(who, "rename_character", %{identity: id, input: %{name: name}, fields: ["id", "name"]})
    end

    assert %{"success" => true, "data" => %{"name" => "Gale Voss"}} =
             rename.(ctx.player, second, "  Gale Voss ")

    refute rename.(ctx.stranger, second, "Mine")["success"]
    assert %{"success" => true, "data" => %{"name" => "Gale"}} = rename.(ctx.gm, second, "Gale")
    assert %{"success" => true} = rename.(ctx.player, second, "Gale Voss")

    assert %{"success" => true, "data" => characters} =
             rpc(ctx.gm, "list_characters", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id", "name", "playerName"]
             })

    assert [%{"id" => ^first, "name" => nil}, %{"id" => ^second, "name" => "Gale Voss"}] =
             characters

    # Joining again keeps the first character and adds none.
    assert %{"success" => true, "data" => %{"id" => ^first}} = join(ctx.player, token)
  end

  test "only a player of the campaign adds a character to it", ctx do
    assert %{"data" => %{"token" => token}} = invite(ctx)
    assert %{"success" => true} = join(ctx.player, token)

    for who <- [ctx.gm, ctx.stranger] do
      refute rpc(who, "create_character", %{input: %{campaignId: ctx.campaign_id}, fields: ["id"]})[
               "success"
             ]
    end

    assert %{"data" => [_only_one]} =
             rpc(ctx.gm, "list_characters", %{
               input: %{campaignId: ctx.campaign_id},
               fields: ["id"]
             })
  end

  describe "character status" do
    setup ctx do
      assert %{"data" => %{"token" => token}} = invite(ctx)
      assert %{"success" => true, "data" => %{"id" => id}} = join(ctx.player, token)
      {:ok, character_id: id}
    end

    defp set_status(who, id, status),
      do:
        rpc(who, "set_character_status", %{
          identity: id,
          input: %{status: status},
          fields: ["id", "status"]
        })

    defp status_of(who, ctx) do
      assert %{"success" => true, "data" => [%{"status" => status}]} =
               rpc(who, "list_characters", %{
                 input: %{campaignId: ctx.campaign_id},
                 fields: ["id", "status"]
               })

      status
    end

    test "a character starts active, and every member reads the status", ctx do
      assert status_of(ctx.gm, ctx) == "active"
      assert status_of(ctx.player, ctx) == "active"
    end

    test "only the GM sets the status, in any direction", ctx do
      for status <- ["retired", "dead", "active"] do
        assert %{"success" => true, "data" => %{"status" => ^status}} =
                 set_status(ctx.gm, ctx.character_id, status)

        assert status_of(ctx.player, ctx) == status
      end
    end

    test "a player cannot set the status of their own character", ctx do
      refute set_status(ctx.player, ctx.character_id, "dead")["success"]
      assert status_of(ctx.gm, ctx) == "active"
    end

    test "a stranger cannot set the status", ctx do
      refute set_status(ctx.stranger, ctx.character_id, "dead")["success"]
      assert status_of(ctx.gm, ctx) == "active"
    end

    test "the status must be a known value", ctx do
      refute set_status(ctx.gm, ctx.character_id, "missing")["success"]
      refute set_status(ctx.gm, ctx.character_id, nil)["success"]
      assert status_of(ctx.gm, ctx) == "active"
    end

    test "a dead character keeps its name, its description, and its player", ctx do
      assert %{"success" => true} =
               rpc(ctx.player, "rename_character", %{
                 identity: ctx.character_id,
                 input: %{name: "Gale"},
                 fields: ["id"]
               })

      assert {:ok, _} =
               Atlas.Fixtures.save_section(
                 Atlas.Campaigns.Character,
                 ctx.character_id,
                 :description,
                 [paragraph("Lost at sea")],
                 "player@example.com"
               )

      assert %{"success" => true} = set_status(ctx.gm, ctx.character_id, "dead")

      assert %{"success" => true, "data" => character} =
               rpc(ctx.player, "get_character", %{
                 getBy: %{id: ctx.character_id},
                 fields: ["name", "status", "playerName", "isMine", "descriptionJson"]
               })

      assert %{"name" => "Gale", "status" => "dead", "isMine" => true} = character
      assert inspect(character["descriptionJson"]) =~ "Lost at sea"

      # The player still edits the description and the name.
      assert {:ok, _} =
               Atlas.Fixtures.save_section(
                 Atlas.Campaigns.Character,
                 ctx.character_id,
                 :description,
                 [paragraph("Found again")],
                 "player@example.com"
               )
    end
  end
end
