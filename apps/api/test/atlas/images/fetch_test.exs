defmodule Atlas.Images.FetchTest do
  use ExUnit.Case, async: false

  alias Atlas.Images.Fetch

  @public {93, 184, 216, 34}

  setup do
    previous = Application.get_env(:atlas, :image_fetch)

    put = fn resolver ->
      Application.put_env(:atlas, :image_fetch,
        resolver: resolver,
        req_options: [plug: {Req.Test, Fetch}]
      )
    end

    put.(fn _host -> [@public] end)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:atlas, :image_fetch, previous),
        else: Application.delete_env(:atlas, :image_fetch)
    end)

    {:ok, put: put}
  end

  test "downloads the body to a temporary file" do
    Req.Test.stub(Fetch, fn conn -> Plug.Conn.send_resp(conn, 200, "image bytes") end)

    assert {:ok, path} = Fetch.download("https://images.example.com/a.png")
    assert File.read!(path) == "image bytes"
    File.rm!(path)
  end

  test "sends the request to the checked address and keeps the host name" do
    Req.Test.stub(Fetch, fn conn ->
      assert conn.host == "93.184.216.34"
      assert Plug.Conn.get_req_header(conn, "host") == ["images.example.com"]
      Plug.Conn.send_resp(conn, 200, "x")
    end)

    assert {:ok, path} = Fetch.download("https://images.example.com/a.png")
    File.rm!(path)
  end

  test "refuses a host with any private address", %{put: put} do
    put.(fn _ -> [@public, {10, 0, 0, 5}] end)

    assert {:error, "must not point to a private address"} =
             Fetch.download("https://x.example/a.png")
  end

  test "refuses URLs that are not http or https, or have no host" do
    for url <- ["ftp://x.example/a.png", "file:///etc/passwd", "https:///a.png", "not a url", ""] do
      assert {:error, "must be an http or https URL"} = Fetch.download(url)
    end
  end

  test "refuses a host that does not resolve", %{put: put} do
    put.(fn _ -> [] end)

    assert {:error, "has a host that does not resolve"} =
             Fetch.download("https://x.example/a.png")
  end

  test "does not follow a redirect" do
    Req.Test.stub(Fetch, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://127.0.0.1/")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert {:error, "answered with status 302"} = Fetch.download("https://x.example/a.png")
  end

  test "stops a body above the size limit" do
    Req.Test.stub(Fetch, fn conn ->
      Plug.Conn.send_resp(conn, 200, :binary.copy("a", Atlas.Images.Processor.max_bytes() + 1))
    end)

    assert {:error, "is larger than 25 MB"} = Fetch.download("https://x.example/a.png")
  end

  test "classifies addresses" do
    private = [
      {127, 0, 0, 1},
      {10, 1, 2, 3},
      {172, 16, 0, 1},
      {192, 168, 1, 1},
      {169, 254, 169, 254},
      {100, 64, 0, 1},
      {0, 0, 0, 0},
      {224, 0, 0, 1},
      {0, 0, 0, 0, 0, 0, 0, 1},
      {0xFC00, 0, 0, 0, 0, 0, 0, 1},
      {0xFE80, 0, 0, 0, 0, 0, 0, 1},
      {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}
    ]

    for address <- private, do: refute(Fetch.public?(address), inspect(address))

    for address <- [
          @public,
          {8, 8, 8, 8},
          {172, 32, 0, 1},
          {0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}
        ],
        do: assert(Fetch.public?(address), inspect(address))
  end
end
