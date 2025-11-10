# Known Issues & Bug Tracking

## Active Issues

### 🐛 Port check messages not displaying during setup
**Status:** INVESTIGATING  
**Severity:** Medium (UX issue)  
**Reported:** 2025-11-10

**Description:**
When running setup, port checking messages don't appear:
```
Enter Host Port for MySQL (Default: 3306):
   Do you want to use port 3307 instead? (y/n):
```

Missing expected output:
```
Enter Host Port for MySQL (Default: 3306): 3306
Checking if port 3306 is available...
✗ Port not available
Finding next available port...
⚠ Port 3306 is already in use.
   Do you want to use port 3307 instead? (y/n):
```

**Expected Behavior:**
- Show "Checking if port X is available..." message
- Show result: "Port available" or "Port not available"
- Show "Finding next available port..." when searching
- Show warning with port conflict details

**Environment:**
- OS: Windows 11 with WSL2 Ubuntu
- Terminal: WSL Ubuntu terminal
- Running via: install.sh (downloads from GitHub)

**Root Cause:**
User is running `install.sh` which downloads code from GitHub, not local updated version.

**Workaround:**
1. Push changes to GitHub first:
   ```bash
   cd /mnt/d/Development/symfony-docker-thy
   git add .
   git commit -m "feat: enhance port detection UX"
   git push origin main
   ```

2. Then run `install.sh` (will download updated version)

**OR** run setup directly:
```bash
cd /mnt/d/Development/symfony-docker-thy/setup
./setup.sh
```

**Fix Location:**
File: `setup/setup.sh`, lines 188-206 (prompt_for_port function)

**Related Code:**
```bash
# Show checking indicator and flush output
printf "Checking if port %s is available...\n" "$input_port"

# Check if port is available
if check_port $input_port "$service_name"; then
    echoc "32" "✓ Port $input_port is available and will be used"
    selected_port=$input_port
    echo ""
    break
else
    echoc "31" "✗ Port not available"
    echo "Finding next available port..."
    local suggested=$(find_available_port $((input_port + 1)))
    
    echoc "33" "⚠ Port $input_port is already in use."
    read -p "   Do you want to use port $suggested instead? (y/n): " use_suggested
```

**Testing Needed:**
- [ ] Verify messages appear in WSL terminal
- [ ] Verify messages appear in native Linux
- [ ] Verify messages appear via install.sh after GitHub push
- [ ] Test with verbose mode

---

## Resolved Issues

*No resolved issues yet*

---

## Future Enhancements

### Port Detection Improvements
- [ ] Add spinner/progress bar for port checking
- [ ] Reduce port check delay (optimize PowerShell queries)
- [ ] Cache port check results to avoid repeated checks
- [ ] Add parallel port checking for multiple ports

### Input Validation
- [ ] Add length limits for project names
- [ ] Validate port ranges more strictly
- [ ] Add password strength requirements
- [ ] Validate database name against MySQL reserved words

### UX Improvements
- [ ] Add color-coded output themes
- [ ] Add summary screen before starting installation
- [ ] Add progress percentage indicator
- [ ] Add estimated time remaining

---

## Reporting New Issues

To report a new issue:

1. **Via GitHub:**
   ```
   https://github.com/ThyreenAgain/symfony-docker-thy/issues/new
   ```

2. **Information to include:**
   - Operating system and version
   - Terminal used (WSL/native Linux/etc.)
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant logs or screenshots
   - Output of `./setup.sh --verbose`

3. **Labels:**
   - `bug` - Something isn't working
   - `enhancement` - New feature or improvement
   - `documentation` - Documentation improvements
   - `wsl` - Specific to WSL environment
   - `ux` - User experience issues