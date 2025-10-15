#!/bin/bash
set -Eeuo pipefail

export COURSES_GRADING=${COURSES_GRADING:-true}
export CI=${CI:-true}
export NODE_ENV=${NODE_ENV:-test}
if [ -z "${MONGOMS_SYSTEM_BINARY:-}" ] && [ -x "/usr/bin/mongod" ]; then
  export MONGOMS_SYSTEM_BINARY="/usr/bin/mongod"
fi
if [ -z "${MONGOMS_VERSION:-}" ]; then
  export MONGOMS_VERSION="7.0.14"
fi
export MONGODB_PORT=${MONGODB_PORT:-27017}
export HOST=${HOST:-0.0.0.0}

PACKAGE_MANAGER="npm"
DEV_PID=""
MONGODB_PID=""
RESULTS_DIR=""
BASE_URL=""
RUN_JEST=false
RUN_VITEST=false

log() {
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  echo "[$ts] $*"
}

warn() {
  log "WARN: $*"
}

error() {
  >&2 log "ERROR: $*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

safe_kill() {
  local pid="$1"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

find_project_root() {
  local base="$1"
  local override="${LAB_SUBDIR:-${TARGET_LAB:-${LAB_DIR:-${LAB_NAME:-}}}}"

  if [ -n "$override" ]; then
    local candidate="$base/$override"
    if [ -d "$candidate" ] && [ -f "$candidate/package.json" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  fi

  node - "$base" <<'NODE'
const fs = require('fs');
const path = require('path');

const base = path.resolve(process.argv[2] || '.');
const maxDepth = 5;

const skipDirs = new Set([
  'node_modules',
  '.git',
  '.hg',
  '.svn',
  '.cache',
  '.cypress',
  '.next',
  '.nuxt',
  '.pnpm',
  '.turbo',
  '__pycache__',
  'dist',
  'build',
  'coverage',
  'tmp',
  'logs',
  'assignment-autograder'
]);

function isDefaultTestScript(value) {
  if (!value || typeof value !== 'string') return true;
  const trimmed = value.trim();
  return trimmed === '' || trimmed === 'echo "Error: no test specified" && exit 1';
}

const candidates = [];

function walk(current, depth) {
  if (depth > maxDepth) return;
  let stats;
  try {
    stats = fs.statSync(current);
  } catch {
    return;
  }
  if (!stats.isDirectory()) return;

  let entries = [];
  try {
    entries = fs.readdirSync(current, { withFileTypes: true });
  } catch {
    return;
  }

  const pkgPath = path.join(current, 'package.json');
  if (fs.existsSync(pkgPath)) {
    let pkg = {};
    try {
      pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    } catch {
      pkg = {};
    }
    const scripts = pkg.scripts && typeof pkg.scripts === 'object' ? pkg.scripts : {};
    const scriptValues = Object.values(scripts).filter((v) => typeof v === 'string');

    const rel = path.relative(base, current);
    const relLower = rel.toLowerCase();
    const depthScore = Math.max(0, 10 - depth * 2);
    const containsLab = relLower.includes('lab');
    const hasSrc = fs.existsSync(path.join(current, 'src'));
    const hasCypressDir = fs.existsSync(path.join(current, 'cypress'));
    const hasCypressConfig = ['cypress.config.js','cypress.config.cjs','cypress.config.mjs','cypress.config.ts'].some((file) => fs.existsSync(path.join(current, file)));
    const hasTestScript = scripts.test && !isDefaultTestScript(scripts.test);
    const hasDevScript = Boolean(scripts.dev || scripts.start || scripts.serve || scripts.preview);
    const scriptContains = (needle) => scriptValues.some((value) => value.includes(needle));
    const hasJest = Boolean(
      (pkg.devDependencies && pkg.devDependencies.jest) ||
      (pkg.dependencies && pkg.dependencies.jest) ||
      scriptContains('jest')
    );
    const hasVitest = Boolean(
      (pkg.devDependencies && pkg.devDependencies.vitest) ||
      (pkg.dependencies && pkg.dependencies.vitest) ||
      scriptContains('vitest')
    );
    const hasCypressDep = Boolean(
      (pkg.devDependencies && pkg.devDependencies.cypress) ||
      (pkg.dependencies && pkg.dependencies.cypress) ||
      scriptContains('cypress')
    );

    let score = depthScore;
    if (containsLab) score += 5;
    if (hasSrc) score += 2;
    if (hasCypressDir) score += 6;
    if (hasCypressConfig) score += 4;
    if (hasCypressDep) score += 3;
    if (hasTestScript) score += 4;
    if (hasDevScript) score += 2;
    if (hasJest) score += 2;
    if (hasVitest) score += 2;
    if (rel === '') score += 1;
    if (relLower.includes('autograder')) score -= 8;

    candidates.push({
      path: current,
      depth,
      score
    });
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (skipDirs.has(entry.name)) continue;
    const nextPath = path.join(current, entry.name);
    if (nextPath.includes(`${path.sep}assignment${path.sep}autograder`)) continue;
    walk(nextPath, depth + 1);
  }
}

walk(base, 0);

if (candidates.length === 0) {
  console.log(base);
  process.exit(0);
}

candidates.sort((a, b) => {
  if (b.score !== a.score) return b.score - a.score;
  if (a.depth !== b.depth) return a.depth - b.depth;
  return a.path.length - b.path.length;
});

console.log(path.resolve(candidates[0].path));
NODE
}

has_npm_script() {
  local script="$1"
  node - "$script" <<'NODE'
const fs = require('fs');
const script = process.argv[2];
if (!fs.existsSync('package.json')) process.exit(1);
try {
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  const scripts = pkg.scripts || {};
  if (Object.prototype.hasOwnProperty.call(scripts, script)) process.exit(0);
} catch {}
process.exit(1);
NODE
}

read_npm_script() {
  local script="$1"
  node - "$script" <<'NODE'
const fs = require('fs');
const script = process.argv[2];
if (!fs.existsSync('package.json')) process.exit(0);
try {
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  const scripts = pkg.scripts || {};
  if (scripts && scripts[script]) process.stdout.write(String(scripts[script]));
} catch {}
NODE
}

detect_package_manager() {
  if [ -f pnpm-lock.yaml ]; then
    PACKAGE_MANAGER="pnpm"
  elif [ -f yarn.lock ]; then
    PACKAGE_MANAGER="yarn"
  elif [ -f bun.lockb ]; then
    PACKAGE_MANAGER="bun"
  else
    PACKAGE_MANAGER="npm"
  fi
}

install_dependencies() {
  if [ ! -f package.json ]; then
    warn "No package.json found; skipping dependency installation."
    return
  fi

  detect_package_manager
  case "$PACKAGE_MANAGER" in
    pnpm)
      log "Using pnpm for dependency installation."
      if command_exists pnpm; then
        pnpm install --frozen-lockfile --reporter=append-only || pnpm install --reporter=append-only
      else
        error "pnpm is not available but pnpm-lock.yaml exists."
      fi
      ;;
    yarn)
      log "Using yarn for dependency installation."
      if command_exists yarn; then
        yarn install --frozen-lockfile --silent || yarn install --silent
      else
        error "yarn is not available but yarn.lock exists."
      fi
      ;;
    bun)
      log "Using bun for dependency installation."
      if command_exists bun; then
        bun install || bun install --no-save
      else
        error "bun is not available but bun.lockb exists."
      fi
      ;;
    npm|*)
      if [ -f package-lock.json ]; then
        log "Running npm ci..."
        if ! npm ci --no-audit --no-fund; then
          warn "npm ci failed; retrying with legacy-peer-deps."
          if ! npm ci --no-audit --no-fund --legacy-peer-deps; then
            warn "npm ci with legacy-peer-deps failed; falling back to npm install."
            if ! npm install --no-audit --no-fund; then
              warn "npm install failed; retrying with legacy-peer-deps."
              npm install --no-audit --no-fund --legacy-peer-deps
            fi
          fi
        fi
      else
        log "Running npm install..."
        if ! npm install --no-audit --no-fund; then
          warn "npm install failed; retrying with legacy-peer-deps."
          npm install --no-audit --no-fund --legacy-peer-deps
        fi
      fi
      ;;
  esac
}

run_package_script() {
  local script="$1"
  shift || true
  local -a cmd
  case "$PACKAGE_MANAGER" in
    npm)
      cmd=(npm run "$script")
      if [ "$#" -gt 0 ]; then
        cmd+=("--")
        cmd+=("$@")
      fi
      ;;
    pnpm)
      cmd=(pnpm run "$script")
      if [ "$#" -gt 0 ]; then
        cmd+=("--")
        cmd+=("$@")
      fi
      ;;
    yarn)
      cmd=(yarn run "$script")
      if [ "$#" -gt 0 ]; then
        cmd+=("$@")
      fi
      ;;
    bun)
      cmd=(bun run "$script")
      if [ "$#" -gt 0 ]; then
        cmd+=("$@")
      fi
      ;;
    *)
      cmd=(npm run "$script")
      if [ "$#" -gt 0 ]; then
        cmd+=("--")
        cmd+=("$@")
      fi
      ;;
  esac
  "${cmd[@]}"
}

join_by_comma() {
  local -n array_ref=$1
  local joined=""
  if [ "${#array_ref[@]}" -gt 0 ]; then
    printf -v joined '%s,' "${array_ref[@]}"
    joined=${joined%,}
  fi
  echo "$joined"
}

collect_specs() {
  local -n target=$1
  shift
  local -a buffer=()
  local dir
  for dir in "$@"; do
    if [ -d "$dir" ]; then
      while IFS= read -r file; do
        buffer+=("$file")
      done < <(find "$dir" -type f \( -name '*.cy.js' -o -name '*.cy.jsx' -o -name '*.cy.ts' -o -name '*.cy.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o -name '*.spec.ts' -o -name '*.spec.tsx' \) -not -path '*/node_modules/*' | sort -u)
    fi
  done
  if [ "${#buffer[@]}" -gt 0 ]; then
    mapfile -t target < <(printf '%s\n' "${buffer[@]}" | sort -u)
  else
    target=()
  fi
}

detect_base_url() {
  local config_file
  local url=""
  for config_file in cypress.config.ts cypress.config.mjs cypress.config.cjs cypress.config.js; do
    if [ -f "$config_file" ]; then
      url=$(grep -oE 'baseUrl\s*[:=]\s*["'"'"']https?://[^"'"'"']+' "$config_file" | head -n 1 | sed -E 's/.*["'"'"'](https?:\/\/[^"'"'"']+).*/\1/')
      if [ -n "$url" ]; then
        echo "$url"
        return 0
      fi
      url=$(grep -oE 'https?://[A-Za-z0-9\.\-]+:[0-9]+' "$config_file" | head -n 1 || true)
      if [ -n "$url" ]; then
        echo "$url"
        return 0
      fi
      url=$(grep -oE 'https?://[A-Za-z0-9\.\-]+' "$config_file" | head -n 1 || true)
      if [ -n "$url" ]; then
        echo "$url"
        return 0
      fi
    fi
  done
  echo "http://127.0.0.1:9090"
}

start_mongodb() {
  if ! command_exists mongod; then
    warn "mongod binary not available; skipping MongoDB bootstrap."
    return 1
  fi

  local dbpath="/tmp/mongo-data-$$"
  mkdir -p "$dbpath"
  local log_file="/tmp/mongod-$$.log"
  local pid_file="/tmp/mongod-$$.pid"

  if nc -z 127.0.0.1 "${MONGODB_PORT:-27017}" >/dev/null 2>&1; then
    log "MongoDB already accepting connections on port ${MONGODB_PORT:-27017}."
    return 0
  fi

  log "Starting MongoDB on port ${MONGODB_PORT:-27017}..."
  set +e
  mongod --dbpath "$dbpath" \
    --bind_ip 127.0.0.1 \
    --port "${MONGODB_PORT:-27017}" \
    --fork \
    --logpath "$log_file" \
    --pidfilepath "$pid_file" >/dev/null 2>&1
  local status=$?
  set -e

  if [ $status -ne 0 ]; then
    warn "MongoDB failed to start (exit $status); see ${log_file}."
    return $status
  fi

  if [ -f "$pid_file" ]; then
    MONGODB_PID=$(cat "$pid_file")
    export MONGODB_PID
  fi

  log "MongoDB started with pid ${MONGODB_PID:-unknown}."
  return 0
}

stop_mongodb() {
  local pid_file="/tmp/mongod-$$.pid"

  if [ -n "${MONGODB_PID:-}" ] && kill -0 "$MONGODB_PID" 2>/dev/null; then
    log "Stopping MongoDB (pid $MONGODB_PID)..."
    safe_kill "$MONGODB_PID"
    MONGODB_PID=""
  elif [ -n "$pid_file" ] && [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping MongoDB (pid $pid)..."
      safe_kill "$pid"
    fi
  fi
}

start_dev_server() {
  local port="$1"
  local base_url="$2"
  local script=""

  if has_npm_script "dev"; then
    script="dev"
  elif has_npm_script "start"; then
    script="start"
  elif has_npm_script "serve"; then
    script="serve"
  elif has_npm_script "preview"; then
    script="preview"
  else
    warn "No package script found to start a development server; skipping server launch."
    return 1
  fi

  local script_body
  script_body=$(read_npm_script "$script")
  local -a extra_args=()

  if [[ "$script_body" == *"vite"* ]]; then
    extra_args+=("--host" "0.0.0.0")
    if [ -n "$port" ]; then
      extra_args+=("--port" "$port")
    fi
  elif [[ "$script_body" == *"next"* ]]; then
    if [ -n "$port" ]; then
      extra_args+=("-p" "$port")
    fi
  elif [[ "$script_body" == *"webpack-dev-server"* ]]; then
    if [ -n "$port" ]; then
      extra_args+=("--port" "$port")
    fi
  elif [[ "$script_body" == *"nodemon"* ]] && [[ "$script_body" != *"--port"* ]]; then
    if [ -n "$port" ]; then
      extra_args+=("--")
      extra_args+=("--port" "$port")
    fi
  fi

  local server_log="/tmp/dev-server-$$.log"
  log "Starting development server (${PACKAGE_MANAGER} run $script) -> $server_log"

  local -a cmd
  case "$PACKAGE_MANAGER" in
    npm)
      cmd=(npm run "$script")
      if [ "${#extra_args[@]}" -gt 0 ]; then
        cmd+=("--")
        cmd+=("${extra_args[@]}")
      fi
      ;;
    pnpm)
      cmd=(pnpm run "$script")
      if [ "${#extra_args[@]}" -gt 0 ]; then
        cmd+=("--")
        cmd+=("${extra_args[@]}")
      fi
      ;;
    yarn)
      cmd=(yarn run "$script")
      if [ "${#extra_args[@]}" -gt 0 ]; then
        cmd+=("${extra_args[@]}")
      fi
      ;;
    bun)
      cmd=(bun run "$script")
      if [ "${#extra_args[@]}" -gt 0 ]; then
        cmd+=("${extra_args[@]}")
      fi
      ;;
    *)
      cmd=(npm run "$script")
      if [ "${#extra_args[@]}" -gt 0 ]; then
        cmd+=("--")
        cmd+=("${extra_args[@]}")
      fi
      ;;
  esac

  (
    export COURSES_GRADING=true
    export AUTH_SECRET="${AUTH_SECRET:-secret}"
    export PORT="$port"
    export HOST="${HOST:-0.0.0.0}"
    export BASE_URL="$base_url"
    export MONGODB_URI="${MONGODB_URI:-mongodb://127.0.0.1:${MONGODB_PORT:-27017}/lab}"
    "${cmd[@]}"
  ) >"$server_log" 2>&1 &
  DEV_PID=$!
  export DEV_PID
  sleep 2
  return 0
}

wait_for_server() {
  local base_url="$1"
  local timeout="${2:-180}"
  local port="${3:-}"
  local clean_base="${base_url%/}"
  local -a endpoints=(
    "$clean_base"
    "$clean_base/health"
    "$clean_base/api/health"
    "$clean_base/status"
    "$clean_base/api/status"
  )

  log "Waiting for server readiness (timeout ${timeout}s)..."
  for ((i = 0; i < timeout; i++)); do
    if [ -n "$port" ]; then
      if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
        sleep 1
        continue
      fi
    fi
    for endpoint in "${endpoints[@]}"; do
      local status
      status=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$endpoint" || true)
      if [[ "$status" =~ ^(2|3)[0-9][0-9]$ ]]; then
        log "Server is responding at ${endpoint} (HTTP $status)."
        return 0
      fi
    done
    sleep 1
  done
  warn "Server did not become ready within ${timeout}s; continuing anyway."
  return 1
}

stop_dev_server() {
  if [ -n "${DEV_PID:-}" ]; then
    log "Stopping development server (pid $DEV_PID)..."
    safe_kill "$DEV_PID"
    DEV_PID=""
  fi
}

run_cypress_suite() {
  local suite_type="$1"
  local specs_arg="$2"
  local report_file="$3"
  local log_file="$4"
  local extra_flag="$5"

  local -a cmd
  if [ -x "./node_modules/.bin/cypress" ]; then
    cmd=(./node_modules/.bin/cypress)
  elif command_exists cypress; then
    cmd=(cypress)
  else
    cmd=(npx --yes cypress)
  fi

  cmd+=("run")
  if [ -n "$extra_flag" ]; then
    cmd+=("$extra_flag")
  fi
  if [ -n "$specs_arg" ]; then
    cmd+=("--spec" "$specs_arg")
  fi
  cmd+=("--browser" "electron" "--reporter" "json" "--reporter-options" "output=${report_file}")
  cmd+=("--env" "COURSES_GRADING=true")
  if [ -n "$BASE_URL" ]; then
    cmd+=("--config" "baseUrl=${BASE_URL}")
  fi

  log "Running Cypress ${suite_type} tests..."
  set +e
  COURSES_GRADING=true CYPRESS_BASE_URL="$BASE_URL" "${cmd[@]}" 2>&1 | tee "$log_file"
  local exit_code=${PIPESTATUS[0]}
  set -e
  log "Cypress ${suite_type} exit code: $exit_code"
  return "$exit_code"
}

handle_component_suite_failure() {
  local log_file="$1"
  local report_file="$2"

  if [ ! -f "$log_file" ]; then
    return 1
  fi

  local reason=""
  if grep -qi "Failed to load plugin 'cypress'" "$log_file"; then
    reason="missing eslint-plugin-cypress dependency"
  elif grep -qi "The JSX syntax extension is not currently enabled" "$log_file"; then
    reason="JSX loader not configured for component specs"
  elif grep -qi "Failed to fetch dynamically imported module: .*__cypress/src/cypress/support/component.js" "$log_file"; then
    reason="component support bundle failed to load"
  fi

  if [ -z "$reason" ]; then
    return 1
  fi

  warn "Component suite marked as skipped due to ${reason}."
  cat <<JSON >"$report_file"
{
  "results": {
    "summary": {
      "tests": 0,
      "passed": 0,
      "failed": 0,
      "skipped": 0,
      "pending": 0
    }
  },
  "tests": [],
  "warnings": [
    "Component testing skipped: ${reason}"
  ]
}
JSON
  return 0
}

detect_test_runners() {
  RUN_JEST=false
  RUN_VITEST=false

  if [ ! -f package.json ]; then
    return
  fi

  local detection
  detection=$(node - <<'NODE'
const fs = require('fs');
let pkg = {};
try {
  pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
} catch {
  pkg = {};
}
const scripts = pkg.scripts || {};
const scriptValues = Object.values(scripts).filter((v) => typeof v === 'string');
const scriptContains = (needle) => scriptValues.some((value) => value.includes(needle));
const has = (name) => Boolean(
  (pkg.dependencies && pkg.dependencies[name]) ||
  (pkg.devDependencies && pkg.devDependencies[name])
);
if (has('jest') || has('@jest/core') || has('@testing-library/jest-dom') || scriptContains('jest')) {
  console.log('jest');
}
if (has('vitest') || scriptContains('vitest')) {
  console.log('vitest');
}
NODE
)

  while IFS= read -r line; do
    case "$line" in
      jest) RUN_JEST=true ;;
      vitest) RUN_VITEST=true ;;
    esac
  done <<<"$detection"

  if [ "$RUN_JEST" = true ]; then
    if ! find . -type f \( -name '*.test.js' -o -name '*.test.jsx' -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o -name '*.spec.ts' -o -name '*.spec.tsx' \) -not -path '*/node_modules/*' | head -n 1 >/dev/null; then
      warn "Jest detected but no matching test files found; skipping Jest run."
      RUN_JEST=false
    fi
  fi

  if [ "$RUN_VITEST" = true ]; then
    if ! find . -type f \( -name '*.test.js' -o -name '*.test.jsx' -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o -name '*.spec.ts' -o -name '*.spec.tsx' \) -not -path '*/node_modules/*' | head -n 1 >/dev/null; then
      warn "Vitest detected but no matching test files found; skipping Vitest run."
      RUN_VITEST=false
    fi
  fi
}

run_jest_suite() {
  local report_file="/tmp/autograder-jest-$$.json"
  local log_file="/tmp/autograder-jest-$$.log"
  local -a cmd

  if [ -x "./node_modules/.bin/jest" ]; then
    cmd=(./node_modules/.bin/jest)
  else
    cmd=(npx --yes jest)
  fi

  cmd+=("--runInBand" "--json" "--outputFile" "$report_file" "--testLocationInResults")

  log "Running Jest tests..."
  set +e
  COURSES_GRADING=true CI=true "${cmd[@]}" 2>&1 | tee "$log_file"
  local exit_code=${PIPESTATUS[0]}
  set -e
  log "Jest exit code: $exit_code"

  if [ ! -s "$report_file" ]; then
    warn "Jest JSON report missing; writing empty placeholder."
    echo '{}' >"$report_file"
  fi

  return "$exit_code"
}

run_vitest_suite() {
  local report_file="/tmp/autograder-vitest-$$.json"
  local log_file="/tmp/autograder-vitest-$$.log"
  local -a cmd

  if [ -x "./node_modules/.bin/vitest" ]; then
    cmd=(./node_modules/.bin/vitest)
  else
    cmd=(npx --yes vitest)
  fi

  cmd+=("run" "--reporter=json" "--outputFile" "$report_file")

  log "Running Vitest tests..."
  set +e
  COURSES_GRADING=true CI=true "${cmd[@]}" 2>&1 | tee "$log_file"
  local exit_code=${PIPESTATUS[0]}
  set -e
  log "Vitest exit code: $exit_code"

  if [ ! -s "$report_file" ]; then
    warn "Vitest JSON report missing; writing empty placeholder."
    echo '{}' >"$report_file"
  fi

  return "$exit_code"
}

prepare_results_dir() {
  RESULTS_DIR="${RESULTS_DIR:-/autograder/results}"
  if [ -d "$RESULTS_DIR" ]; then
    rm -rf "${RESULTS_DIR:?}"/* 2>/dev/null || true
  else
    mkdir -p "$RESULTS_DIR"
  fi
}

aggregate_and_score() {
  # Copy test results from /tmp to RESULTS_DIR for aggregation
  cp /tmp/autograder-*-$$.json "$RESULTS_DIR/" 2>/dev/null || true
  cp /tmp/autograder-*-$$.log "$RESULTS_DIR/" 2>/dev/null || true
  
  local aggregate_output
  aggregate_output=$(node /grader/aggregate-results.js "$RESULTS_DIR" 2>/dev/null || echo "")
  if [ -z "$aggregate_output" ]; then
    aggregate_output="{}"
  fi

  local total_tests total_passed total_skipped
  total_tests=$(echo "$aggregate_output" | jq -r '.tests // 0' 2>/dev/null || echo 0)
  total_passed=$(echo "$aggregate_output" | jq -r '.passed // 0' 2>/dev/null || echo 0)
  total_skipped=$(echo "$aggregate_output" | jq -r '.skipped // 0' 2>/dev/null || echo 0)
  local failure_list warnings
  failure_list=$(echo "$aggregate_output" | jq -r '.html.failuresList // ""' 2>/dev/null || echo "")
  warnings=$(echo "$aggregate_output" | jq -r '.warnings | @json' 2>/dev/null || echo "[]")

  if [ "$total_tests" = "null" ] || [ -z "$total_tests" ]; then total_tests=0; fi
  if [ "$total_passed" = "null" ] || [ -z "$total_passed" ]; then total_passed=0; fi
  if [ "$total_skipped" = "null" ] || [ -z "$total_skipped" ]; then total_skipped=0; fi

  local score
  if [ "$total_tests" -eq 0 ]; then
    score="0.0000"
  else
    score=$(awk "BEGIN { printf \"%.4f\", $total_passed / $total_tests }")
  fi
  local percentage
  percentage=$(awk "BEGIN { printf \"%.4f\", $score * 100 }")

  log "Final totals -> tests: $total_tests, passed: $total_passed, skipped: $total_skipped, score: $score"

  local feedback_root="${FEEDBACK_ROOT:-/shared}"
  if [ ! -d "$feedback_root" ]; then
    feedback_root="$RESULTS_DIR"
  fi
  mkdir -p "$feedback_root"
  if [ "$feedback_root" != "/shared" ] && [ -z "${FEEDBACK_ROOT:-}" ]; then
    warn "Feedback directory /shared unavailable; using $feedback_root for feedback artifacts."
  fi

  local feedback_json_path="${feedback_root}/feedback.json"
  local html_feedback_path="${feedback_root}/htmlFeedback.html"

  cat <<JSON >"$feedback_json_path"
{"fractionalScore": $score, "feedback": "Automated grading complete.", "feedbackType": "HTML"}
JSON

  {
    echo "<b>Your score: ${percentage}%</b><br/>"
    echo "Total tests: ${total_tests}<br/>"
    echo "Passed: ${total_passed}<br/>"
    if [ "$total_skipped" -gt 0 ]; then
      echo "Skipped: ${total_skipped}<br/>"
    fi
    if [ "$failure_list" != "null" ] && [ -n "$failure_list" ]; then
      echo "Failures:${failure_list}"
    else
      echo "Failures: None"
    fi
    if [ "$warnings" != "[]" ]; then
      echo "<br/>Warnings: ${warnings}"
    fi
  } >"$html_feedback_path"
  
  # Clean up intermediate test result files, keeping only feedback files
  rm -f "${RESULTS_DIR}"/autograder-*.json 2>/dev/null || true
  rm -f "${RESULTS_DIR}"/autograder-*.log 2>/dev/null || true
  
  # Clean up temporary files
  rm -f /tmp/autograder-*-$$ 2>/dev/null || true
  rm -f /tmp/dev-server-$$.log 2>/dev/null || true
  rm -f /tmp/mongod-$$.* 2>/dev/null || true
  rm -rf /tmp/mongo-data-$$ 2>/dev/null || true
}

cleanup() {
  stop_dev_server
  stop_mongodb
}

trap cleanup EXIT

main() {
  local submission_root="${SUBMISSION_ROOT:-}"
  if [ -n "$submission_root" ] && [ -d "$submission_root" ]; then
    submission_root=$(cd "$submission_root" && pwd)
  else
    local -a possible_roots=(
      "/shared/submission"
      "/submission"
      "/shared"
      "/grader/submission"
      "/workspace"
      "/project"
      "$(pwd)"
    )
    for candidate in "${possible_roots[@]}"; do
      if [ -d "$candidate" ]; then
        submission_root="$candidate"
        break
      fi
    done
    if [ -z "$submission_root" ]; then
      submission_root="/shared"
    fi
    submission_root=$(cd "$submission_root" && pwd)
  fi
  log "Submission root: $submission_root"

  local project_root
  project_root=$(find_project_root "$submission_root" 2>/dev/null || echo "$submission_root")
  if [ ! -d "$project_root" ]; then
    error "Project root not found; falling back to submission root."
    project_root="$submission_root"
  fi
  log "Using project directory: $project_root"
  cd "$project_root"

  prepare_results_dir
  start_mongodb || warn "MongoDB bootstrap skipped or failed; proceeding without dedicated instance."

  if [ -f package.json ]; then
    install_dependencies
    detect_package_manager
    detect_test_runners
  else
    warn "No package.json located; dependency installation and test runner detection skipped."
  fi

  declare -a E2E_SPECS=()
  declare -a COMPONENT_SPECS=()
  collect_specs E2E_SPECS "cypress/e2e" "cypress/integration" "cypress/tests/e2e"
  collect_specs COMPONENT_SPECS "cypress/component" "cypress/components"

  local e2e_spec_arg=""
  local component_spec_arg=""
  if [ "${#E2E_SPECS[@]}" -gt 0 ]; then
    e2e_spec_arg=$(join_by_comma E2E_SPECS)
  fi
  if [ "${#COMPONENT_SPECS[@]}" -gt 0 ]; then
    component_spec_arg=$(join_by_comma COMPONENT_SPECS)
  fi

  BASE_URL=$(detect_base_url)
  local port_from_url
  port_from_url=$(echo "$BASE_URL" | sed -n 's/.*:\([0-9][0-9]*\)\/*$/\1/p')
  if [ -z "$port_from_url" ]; then
    port_from_url="9090"
  fi
  if [[ "$BASE_URL" != http*://* ]]; then
    BASE_URL="http://127.0.0.1:${port_from_url}"
  fi
  BASE_URL="${BASE_URL%/}"
  log "Detected base URL: $BASE_URL"

  if [ "$RUN_JEST" = true ]; then
    run_jest_suite || true
  fi

  if [ "$RUN_VITEST" = true ]; then
    run_vitest_suite || true
  fi

  if [ -n "$component_spec_arg" ]; then
    local component_report="/tmp/autograder-component-$$.json"
    local component_log="/tmp/autograder-component-$$.log"
    local component_exit=0
    run_cypress_suite "component" "$component_spec_arg" "$component_report" "$component_log" "--component" || component_exit=$?
    if [ "$component_exit" -ne 0 ]; then
      if handle_component_suite_failure "$component_log" "$component_report"; then
        log "Component suite skipped after detecting incompatible tooling."
      else
        warn "Component suite exited with code ${component_exit}; retaining Cypress results."
      fi
    fi
  else
    log "No component Cypress specs detected; skipping component suite."
  fi

  local server_started=false
  if [ -n "$e2e_spec_arg" ]; then
    if start_dev_server "$port_from_url" "$BASE_URL"; then
      server_started=true
      wait_for_server "$BASE_URL" 180 "$port_from_url" || true
    else
      warn "Development server failed to launch; e2e tests will proceed without health confirmation."
    fi
    local e2e_report="/tmp/autograder-e2e-$$.json"
    local e2e_log="/tmp/autograder-e2e-$$.log"
    run_cypress_suite "e2e" "$e2e_spec_arg" "$e2e_report" "$e2e_log" "--e2e" || true
  else
    log "No e2e Cypress specs detected; skipping e2e suite."
  fi

  if [ "$server_started" = true ]; then
    stop_dev_server
  fi

  aggregate_and_score
  log "Grading completed."
}

main "$@"
