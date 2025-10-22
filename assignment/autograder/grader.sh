#!/bin/bash

# Fail on unset vars, continue on command errors (we handle them), and propagate pipe failures
set -uo pipefail

echo "[grader] Starting robust grading..."
echo "[grader] Node version: $(node --version)"
echo "[grader] npm version: $(npm --version)"
echo "[grader] Cypress version: $(npx cypress --version 2>&1 || echo 'not found')"

# Log Coursera environment variables if present
if [ -n "${COURSERA_PART_ID:-}" ]; then
    echo "[grader] Coursera Part ID: ${COURSERA_PART_ID}"
fi
if [ -n "${COURSERA_USER_ID:-}" ]; then
    echo "[grader] Coursera User ID: ${COURSERA_USER_ID}"
fi
if [ -n "${COURSERA_FILENAME:-}" ]; then
    echo "[grader] Coursera Filename: ${COURSERA_FILENAME}"
fi

# Cross-platform timeout function
run_with_timeout() {
    local timeout_secs=$1
    shift
    local cmd=("$@")
    
    # Try native timeout first (Linux)
    if command -v timeout &> /dev/null; then
        timeout "$timeout_secs" "${cmd[@]}"
        return $?
    fi
    
    # Fall back to gtimeout (macOS with GNU coreutils)
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_secs" "${cmd[@]}"
        return $?
    fi
    
    # Last resort: background + sleep + kill (works everywhere but less reliable)
    "${cmd[@]}" &
    local pid=$!
    local count=0
    while kill -0 "$pid" 2>/dev/null && [ $count -lt $timeout_secs ]; do
        sleep 1
        count=$((count + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        return 124  # timeout exit code
    fi
    wait "$pid"
    return $?
}

# Function to detect if we're running in Coursera environment
is_coursera_env() {
    [ -d "/shared" ] || [ -n "${COURSERA_GRADER:-}" ] || [ -n "${COURSERA_PART_ID:-}" ]
}

# Function to get output paths based on environment
get_output_paths() {
    if is_coursera_env; then
        # Check if /shared exists for real Coursera environment
        if [ -d "/shared" ]; then
            FEEDBACK_JSON="/shared/feedback.json"
            HTML_FEEDBACK="/shared/htmlFeedback.html"
            SUBMISSION_DIR="/shared/submission"
        else
            # Coursera simulation mode - use local paths
            FEEDBACK_JSON="./results/feedback.json"
            HTML_FEEDBACK="./results/htmlFeedback.html"
            SUBMISSION_DIR="."
        fi
    else
        FEEDBACK_JSON="./results/feedback.json"
        HTML_FEEDBACK="./results/htmlFeedback.html"
        SUBMISSION_DIR="."
    fi
}

# Function to write error feedback
write_error_feedback() {
    local error_msg="$1"
    echo "[grader] ERROR: $error_msg" >&2
    mkdir -p "$(dirname "$FEEDBACK_JSON")"
    echo "{\"fractionalScore\": 0, \"feedback\": \"$error_msg\", \"feedbackType\": \"HTML\"}" > "$FEEDBACK_JSON"
    echo "<b>$error_msg</b>" > "$HTML_FEEDBACK"
}

# Function to check if npm script exists (read package.json to avoid npm quirks)
npm_script_exists() {
    local script_name="$1"
    if [ -f package.json ]; then
        jq -e --arg s "$script_name" '.scripts[$s] // empty | length > 0' package.json >/dev/null 2>&1
    else
        return 1
    fi
}

# Function to run npm commands with logging and timeout
run_npm_command() {
    local log_file="$1"
    shift

    rm -f "$log_file"
    if run_with_timeout 300 "$@" | tee "$log_file"; then
        return 0
    else
        local status=${PIPESTATUS[0]}
        echo "[grader] npm command failed with exit code $status"
        echo "[grader] --- Last 20 lines of npm output ---"
        tail -20 "$log_file" 2>/dev/null || true
        echo "[grader] --- End npm output ---"
        return $status
    fi
}

# Function to run tests with fallback
run_test_with_fallback() {
    local test_type="$1"
    local primary_script="$2"
    local fallback_script="$3"
    local output_file="$4"
    
    echo "[grader] Running $test_type tests..."
    
    # Try primary script first
    if npm_script_exists "$primary_script"; then
        echo "[grader] Using npm script: $primary_script"
        run_with_timeout 180 npm run "$primary_script" > "$output_file" 2>&1 || true
        return $?
    fi
    
    # Try fallback script
    if npm_script_exists "$fallback_script"; then
        echo "[grader] Using fallback npm script: $fallback_script"
        run_with_timeout 180 npm run "$fallback_script" > "$output_file" 2>&1 || true
        return $?
    fi
    
    # Try direct cypress command
    echo "[grader] Using direct cypress command for $test_type"
    if [ "$test_type" = "component" ]; then
        run_with_timeout 180 npx cypress run --component --reporter json > "$output_file" 2>&1 || true
    else
        run_with_timeout 180 npx cypress run --e2e --reporter json > "$output_file" 2>&1 || true
    fi
    return $?
}

# Function to parse test results from text output
parse_text_results() {
    local input_file="$1"
    local output_file="$2"
    
    # Remove ANSI color codes and extract test counts from the text output
    local clean_output=$(sed 's/\x1b\[[0-9;]*m//g' "$input_file")
    
    # Debug: Show what we're parsing
    echo "[grader] Raw output for parsing:"
    echo "$clean_output" | head -20
    
    # Extract test counts - try multiple patterns for Cypress output
    local total_tests="0"
    local passed_tests="0"
    local failed_tests="0"
    
    # Pattern 1: Cypress table format with pipes
    # │ Tests:        3                                                                                │
    total_tests=$(echo "$clean_output" | grep -o "Tests:[[:space:]]*[0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
    passed_tests=$(echo "$clean_output" | grep -o "Passing:[[:space:]]*[0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
    failed_tests=$(echo "$clean_output" | grep -o "Failing:[[:space:]]*[0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
    
    # Pattern 2: Simple "3 passing" format
    if [ "$total_tests" = "0" ]; then
        passed_tests=$(echo "$clean_output" | grep -o "[0-9]* passing" | grep -o "[0-9]*" | head -1 || echo "0")
        if [ "$passed_tests" != "0" ]; then
            total_tests="$passed_tests"
        fi
    fi
    
    # Pattern 3: Summary line format "✔ All specs passed! 111ms 3 3"
    if [ "$total_tests" = "0" ]; then
        local summary_line=$(echo "$clean_output" | grep "All specs passed" | tail -1)
        if [ -n "$summary_line" ]; then
            # Extract numbers from the end of the line
            local numbers=$(echo "$summary_line" | grep -o "[0-9]*[[:space:]]*[0-9]*[[:space:]]*[0-9]*" | tail -1)
            if [ -n "$numbers" ]; then
                total_tests=$(echo "$numbers" | awk '{print $1}')
                passed_tests=$(echo "$numbers" | awk '{print $2}')
                failed_tests=$(echo "$numbers" | awk '{print $3}')
            fi
        fi
    fi
    
    # Pattern 4: Look for any line with "passing" and extract the number
    if [ "$total_tests" = "0" ]; then
        passed_tests=$(echo "$clean_output" | grep -E "[0-9]+ passing" | grep -o "[0-9]+" | head -1 || echo "0")
        if [ "$passed_tests" != "0" ]; then
            total_tests="$passed_tests"
        fi
    fi
    
    # Debug output
    echo "[grader] Parsed results: total=$total_tests, passed=$passed_tests, failed=$failed_tests"
    
    # Create JSON structure
    cat > "$output_file" << EOF
{
  "stats": {
    "tests": $total_tests,
    "passes": $passed_tests,
    "failures": $failed_tests,
    "pending": 0
  }
}
EOF
}

# Function to extract JSON from mixed output
extract_json_from_output() {
    local input_file="$1"
    local output_file="$2"
    
    # Extract JSON object from the output
    sed -n '/^{/,/^}/p' "$input_file" | head -n -1 > "$output_file" 2>/dev/null || true
    
    # If that didn't work, try to find JSON lines
    if [ ! -s "$output_file" ]; then
        grep -E '^\{.*\}$' "$input_file" > "$output_file" 2>/dev/null || true
    fi
    
    # If still empty, try to parse text output
    if [ ! -s "$output_file" ]; then
        echo "[grader] No JSON found, parsing text output..."
        parse_text_results "$input_file" "$output_file"
    fi
    
    # If still empty, create a minimal JSON structure
    if [ ! -s "$output_file" ]; then
        echo '{"stats": {"tests": 0, "passes": 0, "failures": 0}}' > "$output_file"
    fi
}

# Function to start dev server with fallback
start_dev_server() {
    local port="$1"
    local dev_pid_var="$2"
    
    echo "[grader] Starting dev server on port $port..."
    
    # Try different dev server commands
    if npm_script_exists "dev"; then
        echo "[grader] Using npm run dev"
        PORT=$port run_with_timeout 120 npm run dev > /dev/null 2>&1 &
        eval "$dev_pid_var=$!"
    elif npm_script_exists "start"; then
        echo "[grader] Using npm run start"
        PORT=$port run_with_timeout 120 npm run start > /dev/null 2>&1 &
        eval "$dev_pid_var=$!"
    elif npm_script_exists "serve"; then
        echo "[grader] Using npm run serve"
        PORT=$port run_with_timeout 120 npm run serve > /dev/null 2>&1 &
        eval "$dev_pid_var=$!"
    else
        echo "[grader] No dev server script found, skipping server startup"
        eval "$dev_pid_var=0"
        return 1
    fi
    
    return 0
}

# Function to wait for server with timeout
wait_for_server() {
    local port="$1"
    local max_attempts="${2:-30}"
    
    echo "[grader] Waiting for dev server to become ready on port $port..."
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s "http://localhost:${port}" >/dev/null 2>&1; then
            echo "[grader] Dev server is ready!"
            return 0
        fi
        attempts=$((attempts+1))
        sleep 1
    done
    
    echo "[grader] Warning: Dev server did not respond on port ${port} after ${max_attempts}s; proceeding anyway"
    return 1
}

# Initialize paths based on environment
get_output_paths

# Prepare a writable workspace for grading
if is_coursera_env; then
    WORKSPACE_DIR="/grader/workspace"
else
    WORKSPACE_DIR="$(pwd)/grader-workspace"
fi

rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR"

if is_coursera_env; then
    echo "[grader] Copying submission into workspace: $WORKSPACE_DIR"
    if ! cp -a "${SUBMISSION_DIR}/." "$WORKSPACE_DIR/" 2>/dev/null; then
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "${SUBMISSION_DIR}/" "$WORKSPACE_DIR/" || {
                write_error_feedback "Unable to copy submission files into a working directory."
                exit 0
            }
        else
            write_error_feedback "Unable to copy submission files into a working directory."
            exit 0
        fi
    fi
    SUBMISSION_DIR="$WORKSPACE_DIR"
fi

# Extract archived submissions if detected
if [ -d "$SUBMISSION_DIR" ]; then
    ZIP_ARCHIVE=$(find "$SUBMISSION_DIR" -maxdepth 1 -type f -name '*.zip' | head -n1 || true)
    if [ -n "${ZIP_ARCHIVE:-}" ]; then
        echo "[grader] Extracting archive submission: $(basename "$ZIP_ARCHIVE")"
        EXTRACT_DIR="$WORKSPACE_DIR/extracted"
        rm -rf "$EXTRACT_DIR"
        mkdir -p "$EXTRACT_DIR"
        if unzip -q "$ZIP_ARCHIVE" -d "$EXTRACT_DIR"; then
            dir_count=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
            file_count=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
            if [ "$dir_count" -eq 1 ] && [ "$file_count" -eq 0 ]; then
                SUBMISSION_DIR=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1 || echo "$EXTRACT_DIR")
            else
                SUBMISSION_DIR="$EXTRACT_DIR"
            fi
        else
            write_error_feedback "Failed to extract the submitted archive."
            exit 0
        fi
    fi
fi

# Ensure npm has a writable cache directory
NPM_CACHE_DIR="$WORKSPACE_DIR/.npm-cache"
mkdir -p "$NPM_CACHE_DIR"
export npm_config_cache="$NPM_CACHE_DIR"
echo "[grader] npm cache directory: $npm_config_cache"
npm cache clean --force >/dev/null 2>&1 || true

# 1) Move into the submission and locate the project root
if is_coursera_env; then
    # Check if /shared exists, if not, use current directory for simulation
    if [ -d "/shared" ]; then
        cd "$SUBMISSION_DIR" || {
            write_error_feedback "Submission directory missing"
            exit 0
        }
    else
        # Coursera simulation mode - use current directory
        echo "[grader] Coursera simulation mode detected"
        cd "." || {
            write_error_feedback "Cannot access current directory"
            exit 0
        }
    fi
else
    cd "$SUBMISSION_DIR" || {
        write_error_feedback "Cannot access submission directory"
        exit 0
    }
fi

# Heuristic: prefer directory containing cypress.config.* else first package.json
PROJECT_ROOT=""
CFG_PATH=$(find . -maxdepth 6 -type f \( -name 'cypress.config.js' -o -name 'cypress.config.cjs' -o -name 'cypress.config.ts' -o -name 'cypress.config.mjs' \) | head -n1 || true)
if [ -n "${CFG_PATH:-}" ]; then
    PROJECT_ROOT=$(dirname "$CFG_PATH")
else
    PKG_PATH=$(find . -maxdepth 6 -type f -name 'package.json' | head -n1 || true)
    if [ -n "${PKG_PATH:-}" ]; then
        PROJECT_ROOT=$(dirname "$PKG_PATH")
    fi
fi

if [ -z "${PROJECT_ROOT:-}" ]; then
    write_error_feedback "Could not locate a Node project (missing package.json)."
    exit 0
fi

cd "$PROJECT_ROOT"
echo "[grader] Project root: $(pwd)"

# Ensure Node can resolve global modules (like globally installed Cypress)
GLOBAL_NODE_MODULES_DIR=$(npm root -g 2>/dev/null || echo "/usr/local/lib/node_modules")
export NODE_PATH="$(pwd)/node_modules:$GLOBAL_NODE_MODULES_DIR"
export PATH="/usr/local/bin:$PATH"
# Initialize NODE_PATH in Node's resolution paths (no-op if unsupported)
node -e 'require("module").Module._initPaths()' >/dev/null 2>&1 || true

# Ensure results directory is clean
rm -rf results
mkdir -p results

# Remove any pre-existing node_modules to avoid cached/corrupted installs
if [ -d node_modules ]; then
    echo "[grader] Removing existing node_modules directory..."
    if ! rm -rf node_modules; then
        echo "[grader] Warning: Unable to fully remove node_modules; continuing with fresh install attempt."
    fi
fi

# 2) Install dependencies with optimized npm settings
echo "[grader] Installing dependencies..."
# Non-interactive, stable npm settings to avoid TTY/progress issues
export CI=true
export NODE_ENV=test
export npm_config_progress=false
export npm_config_color=false
export npm_config_loglevel=warn

npm config set fetch-timeout 60000
npm config set fetch-retry-mintimeout 10000
npm config set fetch-retry-maxtimeout 60000

INSTALL_LOG_DIR="./results/npm-logs"
rm -rf "$INSTALL_LOG_DIR"
mkdir -p "$INSTALL_LOG_DIR"

INSTALL_SUCCESS=false
INSTALL_STATUS=0

if [ -f package-lock.json ]; then
    echo "[grader] Using npm ci (faster for locked dependencies)..."
    if run_npm_command "$INSTALL_LOG_DIR/npm-ci.log" npm ci --no-audit --no-fund --legacy-peer-deps --progress=false; then
        INSTALL_SUCCESS=true
    else
        echo "[grader] Warning: npm ci reported errors, falling back to npm install..."
    fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
    echo "[grader] Using npm install..."
    if run_npm_command "$INSTALL_LOG_DIR/npm-install.log" npm install --no-audit --no-fund --legacy-peer-deps --progress=false; then
        INSTALL_SUCCESS=true
    else
        INSTALL_STATUS=$?
    fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
    echo "[grader] ERROR: Dependency installation failed (status $INSTALL_STATUS)."
    write_error_feedback "Dependency installation failed. See results/npm-logs for npm output."
    exit 0
fi

if [ ! -d node_modules ]; then
    echo "[grader] ERROR: node_modules directory missing after install."
    write_error_feedback "Dependency installation produced no node_modules directory. See results/npm-logs for details."
    exit 0
fi

# Ensure Cypress is available locally; many configs require require('cypress')
if [ ! -d node_modules/cypress ]; then
    echo "[grader] Local Cypress dependency missing; attempting fallback installation..."
    if run_npm_command "$INSTALL_LOG_DIR/npm-cypress.log" npm install --no-audit --no-fund --legacy-peer-deps --progress=false cypress@13.17.0; then
        echo "[grader] Fallback Cypress installation succeeded."
    else
        echo "[grader] ERROR: Unable to install Cypress locally for the project."
        write_error_feedback "Autograder could not install Cypress dependency. Please ensure cypress@13 is listed in devDependencies."
        exit 0
    fi
fi

echo "[grader] Dependency installation completed (with potential warnings ignored)"

# 3) Run Component tests (with fallbacks)
export TERM=dumb
COMP_JSON=./results/component_feedback.json
COMP_RAW=./results/component_raw.txt

run_test_with_fallback "component" "test:component" "test" "$COMP_RAW"
COMPONENT_EXIT_CODE=$?
echo "[grader] Component tests exit code: $COMPONENT_EXIT_CODE"

# Debug: Show raw output content
echo "[grader] Component raw output content:"
cat "$COMP_RAW" 2>/dev/null || echo "[grader] No component raw output found"

# Extract JSON from component test output
extract_json_from_output "$COMP_RAW" "$COMP_JSON"

# 4) Start dev server for E2E tests (with fallbacks)
PORT=${PORT:-8080}
DEV_PID=0

if start_dev_server "$PORT" "DEV_PID"; then
    if [ $DEV_PID -ne 0 ]; then
        wait_for_server "$PORT" 30
    else
        echo "[grader] No dev server needed, proceeding with E2E tests"
    fi
else
    echo "[grader] No dev server available, proceeding with E2E tests"
fi

# 5) Run E2E tests (with fallbacks)
E2E_JSON=./results/e2e_feedback.json
E2E_RAW=./results/e2e_raw.txt

run_test_with_fallback "e2e" "test:e2e" "test" "$E2E_RAW"
E2E_EXIT_CODE=$?
echo "[grader] E2E tests exit code: $E2E_EXIT_CODE"

# Debug: Show raw output content
echo "[grader] E2E raw output content:"
cat "$E2E_RAW" 2>/dev/null || echo "[grader] No E2E raw output found"

# Extract JSON from E2E test output
extract_json_from_output "$E2E_RAW" "$E2E_JSON"

# 6) Stop development server if it was started
if [ $DEV_PID -ne 0 ]; then
    echo "[grader] Stopping development server (PID: $DEV_PID)..."
    kill $DEV_PID 2>/dev/null || true
    wait $DEV_PID 2>/dev/null || true
fi

# 7) Parse results (handle missing files gracefully)
if [ -f "$COMP_JSON" ]; then
    TOTAL_COMPONENT_TESTS=$(jq -r '.stats.tests // 0' "$COMP_JSON" 2>/dev/null || echo 0)
    TOTAL_COMPONENT_TESTS_PASSED=$(jq -r '.stats.passes // 0' "$COMP_JSON" 2>/dev/null || echo 0)
else
    echo "[grader] Warning: $COMP_JSON not found"
    TOTAL_COMPONENT_TESTS=0
    TOTAL_COMPONENT_TESTS_PASSED=0
fi

if [ -f "$E2E_JSON" ]; then
    TOTAL_E2E_TESTS=$(jq -r '.stats.tests // 0' "$E2E_JSON" 2>/dev/null || echo 0)
    TOTAL_E2E_TESTS_PASSED=$(jq -r '.stats.passes // 0' "$E2E_JSON" 2>/dev/null || echo 0)
else
    echo "[grader] Warning: $E2E_JSON not found"
    TOTAL_E2E_TESTS=0
    TOTAL_E2E_TESTS_PASSED=0
fi

TOTAL_TESTS=$((TOTAL_E2E_TESTS + TOTAL_COMPONENT_TESTS))
PASSED=$((TOTAL_E2E_TESTS_PASSED + TOTAL_COMPONENT_TESTS_PASSED))

if [ $TOTAL_TESTS -eq 0 ]; then
    SCORE="0"
else
    SCORE=$(echo "scale=4; $PASSED / $TOTAL_TESTS" | bc)
fi

# Add leading zero if needed
if [[ $SCORE =~ ^\. ]]; then
    SCORE="0$SCORE"
fi

# 8) Write Coursera-required outputs
mkdir -p "$(dirname "$FEEDBACK_JSON")"

# Create detailed feedback message
if [ $TOTAL_TESTS -eq 0 ]; then
    FEEDBACK_MSG="No tests found. Please check your test files."
elif [ $PASSED -eq $TOTAL_TESTS ]; then
    FEEDBACK_MSG="All tests passed! Great job!"
else
    FEEDBACK_MSG="Some tests failed. Check your implementation."
fi

echo "{\"fractionalScore\": $SCORE, \"feedback\": \"$FEEDBACK_MSG\", \"feedbackType\": \"HTML\"}" > "$FEEDBACK_JSON"

# Create detailed HTML feedback
PERCENT=$(echo "$SCORE * 100" | bc)
cat > "$HTML_FEEDBACK" << EOF
<h3>Test Results</h3>
<p><b>Score: ${PERCENT}%</b></p>
<p>Component Tests: ${TOTAL_COMPONENT_TESTS_PASSED}/${TOTAL_COMPONENT_TESTS} passed</p>
<p>E2E Tests: ${TOTAL_E2E_TESTS_PASSED}/${TOTAL_E2E_TESTS} passed</p>
<p><b>Total: ${PASSED}/${TOTAL_TESTS} tests passed</b></p>
<p>$FEEDBACK_MSG</p>
EOF

echo "[grader] Grading completed. Score: $SCORE ($PASSED/$TOTAL_TESTS)"
echo "[grader] Component tests: $TOTAL_COMPONENT_TESTS_PASSED/$TOTAL_COMPONENT_TESTS"
echo "[grader] E2E tests: $TOTAL_E2E_TESTS_PASSED/$TOTAL_E2E_TESTS"
