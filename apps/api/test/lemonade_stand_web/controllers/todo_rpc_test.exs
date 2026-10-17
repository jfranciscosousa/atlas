defmodule LemonadeStandWeb.TodoRpcTest do
  use LemonadeStandWeb.ConnCase, async: true

  alias LemonadeStand.Tasks.Todo

  @fields ["id", "title", "completed"]

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "a user can create, list, complete, reopen, and delete a todo", %{conn: conn} do
    user = register(conn, "owner@example.com")

    assert %{
             "success" => true,
             "data" => %{"id" => id, "title" => "Buy lemons", "completed" => false}
           } =
             rpc(user, "create_todo", %{input: %{title: "  Buy lemons  "}, fields: @fields})

    assert %{"success" => true, "data" => [%{"id" => ^id}]} =
             rpc(user, "list_todos", %{fields: @fields})

    for completed <- [true, false] do
      assert %{"success" => true, "data" => %{"id" => ^id, "completed" => ^completed}} =
               rpc(user, "update_todo", %{
                 identity: id,
                 input: %{completed: completed},
                 fields: @fields
               })
    end

    assert %{"success" => true} = rpc(user, "destroy_todo", %{identity: id})
    assert %{"success" => true, "data" => []} = rpc(user, "list_todos", %{fields: @fields})
  end

  test "users cannot list, update, or delete another user's todos", %{conn: conn} do
    owner = register(conn, "owner@example.com")
    other = register(conn, "other@example.com")

    assert %{"success" => true, "data" => %{"id" => id}} =
             rpc(owner, "create_todo", %{input: %{title: "Private todo"}, fields: @fields})

    assert %{"success" => true, "data" => []} = rpc(other, "list_todos", %{fields: @fields})

    assert %{"success" => true, "data" => []} =
             rpc(other, "list_todos", %{fields: @fields, filter: %{id: %{eq: id}}})

    assert %{"success" => false} =
             rpc(other, "update_todo", %{identity: id, input: %{completed: true}, fields: @fields})

    assert %{"success" => true} = rpc(other, "destroy_todo", %{identity: id})

    assert %{"success" => true, "data" => [%{"id" => ^id, "completed" => false}]} =
             rpc(owner, "list_todos", %{fields: @fields})
  end

  test "anonymous requests cannot use todo actions", %{conn: conn} do
    owner = register(conn, "owner@example.com")

    %{"data" => %{"id" => id}} =
      rpc(owner, "create_todo", %{input: %{title: "Private todo"}, fields: @fields})

    for {action, params} <- [
          {"list_todos", %{fields: @fields}},
          {"create_todo", %{input: %{title: "Anonymous todo"}, fields: @fields}},
          {"update_todo", %{identity: id, input: %{completed: true}, fields: @fields}},
          {"destroy_todo", %{identity: id}}
        ] do
      assert %{"error" => "Sign in to continue."} = rpc(conn, action, params, 401)
    end
  end

  test "anonymous requests cannot validate todo actions", %{conn: conn} do
    session = get(conn, ~p"/api/session")
    token = json_response(session, 200)["csrfToken"]

    response =
      session
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", token)
      |> post(~p"/rpc/validate", %{action: "create_todo", input: %{title: "Buy lemons"}})

    assert %{"error" => "Sign in to continue."} = json_response(response, 401)
  end

  test "titles must be present and contain at most 200 characters", %{conn: conn} do
    user = register(conn, "owner@example.com")

    for input <- [%{}, %{title: ""}, %{title: "   "}, %{title: String.duplicate("a", 201)}] do
      assert %{"success" => false, "errors" => [_ | _]} =
               rpc(user, "create_todo", %{input: input, fields: @fields})
    end

    assert %{"success" => true, "data" => []} = rpc(user, "list_todos", %{fields: @fields})
  end

  @tag capture_log: true
  test "clients cannot assign or transfer ownership", %{conn: conn} do
    owner = register(conn, "owner@example.com")
    other = register(conn, "other@example.com")
    other_id = json_response(other, 200)["user"]["id"]
    owner_id = json_response(owner, 200)["user"]["id"]

    assert %{"success" => false} =
             rpc(owner, "create_todo", %{
               input: %{title: "Owned", userId: other_id},
               fields: @fields
             })

    %{"data" => %{"id" => id}} =
      rpc(owner, "create_todo", %{input: %{title: "Owned"}, fields: @fields})

    assert %{"success" => false} =
             rpc(owner, "update_todo", %{
               identity: id,
               input: %{userId: other_id},
               fields: @fields
             })

    assert Ash.get!(Todo, id, authorize?: false).user_id == owner_id
    assert %{"success" => true, "data" => []} = rpc(other, "list_todos", %{fields: @fields})
  end

  test "validation reports invalid titles without creating records", %{conn: conn} do
    user = register(conn, "owner@example.com")
    session = user |> recycle() |> get(~p"/api/session")
    token = json_response(session, 200)["csrfToken"]

    response =
      session
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", token)
      |> post(~p"/rpc/validate", %{action: "create_todo", input: %{title: " "}})

    assert %{"success" => false, "errors" => [_ | _]} = json_response(response, 200)
    assert %{"success" => true, "data" => []} = rpc(user, "list_todos", %{fields: @fields})
  end

  defp register(conn, email) do
    response =
      post(conn, ~p"/auth/user/password/register",
        user: %{
          email: email,
          password: "a-secure-password",
          password_confirmation: "a-secure-password"
        }
      )

    assert %{"user" => %{"id" => _}} = json_response(response, 200)
    response
  end

  defp rpc(conn, action, params, status \\ 200) do
    session = conn |> recycle() |> get(~p"/api/session")
    token = json_response(session, 200)["csrfToken"]

    session
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
    |> post(~p"/rpc/run", Map.put(params, :action, action))
    |> json_response(status)
  end
end
