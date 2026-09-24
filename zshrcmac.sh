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
local MEOW_DISK_TOTAL MEOW_DISK_PERCENT MEM_PRESSURE RAM_USED RAM_TOTAL
local MEOW_MAC_MODEL MEOW_MAC_CHIP MEOW_SYS_CORES MEOW_SYS_MEMBYTES
local MEOW_SYS_BOOTSEC MEOW_SYS_SWAP MEOW_SYS_MEMFREE MEOW_SYS_PCORES MEOW_CPU_UNIT
local -a WELCOMES CAT_ART_1 CAT_ART_2 MEOW_GPU_NAMES
local -A MEOW_CACHE

zmodload zsh/datetime 2>/dev/null
zmodload zsh/zselect 2>/dev/null

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

# One record per line in the file, so a value never carries a newline.
meow_cache_set() {
  MEOW_CACHE[$1]="${MEOW_NOW} ${2//$'\n'/ }"
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

# Hardware only changes across a power cycle, so everything cached belongs to
# the boot it was measured in. A new boot starts from an empty cache: a swapped
# CPU, GPU or memory shows up in the first shell after the machine comes back,
# instead of up to MEOW_STATIC_TTL later.
#
# $1 is an opaque boot id, or the boot time in epoch seconds. The kernel moves
# the boot time whenever the clock is stepped (NTP after a wake from sleep, a
# manual change), so boot times under a minute apart are the same boot. No
# power cycle long enough to swap a part is that short.
meow_cache_bind_boot() {
  [[ -n "$1" && "$1" != 0 ]] || return 0
  if meow_cache_get boot -1; then
    [[ "$REPLY" == "$1" ]] && return 0
    [[ "$REPLY" == <-> && "$1" == <-> ]] && (( REPLY - $1 < 60 && $1 - REPLY < 60 )) && return 0
  fi
  MEOW_CACHE=()
  meow_cache_set boot "$1"
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
# macOS has no /proc, so these shell out -- but each command now runs once, the
# expensive ones are cached, and the ones that touch the network are bounded.
# ---------------------------------------------------------------------------

meow_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  REPLY="$s"
}

# macOS ships no timeout(1), so a blocked lookup has nothing to stop it. Run a
# command with a hard wall-clock limit instead.
#
# Only wrap commands that do not spawn children of their own: output travels
# down a pipe, and a surviving grandchild would keep that pipe open past the
# kill. route and ipconfig are both single binaries. Slow-but-reliable
# commands (system_profiler, top) are handled by the cache instead.
#
# The watchdog waits with zselect, a builtin, so it holds no child process and
# dismissing it leaves nothing running. An external sleep would be orphaned
# instead and linger for the rest of the limit, which is what the CI runner
# reported as "Terminate orphan process: (sleep)". The sleep branch is only
# for the unlikely case that zsh/zselect is unavailable.
meow_run_limited() {
  emulate -L zsh
  setopt no_monitor no_notify

  local limit="${1:-1}"
  shift

  (
    "$@" 2>/dev/null &
    cmd_pid=$!

    if (( $+builtins[zselect] )); then
      ( zselect -t $(( limit * 100 )); kill -KILL "$cmd_pid" ) >/dev/null 2>&1 &
    else
      ( sleep "$limit"; kill -KILL "$cmd_pid" ) >/dev/null 2>&1 &
    fi
    watchdog_pid=$!

    wait "$cmd_pid" 2>/dev/null
    ret=$?
    kill -KILL "$watchdog_pid" 2>/dev/null
    exit $ret
  )
}

# macOS style: "2d 2h 5m", as this script has always printed it.
meow_format_uptime() {
  local -i total=${1:-0} days hours minutes
  local -a parts=()
  days=$(( total / 86400 ))
  hours=$(( (total % 86400) / 3600 ))
  minutes=$(( (total % 3600) / 60 ))
  (( days > 0 ))    && parts+=("${days}d")
  (( hours > 0 ))   && parts+=("${hours}h")
  (( minutes > 0 )) && parts+=("${minutes}m")
  (( ${#parts} == 0 )) && parts=("less than a minute")
  REPLY="${(j: :)parts}"
}

# uname -m is authoritative. $CPUTYPE is baked in when zsh is compiled, so a
# Homebrew zsh built for x86_64 would misreport an Apple Silicon Mac. Caching
# makes the process cost vanish after the first shell.
meow_arch() {
  REPLY="$(uname -m 2>/dev/null)"
  [[ -n "$REPLY" ]] || REPLY="${CPUTYPE:-}"
  [[ -n "$REPLY" ]] || REPLY="unknown-arch"
}

meow_hostname() {
  REPLY="${HOST:-}"
  [[ -n "$REPLY" ]] || REPLY="$(hostname 2>/dev/null)"
  REPLY="${REPLY%%$'\n'*}"
  [[ -n "$REPLY" ]] || REPLY="unknown-host"
}

# One sysctl process answers six questions. The first five keys exist on every
# macOS 10.x and later, so their reply lines cannot slip out of order. The last,
# kern.memorystatus_level, is the figure memory_pressure prints as its "free
# percentage"; it goes last so that a system without it (10.8 and older) just
# returns one line fewer.
#
# hw.logicalcpu counts hardware threads and is what CPU usage is divided by;
# hw.physicalcpu counts cores and is what the banner shows.
meow_sysctl_batch() {
  local out
  local -a lines
  MEOW_SYS_CORES=0 MEOW_SYS_PCORES=0 MEOW_SYS_MEMBYTES=0 MEOW_SYS_BOOTSEC=0
  MEOW_SYS_SWAP="" MEOW_SYS_MEMFREE=""
  out="$(sysctl -n hw.logicalcpu hw.physicalcpu hw.memsize kern.boottime vm.swapusage kern.memorystatus_level 2>/dev/null)"
  lines=(${(f)out})
  (( ${#lines} >= 5 )) || return 1
  [[ "${lines[1]}" == <-> ]] && MEOW_SYS_CORES=${lines[1]}
  [[ "${lines[2]}" == <-> ]] && MEOW_SYS_PCORES=${lines[2]}
  [[ "${lines[3]}" == <-> ]] && MEOW_SYS_MEMBYTES=${lines[3]}
  # "{ sec = 1712345678, usec = 0 } Fri Apr  5 ..."
  local boot="${lines[4]#*sec = }"
  boot="${boot%%,*}"
  boot="${boot//[[:space:]]/}"
  [[ "$boot" == <-> ]] && MEOW_SYS_BOOTSEC=$boot
  MEOW_SYS_SWAP="${lines[5]}"
  [[ "${lines[6]-}" == <-> ]] && MEOW_SYS_MEMFREE=${lines[6]}
  return 0
}

# Physical cores, in REPLY; MEOW_CPU_UNIT says "cores", or "threads" in the
# unlikely case only the logical count could be read.
meow_cpu_cores() {
  MEOW_CPU_UNIT=cores
  REPLY=${MEOW_SYS_PCORES:-0}
  [[ "$REPLY" == <-> && $REPLY -gt 0 ]] || REPLY="$(sysctl -n hw.physicalcpu 2>/dev/null)"
  [[ "$REPLY" == <-> && $REPLY -gt 0 ]] && return
  MEOW_CPU_UNIT=threads
  REPLY=${MEOW_SYS_CORES:-0}
  [[ "$REPLY" == <-> && $REPLY -gt 0 ]] || REPLY=""
}

# meow_format_cores <count> [unit]  ->  "1 core", "8 cores", "16 threads"
meow_format_cores() {
  local -i count=${1:-0}
  local unit="${2:-cores}"
  (( count == 1 )) && unit="${unit%s}"
  REPLY="$count $unit"
}

# kern.boottime is an integer from the kernel. The old code read "who -b" and
# fed its output to `date -j -f '%b %e %H:%M %Y'`, which needs English month
# abbreviations and so returned N/A under any other locale.
meow_uptime() {
  local -i boot=${MEOW_SYS_BOOTSEC:-0} now=${MEOW_NOW:-0}
  REPLY="N/A"
  (( boot > 0 && now >= boot )) || return
  meow_format_uptime $(( now - boot ))
}

# system_profiler is the slowest thing this banner ever ran, at roughly one to
# three seconds for the pair of calls. None of what it reports can change while
# the machine is booted, so it is read once and cached.
meow_mac_hardware() {
  local out line key value
  MEOW_MAC_MODEL="" MEOW_MAC_CHIP=""
  out="$(system_profiler SPHardwareDataType 2>/dev/null)"
  for line in ${(f)out}; do
    [[ "$line" == *:* ]] || continue
    key="${line%%:*}"; value="${line#*:}"
    key="${key//[[:space:]]/}"
    meow_trim "$value"; value="$REPLY"
    [[ -n "$value" ]] || continue
    case "$key" in
      (ModelName)     [[ -n "$MEOW_MAC_MODEL" ]] || MEOW_MAC_MODEL="$value" ;;
      (Chip)          [[ -n "$MEOW_MAC_CHIP" ]]  || MEOW_MAC_CHIP="$value" ;;
      (ProcessorName) [[ -n "$MEOW_MAC_CHIP" ]]  || MEOW_MAC_CHIP="$value" ;;
    esac
  done
  if [[ -z "$MEOW_MAC_CHIP" ]]; then
    MEOW_MAC_CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    meow_trim "$MEOW_MAC_CHIP"; MEOW_MAC_CHIP="$REPLY"
  fi
}

# Non-zero only when system_profiler itself gave nothing. A reply with no
# chipset in it is an answer: Apple's virtual machines, the CI runner among
# them, list a display but no GPU.
meow_gpu_names() {
  local out line
  typeset -ga MEOW_GPU_NAMES
  MEOW_GPU_NAMES=()
  out="$(system_profiler SPDisplaysDataType 2>/dev/null)"
  [[ -n "$out" ]] || return 1
  for line in ${(f)out}; do
    [[ "$line" == *"Chipset Model:"* ]] || continue
    meow_trim "${line#*:}"
    [[ -n "$REPLY" ]] && MEOW_GPU_NAMES+=("$REPLY")
  done
  return 0
}

meow_battery() {
  local out line
  REPLY=""
  out="$(pmset -g batt 2>/dev/null)"
  for line in ${(f)out}; do
    if [[ "$line" == *%* ]]; then
      local rest="${line#*	}"
      local pct="${line%%\%*}"
      pct="${pct##*[!0-9]}"
      [[ "$pct" == <-> ]] && { REPLY="${pct}%"; return }
    fi
  done
}

# CPU usage right now. ps's %cpu on macOS is the kernel scheduler's figure for
# each thread: XNU folds a thread's run time in every 125 ms and decays it by
# 5/8 each time (osfmk/kern/priority.c), so it is a moving average over about
# the last half second, not the minute the BSD manual describes. Summed and
# divided by the logical CPU count, that is the machine's load at this moment,
# from one process that returns in milliseconds. On the macOS CI runner it came
# within a point, on average, of top's own one-second samples taken at the same
# moment; reading the tick counters directly would mean waiting on top, whose
# delay only takes whole seconds.
#
# This shell is left out. Its last half second is spent starting up (oh-my-zsh,
# plugins, this banner), and that would otherwise be reported as load on the
# machine.
#
# LC_ALL=C pins the decimal point; under de_DE or fr_FR ps would print "12,5"
# and every value would fail to parse.
meow_cpu_usage_raw() {
  local out pid value
  local -F sum=0
  local -i cores=${MEOW_SYS_CORES:-0} pct
  REPLY=""
  out="$(LC_ALL=C ps -A -o pid= -o %cpu= 2>/dev/null)" || return
  [[ -n "$out" ]] || return
  for pid value in ${=out}; do
    [[ "$pid" == "$$" ]] && continue
    [[ "$value" == <->.<-> || "$value" == <-> ]] && (( sum += value ))
  done
  (( cores > 0 )) || cores=1
  pct=$(( sum / cores + 0.5 ))
  (( pct > 100 )) && pct=100
  (( pct < 0 )) && pct=0
  REPLY=$pct
}

# Empty when ps gave nothing, so the banner says N/A instead of a made-up 0%.
meow_cpu_usage() {
  meow_cached cpu_usage $MEOW_SAMPLE_TTL meow_cpu_usage_raw
  [[ "$REPLY" == <-> ]] || REPLY=""
}

# Percentages are rounded, not truncated: (200a + b) / 2b is round-half-up in
# integer arithmetic. Truncating showed 40% where fastfetch, and this banner on
# Windows, showed 41-42% for the same memory.
# Used memory the way Activity Monitor and fastfetch count it: app memory
# (anonymous pages the kernel cannot simply drop, i.e. minus purgeable ones),
# plus wired, plus what the compressor occupies. The old sum of active + wired
# + compressed - speculative also counted the file cache as used, so it read
# well above both: 55% against fastfetch's 44% on the same CI runner.
# "Anonymous pages" appeared in vm_stat with 10.9; older systems keep the old
# formula.
meow_memory() {
  local out line key value
  local -i page_size=4096 active=0 wired=0 compressed=0 speculative=0
  local -i anonymous=-1 purgeable=0 used_pages
  MEOW_RAM_USED=0 MEOW_RAM_TOTAL=0 MEOW_RAM_PERCENT=0
  out="$(vm_stat 2>/dev/null)"
  for line in ${(f)out}; do
    if [[ "$line" == *"page size of"* ]]; then
      value="${line##*page size of }"
      value="${value%% bytes*}"
      [[ "$value" == <-> ]] && page_size=$value
      continue
    fi
    [[ "$line" == *:* ]] || continue
    key="${line%%:*}"; value="${line#*:}"
    value="${value//[[:space:]]/}"
    value="${value%.}"
    [[ "$value" == <-> ]] || continue
    case "$key" in
      ("Pages active")                 active=$value ;;
      ("Pages wired down")             wired=$value ;;
      ("Pages occupied by compressor") compressed=$value ;;
      ("Pages speculative")            speculative=$value ;;
      ("Anonymous pages")              anonymous=$value ;;
      ("Pages purgeable")              purgeable=$value ;;
    esac
  done
  local -i total_bytes=${MEOW_SYS_MEMBYTES:-0}
  MEOW_RAM_TOTAL=$(( total_bytes / 1048576 ))
  if (( anonymous >= 0 )); then
    used_pages=$(( anonymous - purgeable + wired + compressed ))
  else
    used_pages=$(( active + wired + compressed - speculative ))
  fi
  MEOW_RAM_USED=$(( used_pages * page_size / 1048576 ))
  (( MEOW_RAM_USED < 0 )) && MEOW_RAM_USED=0
  (( MEOW_RAM_TOTAL > 0 )) && MEOW_RAM_PERCENT=$(( (200 * MEOW_RAM_USED + MEOW_RAM_TOTAL) / (2 * MEOW_RAM_TOTAL) ))
}

meow_memory_pressure() {
  local out line value
  REPLY=0
  if [[ "${MEOW_SYS_MEMFREE-}" == <-> ]]; then
    REPLY=$(( 100 - MEOW_SYS_MEMFREE ))
    return
  fi
  (( $+commands[memory_pressure] )) || return
  out="$(memory_pressure 2>/dev/null)"
  for line in ${(f)out}; do
    [[ "$line" == *"System-wide memory free percentage"* ]] || continue
    value="${line##*: }"
    value="${value%\%*}"
    value="${value//[[:space:]]/}"
    [[ "$value" == <-> ]] && REPLY=$(( 100 - value ))
    return
  done
}

meow_swap() {
  local raw used total
  MEOW_SWAP_USED=0 MEOW_SWAP_TOTAL=0 MEOW_SWAP_PERCENT=0
  raw="${MEOW_SYS_SWAP:-}"
  [[ -n "$raw" ]] || return
  total="${raw#*total = }"; total="${total%% *}"
  used="${raw#*used = }";   used="${used%% *}"
  meow_mb_from_size "$total"; MEOW_SWAP_TOTAL=$REPLY
  meow_mb_from_size "$used";  MEOW_SWAP_USED=$REPLY
  (( MEOW_SWAP_TOTAL > 0 )) && MEOW_SWAP_PERCENT=$(( (200 * MEOW_SWAP_USED + MEOW_SWAP_TOTAL) / (2 * MEOW_SWAP_TOTAL) ))
}

meow_mb_from_size() {
  local val="${1:-0M}" number
  local -i out=0
  REPLY=0
  number="${val%[KMGkmg]}"
  [[ "$number" == <->.<-> || "$number" == <-> ]] || return
  case "$val" in
    (*[Gg]) out=$(( number * 1024 )) ;;
    (*[Mm]) out=$(( number )) ;;
    (*[Kk]) out=$(( number / 1024 )) ;;
  esac
  REPLY=$out
}

meow_disk_probe() {
  local out line target
  local -a fields
  MEOW_DISK_USED=0 MEOW_DISK_TOTAL=1 MEOW_DISK_PERCENT=0
  if [[ -d /System/Volumes/Data ]]; then target="/System/Volumes/Data"; else target="/"; fi
  out="$(df -P -k "$target" 2>/dev/null)"
  [[ -n "$out" ]] || return
  line="${${(f)out}[2]}"
  fields=(${=line})
  [[ "${fields[2]-}" == <-> && "${fields[4]-}" == <-> ]] || return
  # Size minus available, not df's Used column. On APFS every volume shares one
  # container, and Used counts only the volume asked about: the system volume,
  # VM swap and snapshots were all left out, so the banner read 64% on the CI
  # runner where fastfetch and Finder read 70%. Available is the container's
  # free space, so size minus it is what the whole disk has in use. HFS+
  # (10.12 and older) shares nothing, so there it makes no difference.
  MEOW_DISK_TOTAL=$(( fields[2] / 1024 ))
  MEOW_DISK_USED=$(( (fields[2] - fields[4]) / 1024 ))
  (( MEOW_DISK_TOTAL > 0 )) || MEOW_DISK_TOTAL=1
  MEOW_DISK_PERCENT=$(( (200 * MEOW_DISK_USED + MEOW_DISK_TOTAL) / (2 * MEOW_DISK_TOTAL) ))
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

meow_primary_ip() {
  local default_if ip_addr="" iface out line
  local -a candidates
  # -n stops route(8) reverse-resolving the gateway. Without it the lookup
  # waits out the whole resolver timeout whenever a VPN or proxy profile
  # leaves PTR queries unanswered, stalling every new shell for seconds.
  out="$(meow_run_limited 1 route -n get default)"
  for line in ${(f)out}; do
    if [[ "$line" == *interface:* ]]; then
      meow_trim "${line#*:}"; default_if="$REPLY"
      break
    fi
  done
  # Tunnels are not managed by IPConfiguration, so asking configd about one
  # only buys a round-trip and an empty answer.
  case "$default_if" in
    (utun*|ipsec*|ppp*|tun*|tap*|gif*|stf*) default_if="" ;;
  esac
  candidates=(en0 en1)
  [[ -n "$default_if" ]] && candidates=("$default_if" "${candidates[@]}")
  candidates=("${(@u)candidates}")
  for iface in "${candidates[@]}"; do
    ip_addr="$(meow_run_limited 1 ipconfig getifaddr "$iface")"
    ip_addr="${ip_addr//[[:space:]]/}"
    [[ -n "$ip_addr" ]] && break
  done
  [[ -n "$ip_addr" ]] || ip_addr="N/A"
  REPLY="$ip_addr"
}

# ---------------------------------------------------------------------------
# Gather
# ---------------------------------------------------------------------------

meow_cache_load
meow_sysctl_batch
meow_cache_bind_boot "$MEOW_SYS_BOOTSEC"

meow_hostname;   HOST_NAME="$REPLY"

meow_cached arch $MEOW_STATIC_TTL meow_arch
ARCH="$REPLY"
[[ -n "$ARCH" ]] || ARCH="unknown-arch"

# One system_profiler pair, cached, instead of two calls on every shell.
if meow_cache_get mac_model $MEOW_STATIC_TTL; then
  MODEL_NAME="$REPLY"
  meow_cache_get mac_chip $MEOW_STATIC_TTL && CHIP="$REPLY"
fi
if [[ -z "${MODEL_NAME:-}" || -z "${CHIP:-}" ]]; then
  meow_mac_hardware
  MODEL_NAME="$MEOW_MAC_MODEL"
  CHIP="$MEOW_MAC_CHIP"
  [[ -n "$MODEL_NAME" ]] && meow_cache_set mac_model "$MODEL_NAME"
  [[ -n "$CHIP" ]] && meow_cache_set mac_chip "$CHIP"
fi
# Cached even when empty: a Mac that lists no chipset used to re-run
# system_profiler on every shell. Names are joined with "|", because the cache
# holds one record per line; the newline they were joined with before cut the
# second GPU of a dual-GPU MacBook Pro off every shell after the first.
if meow_cache_get mac_gpu_list $MEOW_STATIC_TTL; then
  [[ -n "$REPLY" ]] && MEOW_GPU_NAMES=("${(@s:|:)REPLY}")
elif meow_gpu_names; then
  meow_cache_set mac_gpu_list "${(j:|:)MEOW_GPU_NAMES}"
fi
[[ -n "$MODEL_NAME" ]] || MODEL_NAME="Mac"
[[ -n "$CHIP" ]] || CHIP="Unknown CPU"

meow_cpu_cores
CPU_CORES="$REPLY"
CPU_CORE_TEXT=""
if [[ "$CPU_CORES" == <-> ]] && (( CPU_CORES > 0 )); then
  meow_format_cores "$CPU_CORES" "$MEOW_CPU_UNIT"; CPU_CORE_TEXT="($REPLY)"
fi

meow_primary_ip; IP_ADDR="$REPLY"
meow_uptime;     UP_TIME="$REPLY"
meow_battery;    BATTERY="$REPLY"
meow_cpu_usage;  CPU_USAGE="$REPLY"

meow_memory
meow_memory_pressure; MEM_PRESSURE="$REPLY"
meow_swap
meow_disk

VM_USED=$MEOW_RAM_USED
VM_TOTAL=$MEOW_RAM_TOTAL
RAM_PERCENT=$MEOW_RAM_PERCENT
RAM_USED=$MEOW_RAM_USED
RAM_TOTAL=$MEOW_RAM_TOTAL
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

# Root is the effective uid, not $USER. su keeps the caller's USER when the
# target is root, as BSD su does, so an su to root used to get the ordinary cat
# and the caller's name.
if (( EUID == 0 )); then
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

if (( EUID == 0 )); then
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
fi
# The telnet check that stood here compared the shell's parent with "telnet",
# but under telnetd that parent is login, so it never fired; current macOS has
# no telnet server to begin with. All it did was start a ps on every shell.

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
if [[ -n "$CPU_USAGE" ]]; then
  meow_gauge "CPU Usage:" "$CPU_USAGE" "$CPU_CORE_TEXT"
else
  meow_row "CPU Usage:" "N/A${CPU_CORE_TEXT:+ $CPU_CORE_TEXT}"
fi
meow_gauge "RAM Usage:"       "$RAM_PERCENT"  "(${VM_USED}/${VM_TOTAL} MB)"
meow_gauge "Disk Usage:"      "$DISK_PERCENT" "(${DISK_USED}/${DISK_TOTAL} MB)"
meow_gauge "Memory Pressure:" "$MEM_PRESSURE"
if (( SWAP_TOTAL > 0 )); then
  meow_gauge "Swap Usage:" "$SWAP_PERCENT" "(${SWAP_USED}/${SWAP_TOTAL} MB)"
fi

if (( ${#MEOW_GPU_NAMES} == 1 )); then
  meow_row "GPU:" "${YELLOW}${MEOW_GPU_NAMES[1]}"
elif (( ${#MEOW_GPU_NAMES} > 1 )); then
  GPU_INDEX=0
  for util in "${MEOW_GPU_NAMES[@]}"; do
    meow_row "GPU${GPU_INDEX}:" "${YELLOW}${util}"
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
