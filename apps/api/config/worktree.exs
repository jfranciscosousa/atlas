# Evaluates to the database name suffix. A linked git worktree has a .git file, not a directory.
# Each worktree gets its own databases, so its migrations never touch another checkout's data.
root = Path.expand("../../..", __DIR__)

if File.regular?(Path.join(root, ".git")) do
  slug =
    root
    |> Path.basename()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.slice(0, 40)

  "_" <> slug
else
  ""
end
