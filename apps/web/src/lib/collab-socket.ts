import { Socket } from "phoenix";

let socket: Socket | undefined;
let csrfToken = "";

// One WebSocket carries every editor. The CSRF token proves the page knows the session.
export function connectSocket(token: string) {
  csrfToken = token;
  socket ??= new Socket("/socket", {
    params: () => ({ _csrf_token: csrfToken }),
  });
  if (!socket.isConnected()) socket.connect();
  return socket;
}

/** Closes the connection of a signed-out browser. */
export function closeCollabSocket() {
  socket?.disconnect();
  socket = undefined;
}
