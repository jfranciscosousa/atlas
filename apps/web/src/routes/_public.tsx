import { createFileRoute, Outlet } from "@tanstack/react-router";
import { sessionRequest } from "../lib/auth";

export const Route = createFileRoute("/_public")({
  beforeLoad: () => sessionRequest("/api/session"),
  component: Outlet,
});
