#!/bin/bash
# start.sh - Wizard-first startup for Linux / macOS
# Usage: chmod +x start.sh && ./start.sh

PORT=3000
DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect browser open command
if command -v xdg-open &>/dev/null; then
  OPEN_CMD="xdg-open"          # Linux
elif command -v open &>/dev/null; then
  OPEN_CMD="open"               # macOS
else
  OPEN_CMD=""
fi

# Start HTTP server (npx serve preferred, fallback to python3)
if command -v npx &>/dev/null; then
  echo "Starting server with npx serve on port $PORT..."
  npx serve "$DIR" -p $PORT --no-clipboard &>/dev/null &
  SERVER_PID=$!
  sleep 2
elif command -v python3 &>/dev/null; then
  echo "Starting server with python3 on port $PORT..."
  python3 -m http.server $PORT --directory "$DIR" &>/dev/null &
  SERVER_PID=$!
  sleep 1
else
  echo "ERROR: npx (Node.js) or python3 is required."
  exit 1
fi

URL="http://localhost:$PORT/wizard.html"

if [ -n "$OPEN_CMD" ]; then
  $OPEN_CMD "$URL"
  echo "Opened: $URL"
else
  echo "Please open manually: $URL"
fi

echo ""
echo "Setup wizard -> configure -> 'チャット画面を開く'"
echo "Press Ctrl+C to stop the server."
echo ""

# Wait and clean up on exit
trap "kill $SERVER_PID 2>/dev/null; echo 'Server stopped.'" EXIT
wait $SERVER_PID
