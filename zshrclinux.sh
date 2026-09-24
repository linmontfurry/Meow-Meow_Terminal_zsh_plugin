# Everything below runs inside an anonymous function, which zsh calls at once.
#
# Pasted into .zshrc, or sourced from it, this file would otherwise run at the
# top level, where "emulate -LR zsh" is not local at all: it reset every option
# set before it (prompt_subst, the history options, auto_cd, ...) to zsh
# defaults for the rest of the session, and leaked pipefail with it. Inside a
# function both stay local and are put back on return.
#
# The working variables are local for the same reason. As globals they would
# overwrite, and the cleanup at the end would then delete, anything of yours
# with the same name: an exported $ARCH, your own $RED, a $line.
() {
emulate -LR zsh
setopt pipefail

local REPLY ARCH HOST_NAME MODEL_NAME CHIP CPU_CORES CPU_CORE_TEXT CPU_USAGE
local IP_ADDR UP_TIME BATTERY BAT_VAL BAT_COLOR BAT_TEXT VM_USED VM_TOTAL
local RAM_PERCENT SWAP_USED SWAP_TOTAL SWAP_PERCENT DISK_USED DISK_TOTAL
local DISK_PERCENT WELCOME USER_NAME CONNECTION_TYPE LOGIN_IP TTY_INFO GPU_INDEX
local CAT_1 CAT_2 CAT_1_TAIL CAT_2_TAIL CAT_1_TEXT CAT_2_TEXT line util RESET
local PINK CYAN YELLOW MAGENTA GREEN ORANGE BLUE DIM LIGHT_GREEN RED MEOW_NOW
local MEOW_CACHE_DIR MEOW_CACHE_FILE MEOW_CACHE_DIRTY MEOW_I MEOW_GAP
local MEOW_FACE_GAP MEOW_ART_PAD MEOW_RAM_USED MEOW_RAM_TOTAL MEOW_RAM_PERCENT
local MEOW_SWAP_USED MEOW_SWAP_TOTAL MEOW_SWAP_PERCENT MEOW_DISK_USED
local MEOW_DISK_TOTAL MEOW_DISK_PERCENT
local -a WELCOMES CAT_ART_1 CAT_ART_2 MEOW_GPU_UTILS
local -A MEOW_CACHE

zmodload zsh/datetime 2>/dev/null

RESET="\033[0m"
PINK="\033[1;35m"
CYAN="\033[38;5;51m"
YELLOW="\033[38;5;226m"
MAGENTA="\033[38;5;201m"
GREEN="\033[38;5;46m"
ORANGE="\033[38;5;208m"
BLUE="\033[1;34m"
DIM="\033[2m"
LIGHT_GREEN="\033[38;5;120m"
RED="\033[1;31m"

meow_echo() {
  printf '%b\n' "$1"
}

# ---------------------------------------------------------------------------
# Cache
#
# Hardware facts never change between shells, and a few probes are far too slow
# to repeat on every prompt. Both live in ONE fixed file that is rewritten in
# place, so ten thousand terminals leave exactly one file behind, never ten
# thousand. Each record carries its own timestamp, so different entries can
# expire on different schedules.
# ---------------------------------------------------------------------------

local MEOW_STATIC_TTL=${MEOW_STATIC_TTL:-604800}   # 7 days  - model, CPU name, ...
local MEOW_SAMPLE_TTL=${MEOW_SAMPLE_TTL:-10}       # 10 s    - costly live samples
MEOW_NOW=${EPOCHSECONDS:-0}
[[ "$MEOW_NOW" == <-> ]] || MEOW_NOW="$(date +%s 2>/dev/null)"
[[ "$MEOW_NOW" == <-> ]] || MEOW_NOW=0

MEOW_CACHE=()
MEOW_CACHE_DIRTY=0

if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  MEOW_CACHE_DIR="${XDG_CACHE_HOME}/meow-terminal"
elif [[ -n "${HOME:-}" ]]; then
  MEOW_CACHE_DIR="${HOME}/.cache/meow-terminal"
else
  MEOW_CACHE_DIR="${TMPDIR:-/tmp}/meow-terminal-${UID:-0}"
fi
MEOW_CACHE_FILE="${MEOW_CACHE_DIR}/facts"

meow_cache_load() {
  local line stamp key
  [[ -r "$MEOW_CACHE_FILE" ]] || return 0
  # $(<file) is read by the shell itself and does not fork.
  for line in ${(f)"$(<$MEOW_CACHE_FILE)"}; do
    stamp="${line%% *}"; line="${line#* }"
    key="${line%% *}"
    [[ "$stamp" == <-> && -n "$key" && "$key" != "$line" ]] || continue
    MEOW_CACHE[$key]="${stamp} ${line#* }"
  done
}

# meow_cache_get <key> <max-age>  ->  REPLY, non-zero on miss.
# A negative max age never expires. Zero always misses, so setting
# MEOW_STATIC_TTL=0 or MEOW_SAMPLE_TTL=0 forces a fresh probe every shell.
meow_cache_get() {
  local entry="${MEOW_CACHE[$1]-}" stamp
  [[ -n "$entry" ]] || return 1
  stamp="${entry%% *}"
  [[ "$stamp" == <-> ]] || return 1
  (( $2 == 0 )) && return 1
  (( $2 > 0 && MEOW_NOW - stamp > $2 )) && return 1
  REPLY="${entry#* }"
  return 0
}

meow_cache_set() {
  MEOW_CACHE[$1]="${MEOW_NOW} $2"
  MEOW_CACHE_DIRTY=1
}

meow_cache_save() {
  (( MEOW_CACHE_DIRTY )) || return 0
  [[ -d "$MEOW_CACHE_DIR" ]] || mkdir -p "$MEOW_CACHE_DIR" 2>/dev/null || return 0
  local key out=""
  for key in ${(k)MEOW_CACHE}; do
    out+="${MEOW_CACHE[$key]%% *} ${key} ${MEOW_CACHE[$key]#* }"$'\n'
  done
  print -rn -- "$out" >| "$MEOW_CACHE_FILE" 2>/dev/null
}

# meow_cached <key> <ttl> <fn...>   fn must leave its answer in REPLY.
meow_cached() {
  local key="$1" ttl="$2"
  shift 2
  meow_cache_get "$key" "$ttl" && return 0
  REPLY=""
  "$@"
  # An empty answer means the probe failed. Leave it out of the cache so the
  # caller falls back for this one run and we try again next shell, instead of
  # pinning "Unknown CPU" in place for a week.
  [[ -n "$REPLY" ]] && meow_cache_set "$key" "$REPLY"
  return 0
}

# ---------------------------------------------------------------------------
# Formatting helpers
#
# Every one of these answers through REPLY instead of printing. A $(...) call
# costs a forked subshell (~0.5 ms each, and this banner made about twenty-five
# of them); writing to REPLY costs ~0.01 ms.
# ---------------------------------------------------------------------------

meow_color() {
  local -i percent=${1:-0}
  if   (( percent >= 80 )); then REPLY="$RED"
  elif (( percent >= 60 )); then REPLY="$ORANGE"
  elif (( percent >= 30 )); then REPLY="$YELLOW"
  else                           REPLY="$GREEN"
  fi
}

# repeat is a shell builtin, so this forks nothing. It also avoids slicing a
# multibyte string, which silently falls back to bytes outside a UTF-8 locale.
meow_bar() {
  local -i percent=${1:-0} fill
  (( percent > 100 )) && percent=100
  (( percent < 0 )) && percent=0
  fill=$(( percent * 18 / 100 ))
  REPLY=""
  repeat $fill REPLY+="█"
  repeat $(( 18 - fill )) REPLY+="░"
}

meow_color_line() {
  local -a rainbow=(31 33 32 36 34 35)
  REPLY=$'\033['"${rainbow[$(( (${2:-0} % 6) + 1 ))]}"'m'"$1"$'\033[0m'
}

# The gauge rows keep their bars in one column. Each label is padded to the
# longest one shown, so bars and percentages no longer step right with every
# longer label ("Disk Usage:" is one wider than "CPU Usage:", "Memory
# Pressure:" six). Labels are plain ASCII, so a character count is a column
# count under any locale, and none of this forks.
typeset -a MEOW_ROW_KEYS MEOW_ROW_VALS
MEOW_ROW_KEYS=()
MEOW_ROW_VALS=()

# meow_row <label> <value>
meow_row() {
  MEOW_ROW_KEYS+=("$1")
  MEOW_ROW_VALS+=("$2")
}

# meow_gauge <label> <percent> [detail]
# The percentage is right-aligned to three places so the % signs line up too.
meow_gauge() {
  local pct="${2:-0}" bar color
  meow_bar "$pct";   bar="$REPLY"
  meow_color "$pct"; color="$REPLY"
  (( ${#pct} < 3 )) && pct="${(l:3:)pct}"
  meow_row "$1" "${color}${bar} ${pct}%${3:+ $3}"
}

# Appends the collected rows to INFO_LINES with their labels padded to a
# common width.
meow_flush_rows() {
  local -i width=0 i
  local key
  for key in "${MEOW_ROW_KEYS[@]}"; do
    (( ${#key} > width )) && width=${#key}
  done
  for (( i = 1; i <= ${#MEOW_ROW_KEYS}; i++ )); do
    INFO_LINES+=("${CYAN}${(r:width:)MEOW_ROW_KEYS[i]} ${MEOW_ROW_VALS[i]}${RESET}")
  done
}

# ---------------------------------------------------------------------------
# Probes
#
# Everything below reads /proc and /sys straight through the shell. That needs
# no coreutils, no procps and no util-linux, so it behaves the same on glibc,
# musl, BusyBox and Alpine -- any kernel that mounts /proc. df is the only
# command left that has no kernel file to read instead.
# ---------------------------------------------------------------------------

# Trims surrounding whitespace without needing extended_glob, which
# "emulate -LR zsh" leaves switched off.
meow_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  REPLY="$s"
}

meow_plural() {
  if (( $1 == 1 )); then REPLY="$1 $2"; else REPLY="$1 ${2}s"; fi
}

# Linux style: "2 days, 2 hours, 5 minutes" -- matches what uptime -p printed.
# The old version built this with "day$(( days == 1 ? 0 : 1 ))", which appends
# the arithmetic result, so it literally rendered "2 day1" and "1 day0".
meow_format_uptime() {
  local -i total=${1:-0} days hours minutes
  local -a parts=()
  days=$(( total / 86400 ))
  hours=$(( (total % 86400) / 3600 ))
  minutes=$(( (total % 3600) / 60 ))
  (( days > 0 ))    && { meow_plural $days day;      parts+=("$REPLY") }
  (( hours > 0 ))   && { meow_plural $hours hour;    parts+=("$REPLY") }
  (( minutes > 0 )) && { meow_plural $minutes minute; parts+=("$REPLY") }
  (( ${#parts} == 0 )) && parts=("less than a minute")
  REPLY="${(j:, :)parts}"
}

meow_arch() {
  REPLY="$(uname -m 2>/dev/null)"
  [[ -n "$REPLY" ]] || REPLY="${CPUTYPE:-}"
  [[ -n "$REPLY" ]] || REPLY="unknown-arch"
}

meow_hostname() {
  REPLY="${HOST:-}"
  [[ -n "$REPLY" ]] || { [[ -r /proc/sys/kernel/hostname ]] && REPLY="$(</proc/sys/kernel/hostname)" }
  [[ -n "$REPLY" ]] || { [[ -r /etc/hostname ]] && REPLY="$(</etc/hostname)" }
  REPLY="${REPLY%%$'\n'*}"
  [[ -n "$REPLY" ]] || REPLY="unknown-host"
}

meow_model_name() {
  local -a sources=(
    /sys/devices/virtual/dmi/id/product_name
    /sys/firmware/devicetree/base/model
    /proc/device-tree/model
  )
  local path
  REPLY=""
  for path in $sources; do
    [[ -r "$path" ]] || continue
    REPLY="$(<$path)"
    REPLY="${REPLY%%$'\n'*}"
    meow_trim "$REPLY"
    [[ -n "$REPLY" ]] && return
  done
  REPLY="Linux Machine"
}

# /proc/cpuinfo names the CPU on x86 and on most ARM boards. lscpu is kept only
# as a last resort because it costs a process, and the answer is cached anyway.
meow_cpu_model() {
  local line key value
  local model="" hardware="" processor=""
  if [[ -r /proc/cpuinfo ]]; then
    while IFS=: read -r key value; do
      key="${key//[[:space:]]/}"
      meow_trim "$value"; value="$REPLY"
      case "$key" in
        ("modelname") [[ -n "$model" ]]     || model="$value" ;;
        ("Hardware")  [[ -n "$hardware" ]]  || hardware="$value" ;;
        ("Processor") [[ -n "$processor" ]] || processor="$value" ;;
      esac
    done < /proc/cpuinfo
  fi
  REPLY="$model"
  [[ -n "$REPLY" ]] || REPLY="$hardware"
  [[ -n "$REPLY" ]] || REPLY="$processor"
  if [[ -z "$REPLY" ]] && (( $+commands[lscpu] )); then
    local out="$(lscpu 2>/dev/null)"
    for line in ${(f)out}; do
      case "$line" in
        ("Model name:"*) meow_trim "${line#*:}"; break ;;
      esac
    done
  fi
}

meow_cpu_cores() {
  local raw part lo hi
  local -i total=0
  if [[ -r /sys/devices/system/cpu/present ]]; then
    raw="$(</sys/devices/system/cpu/present)"
    raw="${raw//[[:space:]]/}"
    for part in ${(s:,:)raw}; do
      if [[ "$part" == *-* ]]; then
        lo="${part%%-*}"; hi="${part##*-}"
        [[ "$lo" == <-> && "$hi" == <-> ]] && (( total += hi - lo + 1 ))
      elif [[ "$part" == <-> ]]; then
        (( total++ ))
      fi
    done
  fi
  if (( total <= 0 )) && [[ -r /proc/cpuinfo ]]; then
    local key value
    while IFS=: read -r key value; do
      key="${key//[[:space:]]/}"
      [[ "$key" == processor ]] && (( total++ ))
    done < /proc/cpuinfo
  fi
  if (( total > 0 )); then REPLY=$total; else REPLY=""; fi
}

meow_format_cores() {
  local -i cores=${1:-1}
  (( cores > 0 )) || cores=1
  if (( cores == 1 )); then REPLY="1 core"; else REPLY="${cores} cores"; fi
}

meow_uptime() {
  local raw seconds
  REPLY="N/A"
  [[ -r /proc/uptime ]] || return
  raw="$(</proc/uptime)"
  seconds="${${raw%% *}%%.*}"
  [[ "$seconds" == <-> ]] || return
  meow_format_uptime "$seconds"
}

meow_primary_ip() {
  local out line
  local -a fields
  REPLY=""
  if (( $+commands[ip] )); then
    out="$(ip -4 route get 1.1.1.1 2>/dev/null)"
    fields=(${=out})
    local -i i
    for (( i = 1; i <= $#fields; i++ )); do
      if [[ "${fields[i]}" == src && -n "${fields[i+1]-}" ]]; then
        REPLY="${fields[i+1]}"
        break
      fi
    done
  fi
  if [[ -z "$REPLY" && -r /proc/net/fib_trie ]]; then
    local prev=""
    while IFS= read -r line; do
      if [[ "$line" == *"32 host"* && -n "$prev" ]]; then
        local candidate="${prev##*[[:space:]]}"
        if [[ "$candidate" == <->.<->.<->.<-> && "$candidate" != 127.* ]]; then
          REPLY="$candidate"
          break
        fi
      fi
      prev="$line"
    done < /proc/net/fib_trie
  fi
  [[ -n "$REPLY" ]] || REPLY="N/A"
}

meow_battery() {
  local path capacity type_path supply
  REPLY=""
  for path in /sys/class/power_supply/BAT*/capacity(N) /sys/class/power_supply/*/capacity(N); do
    supply="${path:h}"
    type_path="${supply}/type"
    if [[ "${supply:t}" != BAT* ]]; then
      [[ -r "$type_path" && "$(<$type_path)" == Battery* ]] || continue
    fi
    capacity="$(<$path)"
    capacity="${capacity//[[:space:]]/}"
    if [[ "$capacity" == <-> ]]; then
      REPLY="${capacity}%"
      return
    fi
  done
}

# free(1) is procps and its output differs on BusyBox, so read the kernel file.
meow_memory() {
  local key value
  local -i total=0 available=0 free=0 buffers=0 cached=0 reclaimable=0
  local -i swap_total=0 swap_free=0 have_available=0
  MEOW_RAM_USED=0 MEOW_RAM_TOTAL=0 MEOW_RAM_PERCENT=0
  MEOW_SWAP_USED=0 MEOW_SWAP_TOTAL=0 MEOW_SWAP_PERCENT=0
  [[ -r /proc/meminfo ]] || return
  while IFS=: read -r key value; do
    value="${value%%kB*}"
    value="${value//[[:space:]]/}"
    [[ "$value" == <-> ]] || continue
    case "$key" in
      (MemTotal)     total=$value ;;
      (MemAvailable) available=$value; have_available=1 ;;
      (MemFree)      free=$value ;;
      (Buffers)      buffers=$value ;;
      (Cached)       cached=$value ;;
      (SReclaimable) reclaimable=$value ;;
      (SwapTotal)    swap_total=$value ;;
      (SwapFree)     swap_free=$value ;;
    esac
  done < /proc/meminfo
  (( total > 0 )) || return
  local -i used
  if (( have_available )); then
    used=$(( total - available ))
  else
    used=$(( total - free - buffers - cached - reclaimable ))
  fi
  (( used < 0 )) && used=0
  MEOW_RAM_TOTAL=$(( total / 1024 ))
  MEOW_RAM_USED=$(( used / 1024 ))
  (( MEOW_RAM_TOTAL > 0 )) && MEOW_RAM_PERCENT=$(( MEOW_RAM_USED * 100 / MEOW_RAM_TOTAL ))
  MEOW_SWAP_TOTAL=$(( swap_total / 1024 ))
  MEOW_SWAP_USED=$(( (swap_total - swap_free) / 1024 ))
  (( MEOW_SWAP_TOTAL > 0 )) && MEOW_SWAP_PERCENT=$(( MEOW_SWAP_USED * 100 / MEOW_SWAP_TOTAL ))
}

# -P -k is the POSIX spelling: -m is a GNU extension BusyBox may not carry, and
# -P keeps long device names from wrapping onto a second line.
meow_disk_probe() {
  local out line
  local -a fields
  MEOW_DISK_USED=0 MEOW_DISK_TOTAL=1 MEOW_DISK_PERCENT=0
  out="$(df -P -k / 2>/dev/null)"
  [[ -n "$out" ]] || out="$(df -k / 2>/dev/null)"
  [[ -n "$out" ]] || return
  line="${${(f)out}[2]}"
  fields=(${=line})
  [[ "${fields[2]-}" == <-> && "${fields[3]-}" == <-> ]] || return
  MEOW_DISK_TOTAL=$(( fields[2] / 1024 ))
  MEOW_DISK_USED=$(( fields[3] / 1024 ))
  (( MEOW_DISK_TOTAL > 0 )) || MEOW_DISK_TOTAL=1
  MEOW_DISK_PERCENT=$(( MEOW_DISK_USED * 100 / MEOW_DISK_TOTAL ))
}

# Disk usage moves slowly, and df is the one process this banner cannot avoid,
# so its answer is reused for MEOW_SAMPLE_TTL seconds like the other samples.
meow_disk() {
  local -a fields
  if meow_cache_get disk $MEOW_SAMPLE_TTL; then
    fields=(${=REPLY})
    if (( ${#fields} == 3 )); then
      MEOW_DISK_USED=${fields[1]} MEOW_DISK_TOTAL=${fields[2]} MEOW_DISK_PERCENT=${fields[3]}
      return
    fi
  fi
  meow_disk_probe
  (( MEOW_DISK_TOTAL > 1 )) && meow_cache_set disk "$MEOW_DISK_USED $MEOW_DISK_TOTAL $MEOW_DISK_PERCENT"
}

# Two readings of /proc/stat are needed for a real percentage; the previous one
# is kept in the same cache file the hardware facts live in.
meow_cpu_usage() {
  local cpu user nice system idle iowait irq softirq steal rest
  local -i idle_now total_now total_prev=0 idle_prev=0 usage=0 total_delta idle_delta
  REPLY=0
  [[ -r /proc/stat ]] || return
  read -r cpu user nice system idle iowait irq softirq steal rest < /proc/stat
  [[ "$user" == <-> && "$idle" == <-> ]] || return
  idle_now=$(( idle + iowait ))
  total_now=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
  if meow_cache_get cpu_sample -1; then
    total_prev="${REPLY%% *}"
    idle_prev="${REPLY##* }"
  fi
  meow_cache_set cpu_sample "${total_now} ${idle_now}"
  if (( total_prev > 0 && total_now > total_prev )); then
    total_delta=$(( total_now - total_prev ))
    idle_delta=$(( idle_now - idle_prev ))
    usage=$(( (100 * (total_delta - idle_delta)) / total_delta ))
  elif (( total_now > 0 )); then
    usage=$(( (100 * (total_now - idle_now)) / total_now ))
  fi
  (( usage < 0 )) && usage=0
  (( usage > 100 )) && usage=100
  REPLY=$usage
}

meow_gpu_utils() {
  typeset -ga MEOW_GPU_UTILS
  MEOW_GPU_UTILS=()
  local util line
  local -i card=0
  if meow_cache_get gpu_utils $MEOW_SAMPLE_TTL; then
    [[ -n "$REPLY" ]] && MEOW_GPU_UTILS=(${=REPLY})
    return
  fi
  if (( $+commands[nvidia-smi] )); then
    local out="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)"
    for line in ${(f)out}; do
      util="${line//[[:space:]]/}"
      [[ "$util" == <-> ]] && MEOW_GPU_UTILS+=("$util")
    done
  fi
  if (( ${#MEOW_GPU_UTILS} == 0 )); then
    while [[ -r "/sys/class/drm/card${card}/device/gpu_busy_percent" ]]; do
      util="$(</sys/class/drm/card${card}/device/gpu_busy_percent)"
      util="${util//[[:space:]]/}"
      [[ "$util" == <-> ]] && MEOW_GPU_UTILS+=("$util")
      (( card++ ))
    done
  fi
  meow_cache_set gpu_utils "${(j: :)MEOW_GPU_UTILS}"
}

meow_parent_comm() {
  REPLY=""
  [[ -r "/proc/$PPID/comm" ]] && REPLY="$(</proc/$PPID/comm)"
  [[ -n "$REPLY" ]] || REPLY="$(ps -o comm= -p $PPID 2>/dev/null)"
  REPLY="${REPLY%%$'\n'*}"
}

# ---------------------------------------------------------------------------
# Gather
# ---------------------------------------------------------------------------

meow_cache_load

meow_hostname;   HOST_NAME="$REPLY"

meow_cached arch $MEOW_STATIC_TTL meow_arch
ARCH="$REPLY"
[[ -n "$ARCH" ]] || ARCH="unknown-arch"

meow_model_name; MODEL_NAME="$REPLY"
meow_cached cpu_model $MEOW_STATIC_TTL meow_cpu_model
CHIP="$REPLY"
[[ -n "$CHIP" ]] || CHIP="Unknown CPU"

meow_cached cpu_cores $MEOW_STATIC_TTL meow_cpu_cores
CPU_CORES="$REPLY"
[[ "$CPU_CORES" == <-> ]] || CPU_CORES=1
meow_format_cores "$CPU_CORES"; CPU_CORE_TEXT="$REPLY"

meow_primary_ip; IP_ADDR="$REPLY"
meow_uptime;     UP_TIME="$REPLY"
meow_battery;    BATTERY="$REPLY"
meow_cpu_usage;  CPU_USAGE="$REPLY"

meow_memory
meow_disk
meow_gpu_utils

VM_USED=$MEOW_RAM_USED
VM_TOTAL=$MEOW_RAM_TOTAL
RAM_PERCENT=$MEOW_RAM_PERCENT
SWAP_USED=$MEOW_SWAP_USED
SWAP_TOTAL=$MEOW_SWAP_TOTAL
SWAP_PERCENT=$MEOW_SWAP_PERCENT
DISK_USED=$MEOW_DISK_USED
DISK_TOTAL=$MEOW_DISK_TOTAL
DISK_PERCENT=$MEOW_DISK_PERCENT

WELCOMES=(
"Welcome back!"
"Hello human!"
"Kawaii typing detected!"
"Cat says great!"
"Have a purrfect day!"
"Meow meow!"
"You look comfy!"
"Let's code!"
"Paws activated!"
"Cuteness overload!"
"Enjoy your terminal!"
"Feline power!"
"Stay cozy!"
"Time to hack!"
"Cat inspected!"
"All systems purrfect!"
"Hello world, meow!"
"Cat mode on!"
"Stay pawsitive!"
"Kitty approves your change!"
"Make meow changes!"
"Git commit approved by cat!"
"Deploying cuteness..."
"Terminal purrformance optimal!"
"Cat detected hacker energy!"
"Linting your code with paws..."
"Compiling meowdule..."
"Debugging with whiskers..."
"Running pawcess..."
"Cat watching your commits."
"Code review by kitty complete!"
"System check: purrfect!"
"Whiskers calibrated."
"Claws ready for coding!"
"Keyboard warmed by paws."
"Terminal smells like productivity."
"Coffee detected. Coding likely."
"Cat supervising development."
"Boot sequence approved by cat."
"Purrmission granted!"
"Terminal ready. Meow!"
"Cat scanned the system."
"No bugs detected (cat hopes lol)."
"Whiskers sense good code."
"Purrcess initialized."
"Shell opened successfully."
"Cat guarding the terminal."
"Keep coding, human."
"Terminal looks cozy today."
"Meowgic detected!"
"Your code smells interesting."
"Another day, another commit."
"Cat recommends more snacks."
"Human detected at keyboard."
"Stay focused, stay pawsitive."
"Whisker-driven development."
"Code like a feline."
"System uptime approved."
"Cat believes in your code."
"Meow is a good time to code."
"Paws on keyboard!"
)

WELCOME="${WELCOMES[$(( (RANDOM % ${#WELCOMES[@]}) + 1 ))]}"

meow_echo ""
meow_echo "${BLUE}Welcome to Meow-Meow Terminal!${RESET}"
meow_echo "${CYAN}Cat says:${RESET} ${ORANGE}${WELCOME}${RESET}"
meow_echo ""

if [[ "$USER" == "root" ]]; then
  CAT_1=$'   /\\_/\\\\\n  ( ⊙ʌ⊙ )'
  CAT_2=$'    /\\_/\\\\\n   ( ⊙ʌ⊙ )'
  CAT_1_TAIL=' ʔ/ づ づ'
  CAT_2_TAIL='   づ づ  \ʃ'
  CAT_1_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
  CAT_2_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
  # This caption is 23 columns wide, so its tab lands on column 24 while the
  # short face rows land on 16. Two tabs put the faces on 24 as well, keeping
  # the right-hand cat stacked over its own caption.
  MEOW_FACE_GAP=$'\t\t'
else
  CAT_1=$'   /\\_/\\\\\n  ( ≧ω≦ )'
  CAT_2=$'    /\\_/\\\\\n   ( OωO )'
  CAT_1_TAIL=' ʔ/ づ づ'
  CAT_2_TAIL='   づ づ  \ʃ'
  CAT_1_TEXT="${PINK} Kimochiii!${RESET}"
  CAT_2_TEXT="${BLUE}  Kawayiii!${RESET}"
  MEOW_FACE_GAP=$'\t'
fi

# Was: paste <(...) <(...) | while read. That spent a pipeline, two process
# substitutions and an external paste on four lines of cat.
typeset -a MEOW_FACE_L MEOW_FACE_R
MEOW_FACE_L=("${(@f)CAT_1}" "$CAT_1_TAIL" "$CAT_1_TEXT")
MEOW_FACE_R=("${(@f)CAT_2}" "$CAT_2_TAIL" "$CAT_2_TEXT")
# Tabs rather than spaces: a terminal that draws ambiguous-width characters
# such as ω and ⊙ double wide still lands every row on the same tab stop.
for (( MEOW_I = 1; MEOW_I <= ${#MEOW_FACE_L}; MEOW_I++ )); do
  MEOW_GAP="$MEOW_FACE_GAP"
  (( MEOW_I == ${#MEOW_FACE_L} )) && MEOW_GAP=$'\t'
  printf '%b%s%b\n' "${MEOW_FACE_L[MEOW_I]}" "$MEOW_GAP" "${MEOW_FACE_R[MEOW_I]-}"
done

meow_echo ""

if [[ "$USER" == "root" ]]; then
  USER_NAME="${RED}powerful master${RESET}"
  meow_echo "${CYAN}Cat whispers: your username is ${USER_NAME}${CYAN}... oh no!${RESET}"
  meow_echo "${RED}Cat is scared!${RESET}"
  meow_echo "${YELLOW}Please do not delete the system, ${RED}powerful master${YELLOW}...${RESET}"
  meow_echo "${YELLOW}rm -rf / is not a toy. That is not fun!${RESET}"
  meow_echo "${CYAN}Cat hides behind the keyboard... ${RED}please do not delete meow.${RESET}"
else
  USER_NAME="${YELLOW}${USER}${RESET}"
  meow_echo "${CYAN}Cat whispers: your username is ${USER_NAME}${CYAN}, noted!${RESET}"
fi

CONNECTION_TYPE=""
LOGIN_IP=""

if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  CONNECTION_TYPE="SSH"
  LOGIN_IP="${${=SSH_CONNECTION}[1]}"
  [[ -n "$LOGIN_IP" ]] || LOGIN_IP="${${=SSH_CLIENT}[1]}"
else
  meow_parent_comm
  if [[ "$REPLY" == *telnet* || "$REPLY" == *rlogin* ]]; then
    CONNECTION_TYPE="telnet"
    LOGIN_IP="${${=$(who am i 2>/dev/null)}[-1]}"
    LOGIN_IP="${LOGIN_IP//[()]/}"
    if [[ -z "$LOGIN_IP" ]] && (( $+commands[ss] )); then
      LOGIN_IP="$(ss -tn 2>/dev/null | awk '/ESTAB/ && /:23 / {gsub(/:[0-9]+$/, "", $5); print $5; exit}')"
    fi
    if [[ -z "$LOGIN_IP" ]] && (( $+commands[netstat] )); then
      LOGIN_IP="$(netstat -tn 2>/dev/null | awk '/ESTABLISHED/ && /:23 / {gsub(/:[0-9]+$/, "", $5); print $5; exit}')"
    fi
  fi
fi

if [[ -n "$CONNECTION_TYPE" ]]; then
  if [[ -n "$LOGIN_IP" ]]; then
    meow_echo "${CYAN}Cat noticed: you connected via ${MAGENTA}${CONNECTION_TYPE}${CYAN} from ${YELLOW}${LOGIN_IP}${CYAN}, is this you?${RESET}"
  else
    meow_echo "${CYAN}Cat noticed: you connected via ${MAGENTA}${CONNECTION_TYPE}${CYAN} from ${YELLOW}somewhere mysterious${CYAN}...${RESET}"
  fi
else
  TTY_INFO="${TTY:-}"
  [[ -n "$TTY_INFO" ]] || TTY_INFO="$(tty 2>/dev/null)"
  [[ -n "$TTY_INFO" ]] && TTY_INFO="${YELLOW}${TTY_INFO}${RESET}" || TTY_INFO="${YELLOW}unknown${RESET}"
  meow_echo "${CYAN}Cat noticed: you're on local terminal ${TTY_INFO}${RESET}"
fi

meow_echo "${CYAN}Cat sniffed the machine: hostname ${YELLOW}${HOST_NAME}${RESET}"
meow_echo "${CYAN}Cat checked your primary IP: ${YELLOW}${IP_ADDR}${RESET}"
meow_echo "${CYAN}Cat checked the uptime: ${YELLOW}${UP_TIME}${RESET}"

if [[ -n "$BATTERY" ]]; then
  BAT_VAL=${BATTERY%\%}

  if (( BAT_VAL < 20 )); then
    BAT_COLOR=$RED
    BAT_TEXT="Battery is low. Time to plug in soon."
  elif (( BAT_VAL < 50 )); then
    BAT_COLOR=$ORANGE
    BAT_TEXT="Battery is halfway there. Still okay for now."
  else
    BAT_COLOR=$GREEN
    BAT_TEXT="Battery looks healthy. Have a nice meowing day!"
  fi

  meow_echo "${CYAN}Battery level: ${BAT_COLOR}${BATTERY}${CYAN}, ${BAT_TEXT}${RESET}"
fi

meow_echo ""

CAT_ART_1=(
"       I'm hungry!  "
"              ノ    "
"   ／l、 _․         "
"  /  l._/. フ       "
" ( ﾟ⩊ ｡  . ).       "
"  l     ~ヽ         "
"   l      -.\   /)  "
"   じしf_  , .)ノ/  "
"                    "
"                    "
)

CAT_ART_2=(
"       touch me!    "
"              ノ    "
"   ／l、 _․         "
"  /  l._/. フ       "
" (.˃ ᵕ ˂. ).        "
"  l     ~ヽ         "
"   l      -.\   /)  "
"   じしf_  , .)ノ/  "
"                    "
"                    "
)

typeset -a RAW_ART
if (( (RANDOM % 2) == 0 )); then
  RAW_ART=("${CAT_ART_1[@]}")
else
  RAW_ART=("${CAT_ART_2[@]}")
fi

typeset -a DEVICE_ART INFO_LINES
integer art_index=0

for line in "${RAW_ART[@]}"; do
  meow_color_line "$line" "$art_index"
  DEVICE_ART+=("$REPLY")
  (( art_index++ ))
done

INFO_LINES+=("${BLUE}${MODEL_NAME}${RESET}")
INFO_LINES+=("${DIM}CPU:${RESET} ${YELLOW}${CHIP}${RESET} ${DIM}(${ARCH})${RESET}")
INFO_LINES+=("${DIM}User:${RESET} ${LIGHT_GREEN}${USER}${RESET}@${LIGHT_GREEN}${HOST_NAME}${RESET}")
INFO_LINES+=("${DIM}========================================${RESET}")
meow_gauge "CPU Usage:"  "$CPU_USAGE"    "(${CPU_CORE_TEXT})"
meow_gauge "RAM Usage:"  "$RAM_PERCENT"  "(${VM_USED}/${VM_TOTAL} MB)"
meow_gauge "Disk Usage:" "$DISK_PERCENT" "(${DISK_USED}/${DISK_TOTAL} MB)"
if (( SWAP_TOTAL > 0 )); then
  meow_gauge "Swap Usage:" "$SWAP_PERCENT" "(${SWAP_USED}/${SWAP_TOTAL} MB)"
fi

if (( ${#MEOW_GPU_UTILS} == 1 )); then
  meow_gauge "GPU Usage:" "${MEOW_GPU_UTILS[1]}"
elif (( ${#MEOW_GPU_UTILS} > 1 )); then
  GPU_INDEX=0
  for util in "${MEOW_GPU_UTILS[@]}"; do
    meow_gauge "GPU${GPU_INDEX}:" "$util"
    (( GPU_INDEX++ ))
  done
fi

meow_flush_rows

# The old renderer measured each line's display width with a per-character loop
# and then padded by "target_width - width", where target_width was 1. That is
# never positive, so the padding was always zero and every measurement was
# discarded. It also used printf -v, which zsh only learned in 5.3.
#
# More info rows than art rows (a second GPU plus swap, several disks) used to
# vanish, because the loop only walked the ten art rows. The art column is now
# padded out with blanks instead, the way fastfetch pads its logo.
MEOW_ART_PAD="${(l:20:)}"
integer row_index row_count=${#DEVICE_ART}
(( ${#INFO_LINES} > row_count )) && row_count=${#INFO_LINES}
for (( row_index = 1; row_index <= row_count; row_index++ )); do
  printf '%b %b\n' "${DEVICE_ART[row_index]:-$MEOW_ART_PAD}" "${INFO_LINES[row_index]:-}"
done

meow_echo ""
meow_echo "${DIM}============================================================${RESET}"
meow_echo ""

meow_cache_save

# Functions are always global in zsh, so they are removed by hand. Every
# variable above is local and goes away on its own when this function returns.
unfunction -m 'meow_*' 2>/dev/null

if (( $+commands[fastfetch] )); then
  fastfetch
else
  printf '%b\n' "\033[38;5;201mfastfetch not installed\033[0m"
fi
}
