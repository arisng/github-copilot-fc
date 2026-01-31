# Hybrid Approach Template (Bash Script)

For hybrid E2E testing, use this reusable bash template to automate CLI workflows with manual verification. Customize the variables and steps for your use case. Assumes the conventional folder structure from [FOLDER_STRUCTURE.md](FOLDER_STRUCTURE.md).

```bash
#!/bin/bash
# Hybrid E2E Test Template - [Test Description]
# Automates playwright-cli interactions with manual screenshot verification

set -e

# === CONFIGURATION (Customize these) ===
SESSION_DIR="$(pwd)"  # Current working directory (run script from test-session/ root)
PROJECT_ROOT="$(cd ../.. && pwd)"  # Adjust path as needed (e.g., repository root)
SCREENSHOTS_DIR="$SESSION_DIR/screenshots"
APP_URL="[YOUR_APP_URL]"  # e.g., http://localhost:3000
SERVER_URL="[YOUR_SERVER_URL]"  # Optional: e.g., http://localhost:5000
CLIENT_URL="$APP_URL"  # If different from APP_URL
BROWSER_PROFILE="[PROFILE]"  # e.g., chromium.json

# Optional: Server startup (uncomment and customize if needed)
# SERVER_CMD="cd $PROJECT_ROOT && dotnet run"
# CLIENT_CMD="cd $PROJECT_ROOT/client && npm start"

echo "=== Hybrid E2E Test: [Test Description] ==="
echo "Session Directory: $SESSION_DIR"
echo "Project Root: $PROJECT_ROOT"
echo "Screenshots Directory: $SCREENSHOTS_DIR"
echo "App URL: $APP_URL"
echo ""

# === SETUP PHASE ===
# Function to cleanup background processes
cleanup() {
    echo "Cleaning up background processes..."
    # Uncomment and customize if starting servers
    # if [ ! -z "$SERVER_PID" ]; then kill $SERVER_PID 2>/dev/null || true; fi
    # if [ ! -z "$CLIENT_PID" ]; then kill $CLIENT_PID 2>/dev/null || true; fi
}
trap cleanup EXIT

# Optional: Check/start server
# if [ ! -z "$SERVER_URL" ] && ! curl -s "$SERVER_URL" > /dev/null 2>&1; then
#     echo "Starting server..."
#     eval "$SERVER_CMD" > "$SESSION_DIR/server.log" 2>&1 &
#     SERVER_PID=$!
#     echo "Server PID: $SERVER_PID"
#     # Wait for server (customize logic)
# fi

# Optional: Check/start client
# if ! curl -s "$CLIENT_URL" > /dev/null 2>&1; then
#     echo "Starting client..."
#     eval "$CLIENT_CMD" > "$SESSION_DIR/client.log" 2>&1 &
#     CLIENT_PID=$!
#     echo "Client PID: $CLIENT_PID"
#     # Wait for client (customize logic)
# fi

# === EXECUTION PHASE ===
echo "Step 1: Opening browser..."
playwright-cli --config "profiles/$BROWSER_PROFILE" open "$APP_URL"
sleep 3  # Allow page load

# Take initial screenshot
playwright-cli screenshot
LATEST_SCREENSHOT=$(ls -t .playwright-cli/page-*.png 2>/dev/null | head -1)
if [ -n "$LATEST_SCREENSHOT" ]; then
    cp "$LATEST_SCREENSHOT" "$SCREENSHOTS_DIR/01-initial.png"
    echo "✓ Screenshot: 01-initial.png"
fi

# Customize interactions (replace with your steps)
echo "Step 2: Performing interactions..."
# Example: Click an element
playwright-cli click '[SELECTOR]'  # e.g., 'button' or 'e3'
sleep 1

# Example: Fill a form
playwright-cli fill '[INPUT_SELECTOR]' "[INPUT_VALUE]"
sleep 1

# Example: Press Enter
playwright-cli press Enter
sleep 2

# Take post-interaction screenshot
playwright-cli screenshot
LATEST_SCREENSHOT=$(ls -t .playwright-cli/page-*.png 2>/dev/null | head -1)
if [ -n "$LATEST_SCREENSHOT" ]; then
    cp "$LATEST_SCREENSHOT" "$SCREENSHOTS_DIR/02-after-interaction.png"
    echo "✓ Screenshot: 02-after-interaction.png"
fi

# Add more steps as needed...

# === VERIFICATION PHASE ===
echo ""
echo "=== Manual Verification Instructions ==="
echo "Review screenshots in $SCREENSHOTS_DIR for success criteria:"
echo "1. [Describe expected state in 01-initial.png]"
echo "2. [Describe expected state in 02-after-interaction.png]"
echo "..."
echo ""
echo "Run: open $SCREENSHOTS_DIR  # Or use your image viewer"
echo ""

# Optional: Log checks
# if [ -f "$SESSION_DIR/client.log" ]; then
#     if grep -i "error\|exception" "$SESSION_DIR/client.log"; then
#         echo "WARNING: Errors in logs"
#     fi
# fi

echo "=== Test Execution Complete ==="
echo "Screenshots: $SCREENSHOTS_DIR"
echo "SUCCESS: Script executed (manual verification required)"
```

**Usage Tips**:
- Run the script from the `test-session/` folder (set as cwd) to keep all artifact paths relative and ephemeral.
- Replace placeholders (e.g., `[YOUR_APP_URL]`, `[SELECTOR]`) with actual values.
- Add/remove steps in the execution phase based on your workflow.
- Run with `bash scripts/test.sh` after customization.
- For Blazor apps, add waits after interactions (see [BLAZOR_TESTING.md](references/BLAZOR_TESTING.md)).