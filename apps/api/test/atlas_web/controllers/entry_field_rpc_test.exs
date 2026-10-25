defmodule AtlasWeb.EntryFieldRpcTest do
  @moduledoc """
  Custom fields through the app (RPC actions) and through MCP. Both must show the same fields and
  values to the same person, and a player must never receive a GM-only field or its values.
  """
  use AtlasWeb.ConnCase, async: true

  import AtlasWeb.McpHelpers, only: [token_for: 1, ok!: 3, call: 3]
  import AtlasWeb.RpcHelpers

  @field_attrs [
    "id",
    "campaignId",
    "kind",
    "label",
    "type",
    "options",
    "gmOnly",
    "position",
    "archivedAt"
  ]
  @entry_attrs ["id", "name", "customValues"]

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    gm = register(conn, "gm@example.com")
    outsider = register(conn, "outsider@example.com")

    assert %{"success" => true, "data" => %{"id" => campaign_id}} =
             rpc(gm, "create_campaign", %{input: %{name: "Eberron"}, fields: ["id"]})

    assert %{"success" => true, "data" => %{"token" => token}} =
             rpc(gm, "create_invitation", %{input: %{campaignId: campaign_id}, fields: ["token"]})

    player = register(conn, "ann@example.com")

    assert %{"success" => true} =
             rpc(player, "join_campaign", %{input: %{token: token}, fields: ["id"]})

    ctx = %{
      gm: gm,
      player: player,
      outsider: outsider,
      campaign_id: campaign_id,
      gm_token: token_for(Atlas.Fixtures.user_by_email("gm@example.com")),
      player_token: token_for(Atlas.Fixtures.user_by_email("ann@example.com")),
      outsider_token: token_for(Atlas.Fixtures.user_by_email("outsider@example.com"))
    }

    # The Eberron example of the GM.
    dragonmark = field(ctx, "faction", "Dragonmark", "text")
    house = field(ctx, "faction", "House name", "text")
    kingdom = field(ctx, "location", "Kingdom", "entry", %{targetKind: "location"})
    population = field(ctx, "location", "Population", "number")

    allegiance =
      field(ctx, "npc", "True allegiance", "entry", %{targetKind: "faction", gmOnly: true})

    {:ok,
     Map.merge(ctx, %{
       dragonmark: dragonmark,
       house: house,
       kingdom: kingdom,
       population: population,
       allegiance: allegiance
     })}
  end

  defp field(ctx, kind, label, type, extra \\ %{}) do
    assert %{"success" => true, "data" => data} =
             rpc(ctx.gm, "create_entry_field", %{
               input:
                 Map.merge(
                   %{campaignId: ctx.campaign_id, kind: kind, label: label, type: type},
                   extra
                 ),
               fields: @field_attrs
             })

    data
  end

  defp entry(ctx, kind, name, extra \\ %{}, shown \\ true) do
    assert %{"success" => true, "data" => %{"id" => id} = data} =
             rpc(ctx.gm, "create_entry", %{
               input: Map.merge(%{campaignId: ctx.campaign_id, kind: kind, name: name}, extra),
               fields: ["id"]
             })

    if shown do
      assert %{"success" => true} =
               rpc(ctx.gm, "set_entry_hidden", %{
                 identity: id,
                 input: %{hidden: false},
                 fields: ["id"]
               })
    end

    data
  end

  defp set_values(ctx, id, values) do
    rpc(ctx.gm, "update_entry", %{
      identity: id,
      input: %{customValues: values},
      fields: @entry_attrs
    })
  end

  defp app_entry(who, id) do
    assert %{"success" => true, "data" => data} =
             rpc(who, "get_entry", %{getBy: %{id: id}, fields: @entry_attrs})

    data
  end

  defp app_fields(who, ctx, input \\ %{}) do
    assert %{"success" => true, "data" => data} =
             rpc(who, "list_entry_fields", %{
               input: Map.merge(%{campaignId: ctx.campaign_id}, input),
               fields: @field_attrs
             })

    data
  end

  defp viewer(ctx, :gm), do: {ctx.gm, ctx.gm_token}
  defp viewer(ctx, :player), do: {ctx.player, ctx.player_token}

  describe "the GM manages fields" do
    test "creates, renames, reorders, archives and restores through the app", ctx do
      assert %{
               "label" => "Kingdom",
               "type" => "entry",
               "options" => %{"target_kind" => "location"},
               "position" => 0
             } = ctx.kingdom

      assert %{"position" => 1, "gmOnly" => false} = ctx.population

      assert %{"success" => true, "data" => %{"label" => "Realm", "gmOnly" => true}} =
               rpc(ctx.gm, "update_entry_field", %{
                 identity: ctx.kingdom["id"],
                 input: %{label: "Realm", gmOnly: true},
                 fields: @field_attrs
               })

      assert %{"success" => true, "data" => %{"position" => 0}} =
               rpc(ctx.gm, "move_entry_field", %{
                 identity: ctx.population["id"],
                 input: %{position: 0},
                 fields: @field_attrs
               })

      assert ["Population", "Realm"] ==
               ctx.gm |> app_fields(ctx, %{kind: "location"}) |> Enum.map(& &1["label"])

      assert %{"success" => true, "data" => %{"archivedAt" => archived}} =
               rpc(ctx.gm, "archive_entry_field", %{
                 identity: ctx.population["id"],
                 input: %{},
                 fields: @field_attrs
               })

      assert archived

      assert ["Realm"] ==
               ctx.gm |> app_fields(ctx, %{kind: "location"}) |> Enum.map(& &1["label"])

      assert ["Population"] ==
               ctx.gm
               |> app_fields(ctx, %{kind: "location", archived: true})
               |> Enum.map(& &1["label"])

      assert %{"success" => true, "data" => %{"archivedAt" => nil, "position" => 2}} =
               rpc(ctx.gm, "restore_entry_field", %{
                 identity: ctx.population["id"],
                 input: %{},
                 fields: @field_attrs
               })
    end

    test "a player and a non-member cannot write", ctx do
      for who <- [ctx.player, ctx.outsider] do
        assert %{"success" => false} =
                 rpc(who, "create_entry_field", %{
                   input: %{campaignId: ctx.campaign_id, kind: "npc", label: "Mine", type: "text"},
                   fields: ["id"]
                 })

        for {action, input} <- [
              {"update_entry_field", %{label: "Mine"}},
              {"move_entry_field", %{position: 0}},
              {"archive_entry_field", %{}},
              {"restore_entry_field", %{}}
            ] do
          assert %{"success" => false} =
                   rpc(who, action, %{
                     identity: ctx.dragonmark["id"],
                     input: input,
                     fields: ["id"]
                   })
        end
      end

      assert "Dragonmark" == hd(app_fields(ctx.gm, ctx, %{kind: "faction"}))["label"]
    end

    test "MCP offers the same actions, and has no delete", ctx do
      tools = ok_tools(ctx.gm_token)

      for tool <-
            ~w(list_entry_fields create_entry_field update_entry_field move_entry_field archive_entry_field restore_entry_field),
          do: assert(tool in tools)

      refute Enum.any?(tools, &String.contains?(&1, "delete_entry_field"))
      refute Enum.any?(tools, &String.contains?(&1, "destroy_entry_field"))

      assert %{
               "id" => id,
               "label" => "Path",
               "options" => %{"choices" => ["Preserver", "Defiler"]}
             } =
               ok!(ctx.gm_token, "create_entry_field", %{
                 input: %{
                   campaign_id: ctx.campaign_id,
                   kind: "npc",
                   label: "Path",
                   type: "select",
                   choices: ["Preserver", "Defiler"]
                 }
               })

      assert %{"label" => "Way"} =
               ok!(ctx.gm_token, "update_entry_field", %{id: id, input: %{label: "Way"}})

      assert %{"position" => 0} =
               ok!(ctx.gm_token, "move_entry_field", %{id: id, input: %{position: 0}})

      assert %{"archived_at" => at} =
               ok!(ctx.gm_token, "archive_entry_field", %{id: id, input: %{}})

      assert at

      restored = ok!(ctx.gm_token, "restore_entry_field", %{id: id, input: %{}})
      refute restored["archived_at"]

      labels =
        ok!(ctx.gm_token, "list_entry_fields", %{
          input: %{campaign_id: ctx.campaign_id, kind: "npc"}
        })

      assert ["True allegiance", "Way"] == labels |> Enum.map(& &1["label"]) |> Enum.sort()

      assert {true, _} =
               call(ctx.player_token, "create_entry_field", %{
                 input: %{campaign_id: ctx.campaign_id, kind: "npc", label: "Mine", type: "text"}
               })

      assert {true, _} =
               call(ctx.player_token, "update_entry_field", %{id: id, input: %{label: "Mine"}})
    end

    test "a select option rename and a refused removal work through both", ctx do
      path = field(ctx, "npc", "Path", "select", %{choices: ["Preserver", "Defiler"]})
      vex = entry(ctx, "npc", "Vex")
      assert %{"success" => true} = set_values(ctx, vex["id"], %{path["id"] => "Defiler"})

      assert %{"success" => false} =
               rpc(ctx.gm, "update_entry_field", %{
                 identity: path["id"],
                 input: %{choices: ["Preserver"]},
                 fields: ["id"]
               })

      assert {true, text} =
               call(ctx.gm_token, "update_entry_field", %{
                 id: path["id"],
                 input: %{choices: ["Preserver"]}
               })

      assert text =~ "Defiler"

      assert %{"success" => true} =
               rpc(ctx.gm, "update_entry_field", %{
                 identity: path["id"],
                 input: %{
                   choices: ["Preserver", "Despoiler"],
                   renamedChoices: %{"Defiler" => "Despoiler"}
                 },
                 fields: ["id"]
               })

      assert %{"label" => "Path", "value" => "Despoiler"} =
               ok!(ctx.gm_token, "get_entry", %{input: %{id: vex["id"]}})["custom_values"]
               |> Enum.find(&(&1["label"] == "Path"))
    end
  end

  describe "values" do
    test "House Cannith shows its Dragonmark to the players, and True allegiance is GM-only",
         ctx do
      cannith = entry(ctx, "faction", "House Cannith")
      vex = entry(ctx, "npc", "Vex")

      assert %{"success" => true} =
               set_values(ctx, cannith["id"], %{
                 ctx.dragonmark["id"] => "Mark of Making",
                 ctx.house["id"] => "Cannith"
               })

      assert %{"success" => true} =
               set_values(ctx, vex["id"], %{ctx.allegiance["id"] => cannith["id"]})

      assert %{"label" => "Dragonmark", "value" => "Mark of Making"} =
               cannith["id"]
               |> then(&app_entry(ctx.player, &1))
               |> Map.fetch!("customValues")
               |> Enum.find(&(&1["label"] == "Dragonmark"))

      assert [
               %{
                 "label" => "True allegiance",
                 "gm_only" => true,
                 "value" => %{"label" => "House Cannith"}
               }
             ] =
               app_entry(ctx.gm, vex["id"])["customValues"]

      assert [] == app_entry(ctx.player, vex["id"])["customValues"]
      assert [] == ok!(ctx.player_token, "get_entry", %{input: %{id: vex["id"]}})["custom_values"]

      for body <- [
            Jason.encode!(app_entry(ctx.player, vex["id"])),
            Jason.encode!(ok!(ctx.player_token, "get_entry", %{input: %{id: vex["id"]}})),
            Jason.encode!(app_fields(ctx.player, ctx)),
            Jason.encode!(
              ok!(ctx.player_token, "list_entry_fields", %{input: %{campaign_id: ctx.campaign_id}})
            )
          ] do
        refute body =~ "allegiance"
        refute body =~ ctx.allegiance["id"]
      end
    end

    test "the raw stored values are not an API field", ctx do
      vex = entry(ctx, "npc", "Vex")

      for who <- [ctx.gm, ctx.player] do
        assert %{"success" => false} =
                 rpc(who, "get_entry", %{getBy: %{id: vex["id"]}, fields: ["id", "customFields"]})
      end
    end

    test "an entry value that a player cannot read shows Restricted entry with no ID", ctx do
      aundair = entry(ctx, "location", "Aundair", %{}, false)
      sharn = entry(ctx, "location", "Sharn")

      assert %{"success" => true} =
               set_values(ctx, sharn["id"], %{ctx.kingdom["id"] => aundair["id"]})

      gm_view = fn who ->
        app_entry(who, sharn["id"])["customValues"] |> Enum.find(&(&1["label"] == "Kingdom"))
      end

      assert %{"value" => %{"label" => "Aundair", "id" => aundair_id, "shown" => false}} =
               gm_view.(ctx.gm)

      assert aundair_id == aundair["id"]

      player = gm_view.(ctx.player)

      assert %{"value" => %{"label" => "Restricted entry", "id" => nil, "restricted" => true}} =
               player

      refute Jason.encode!(player) =~ "Aundair"
      refute Jason.encode!(player) =~ aundair["id"]

      mcp = ok!(ctx.player_token, "get_entry", %{input: %{id: sharn["id"]}})["custom_values"]

      assert %{"value" => %{"label" => "Restricted entry", "id" => nil}} =
               Enum.find(mcp, &(&1["label"] == "Kingdom"))
    end

    test "the app and MCP refuse the same bad values", ctx do
      sharn = entry(ctx, "location", "Sharn")

      for bad <- [
            %{ctx.population["id"] => "many"},
            %{ctx.kingdom["id"] => sharn["id"] <> "x"},
            %{ctx.dragonmark["id"] => "x"},
            %{"nope" => "x"}
          ] do
        assert %{"success" => false} = set_values(ctx, sharn["id"], bad)

        assert {true, _} =
                 call(ctx.gm_token, "update_entry", %{
                   id: sharn["id"],
                   input: %{custom_values: bad}
                 })
      end

      assert %{"success" => false} =
               rpc(ctx.player, "update_entry", %{
                 identity: sharn["id"],
                 input: %{customValues: %{ctx.population["id"] => 5}},
                 fields: ["id"]
               })

      assert {true, _} =
               call(ctx.player_token, "update_entry", %{
                 id: sharn["id"],
                 input: %{custom_values: %{ctx.population["id"] => 5}}
               })
    end

    test "MCP writes values by field ID", ctx do
      sharn = entry(ctx, "location", "Sharn")

      assert %{"id" => _} =
               ok!(ctx.gm_token, "update_entry", %{
                 id: sharn["id"],
                 input: %{custom_values: %{ctx.population["id"] => 2_000_000}}
               })

      assert %{"value" => 2_000_000, "type" => "number"} =
               ok!(ctx.gm_token, "get_entry", %{input: %{id: sharn["id"]}})["custom_values"]
               |> Enum.find(&(&1["label"] == "Population"))
    end
  end

  describe "the app and MCP match" do
    setup ctx do
      aundair = entry(ctx, "location", "Aundair")
      breland = entry(ctx, "location", "Breland")
      secret = entry(ctx, "location", "Hidden realm", %{}, false)
      cannith = entry(ctx, "faction", "House Cannith")
      vex = entry(ctx, "npc", "Vex")

      assert %{"success" => true} =
               set_values(ctx, cannith["id"], %{
                 ctx.dragonmark["id"] => "Mark of Making",
                 ctx.house["id"] => "Cannith"
               })

      assert %{"success" => true} =
               set_values(ctx, vex["id"], %{ctx.allegiance["id"] => cannith["id"]})

      locations =
        for {name, kingdom, population} <- [
              {"Fairhaven", aundair, 300_000},
              {"Sharn", breland, 2_000_000},
              {"Wroat", aundair, 3},
              {"Lost", secret, 9}
            ] do
          l = entry(ctx, "location", name)

          assert %{"success" => true} =
                   set_values(ctx, l["id"], %{
                     ctx.kingdom["id"] => kingdom["id"],
                     ctx.population["id"] => population
                   })

          l
        end

      {:ok,
       aundair: aundair,
       breland: breland,
       cannith: cannith,
       vex: vex,
       locations: locations,
       secret: secret}
    end

    for who <- [:gm, :player] do
      test "the fields and the values are alike for the #{who}", ctx do
        {app, token} = viewer(ctx, unquote(who))

        app_list = app_fields(app, ctx)
        mcp_list = ok!(token, "list_entry_fields", %{input: %{campaign_id: ctx.campaign_id}})

        assert Enum.map(
                 app_list,
                 &{&1["id"], &1["label"], &1["type"], &1["gmOnly"], &1["position"]}
               ) ==
                 Enum.map(
                   mcp_list,
                   &{&1["id"], &1["label"], &1["type"], &1["gm_only"], &1["position"]}
                 )

        if unquote(who) == :player do
          refute "True allegiance" in Enum.map(app_list, & &1["label"])
        else
          assert "True allegiance" in Enum.map(app_list, & &1["label"])
        end

        entries = [ctx.cannith, ctx.vex, ctx.aundair, ctx.secret | ctx.locations]

        for %{"id" => id} <- entries do
          app_view = rpc(app, "get_entry", %{getBy: %{id: id}, fields: @entry_attrs})

          case app_view do
            %{"success" => true, "data" => data} ->
              mcp = ok!(token, "get_entry", %{input: %{id: id}})
              assert data["customValues"] == mcp["custom_values"]

            %{"success" => false} ->
              # A hidden entry: a player reads neither through the app nor through MCP.
              assert {true, _} = call(token, "get_entry", %{input: %{id: id}})
          end
        end
      end

      test "the filter keeps the same entries for the #{who}", ctx do
        {app, token} = viewer(ctx, unquote(who))

        for kingdom <- [ctx.aundair, ctx.breland, ctx.secret] do
          app_names =
            rpc(app, "list_entries", %{
              input: %{
                campaignId: ctx.campaign_id,
                customFieldId: ctx.kingdom["id"],
                customFieldValue: kingdom["id"]
              },
              fields: ["id", "name"]
            })

          mcp =
            call(token, "list_entries", %{
              input: %{
                campaign_id: ctx.campaign_id,
                custom_field_id: ctx.kingdom["id"],
                custom_field_value: kingdom["id"]
              }
            })

          case {app_names, mcp} do
            {%{"success" => true, "data" => data}, {false, text}} ->
              assert Enum.sort(Enum.map(data, & &1["name"])) ==
                       text |> Jason.decode!() |> Enum.map(& &1["name"]) |> Enum.sort()

            {%{"success" => false}, {true, _}} ->
              # The player cannot read that entry: both refuse the filter.
              assert true
          end
        end

        assert %{"success" => true, "data" => data} =
                 rpc(app, "list_entries", %{
                   input: %{
                     campaignId: ctx.campaign_id,
                     customFieldId: ctx.kingdom["id"],
                     customFieldValue: ctx.aundair["id"]
                   },
                   fields: ["name"]
                 })

        assert ["Fairhaven", "Wroat"] == data |> Enum.map(& &1["name"]) |> Enum.sort()
      end
    end

    test "both refuse a filter by a GM-only field for a player, with the same error as for a missing one",
         ctx do
      args = %{
        campaign_id: ctx.campaign_id,
        custom_field_id: ctx.allegiance["id"],
        custom_field_value: ctx.cannith["id"]
      }

      assert {false, _} = call(ctx.gm_token, "list_entries", %{input: args})
      {true, secret} = call(ctx.player_token, "list_entries", %{input: args})

      {true, missing} =
        call(ctx.player_token, "list_entries", %{
          input: %{args | custom_field_id: Ecto.UUID.generate()}
        })

      assert String.replace(secret, ctx.allegiance["id"], "ID") ==
               String.replace(missing, args.custom_field_id, "ID")

      assert %{"success" => false} =
               rpc(ctx.player, "list_entries", %{
                 input: %{
                   campaignId: ctx.campaign_id,
                   customFieldId: ctx.allegiance["id"],
                   customFieldValue: ctx.cannith["id"]
                 },
                 fields: ["id"]
               })
    end

    test "an archived field is gone from both, and back after a restore", ctx do
      assert %{"success" => true} =
               rpc(ctx.gm, "archive_entry_field", %{
                 identity: ctx.dragonmark["id"],
                 input: %{},
                 fields: ["id"]
               })

      for {app, token} <- [viewer(ctx, :gm), viewer(ctx, :player)] do
        assert [] ==
                 app_entry(app, ctx.cannith["id"])["customValues"]
                 |> Enum.filter(&(&1["label"] == "Dragonmark"))

        assert [] ==
                 ok!(token, "get_entry", %{input: %{id: ctx.cannith["id"]}})["custom_values"]
                 |> Enum.filter(&(&1["label"] == "Dragonmark"))

        refute "Dragonmark" in Enum.map(app_fields(app, ctx), & &1["label"])
      end

      assert %{"success" => true} =
               rpc(ctx.gm, "restore_entry_field", %{
                 identity: ctx.dragonmark["id"],
                 input: %{},
                 fields: ["id"]
               })

      assert %{"value" => "Mark of Making"} =
               app_entry(ctx.player, ctx.cannith["id"])["customValues"]
               |> Enum.find(&(&1["label"] == "Dragonmark"))
    end
  end

  defp ok_tools(token) do
    response =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> json_response(200)

    Enum.map(response["result"]["tools"], & &1["name"])
  end
end
