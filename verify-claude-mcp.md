# Verifying MCP Server in Claude

## Quick Test Commands for Claude

After restarting Claude Code, copy and paste these commands in a new Claude conversation to verify the MCP server is working:

### Test 1: Check if MCP tool is available
```
Can you run list_processes() to show me tracked processes?
```

### Test 2: Look for specific test process
```
Can you run list_processes(process_id='test-install-1761490488')?
```
(Replace with your actual test process ID from installation)

### Test 3: Try reading a log file
```
The install script created a test process. Can you:
1. Use list_processes() to find it
2. Read the stderr log file using the path it provides
```

## Expected Successful Responses

If the MCP server is working, Claude should respond with something like:

✅ **Success looks like:**
```
I'll use the list_processes tool to show tracked processes...

Found 1 process(es):
============================================================
Process ID: test-install-1761490488
Command: bash -c echo 'Test stdout message'...
Status: completed
...
Log Files:
  Combined: /home/user/mcp-process-wrapper/process_logs/test-install-1761490488.log
  Stdout: /home/user/mcp-process-wrapper/process_logs/test-install-1761490488.stdout.log
  Stderr: /home/user/mcp-process-wrapper/process_logs/test-install-1761490488.stderr.log
```

❌ **Failure looks like:**
```
I don't have access to a tool called list_processes
```
or
```
list_processes is not defined
```

## Troubleshooting

### If Claude can't see the MCP server:

1. **Check Claude was fully restarted**
   - Complete shutdown and restart, not just reload
   - All Claude windows/tabs should be closed and reopened

2. **Verify config file exists and is valid**
   ```bash
   cat ~/.claude/mcp.json
   python3 -m json.tool ~/.claude/mcp.json
   ```

3. **Check paths are absolute**
   The mcp.json should have full paths, not relative ones

4. **Look for errors in Claude's console**
   - Open developer tools (F12)
   - Check Console tab for MCP-related errors
   - Look for "Failed to start MCP server" messages

5. **Test Python can run the server manually**
   ```bash
   cd /path/to/mcp-process-wrapper
   python3 mcp_server.py
   ```
   Should see: `Ready to handle MCP requests` or similar

6. **Verify Python path**
   The Python path in mcp.json must be exact:
   ```json
   "command": "/home/ssilver/anaconda3/bin/python3"
   ```

## Manual Test Without Claude

You can test if the MCP server would work by running:

```bash
# Start a test process
./track-it --id manual-test echo "Testing MCP"

# Check it was registered
python3 -c "
import sys
sys.path.append('.')
from process_registry import ProcessRegistry
r = ProcessRegistry()
print(r.list_processes(limit=1))
"
```

If this shows your process, the backend is working and it's just a Claude configuration issue.

## Common Issues

### Issue: "Permission denied"
- Make sure track-it is executable: `chmod +x track-it`
- Check Python path has execute permissions

### Issue: "Module not found: mcp"
- Install MCP package: `pip install mcp`

### Issue: Claude shows old processes but not new ones
- MCP server might be using cached registry
- Try restarting Claude again
- Check if database path in mcp.json matches where track-it writes

### Issue: Paths not found
- MCP config must use absolute paths
- Working directory might be different when Claude starts the server
- Use full paths everywhere in mcp.json

## Success Confirmation

Once Claude can successfully:
1. ✅ Run `list_processes()`
2. ✅ See the test process from installation
3. ✅ Read log files using the provided paths

Then the MCP server is fully integrated and working!
