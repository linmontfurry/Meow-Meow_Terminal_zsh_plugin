$ErrorActionPreference = 'SilentlyContinue'

$RESET = "$([char]27)[0m"
$PINK = "$([char]27)[1;35m"
$CYAN = "$([char]27)[38;5;51m"
$YELLOW = "$([char]27)[38;5;226m"
$MAGENTA = "$([char]27)[38;5;201m"
$GREEN = "$([char]27)[38;5;46m"
$ORANGE = "$([char]27)[38;5;208m"
$BLUE = "$([char]27)[1;34m"
$DIM = "$([char]27)[2m"
$LIGHT_GREEN = "$([char]27)[38;5;120m"
$RED = "$([char]27)[1;31m"

function Write-MeowLine {
    param([string]$Text = '')
    Write-Host $Text
}

# ---------------------------------------------------------------------------
# Cache
#
# A CIM query costs tens to hundreds of milliseconds and this banner made eight
# of them, several for facts that cannot change while the machine is running.
# They go in ONE fixed file that is rewritten in place, so ten thousand
# terminals leave one file behind rather than ten thousand. Each record carries
# its own timestamp so entries can expire on different schedules.
# ---------------------------------------------------------------------------

$MeowStaticTtl = if ($env:MEOW_STATIC_TTL) { [int]$env:MEOW_STATIC_TTL } else { 604800 }
$MeowSampleTtl = if ($env:MEOW_SAMPLE_TTL) { [int]$env:MEOW_SAMPLE_TTL } else { 10 }
$MeowNow = [int][double]::Parse(([datetimeoffset]::UtcNow.ToUnixTimeSeconds()).ToString())

$MeowCacheDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'meow-terminal' }
                elseif ($env:XDG_CACHE_HOME) { Join-Path $env:XDG_CACHE_HOME 'meow-terminal' }
                elseif ($env:HOME) { Join-Path $env:HOME '.cache/meow-terminal' }
                else { Join-Path ([System.IO.Path]::GetTempPath()) 'meow-terminal' }
$MeowCacheFile = Join-Path $MeowCacheDir 'facts'
$MeowCache = @{}
$MeowCacheDirty = $false
$MeowUsage = $null

function Read-MeowCache {
    if (-not (Test-Path -LiteralPath $script:MeowCacheFile)) { return }
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($script:MeowCacheFile)) {
            $parts = $line.Split(' ', 3)
            if ($parts.Count -lt 3) { continue }
            $stamp = 0
            if (-not [int]::TryParse($parts[0], [ref]$stamp)) { continue }
            $script:MeowCache[$parts[1]] = @{ Stamp = $stamp; Value = $parts[2] }
        }
    } catch {
    }
}

# A negative age never expires. Zero always misses, so setting
# MEOW_STATIC_TTL=0 or MEOW_SAMPLE_TTL=0 forces a fresh probe every shell.
function Get-MeowCache {
    param([string]$Key, [int]$MaxAge)

    $entry = $script:MeowCache[$Key]
    if (-not $entry) { return $null }
    if ($MaxAge -eq 0) { return $null }
    if ($MaxAge -gt 0 -and ($script:MeowNow - $entry.Stamp) -gt $MaxAge) { return $null }
    return $entry.Value
}

function Set-MeowCache {
    param([string]$Key, [string]$Value)

    $script:MeowCache[$Key] = @{ Stamp = $script:MeowNow; Value = $Value }
    $script:MeowCacheDirty = $true
}

function Save-MeowCache {
    if (-not $script:MeowCacheDirty) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:MeowCacheDir)) {
            New-Item -ItemType Directory -Force -Path $script:MeowCacheDir | Out-Null
        }
        $lines = foreach ($key in $script:MeowCache.Keys) {
            $e = $script:MeowCache[$key]
            '{0} {1} {2}' -f $e.Stamp, $key, ($e.Value -replace '[\r\n]', ' ')
        }
        [System.IO.File]::WriteAllLines($script:MeowCacheFile, [string[]]$lines)
    } catch {
    }
}

# Returns the cached value, or runs the block once and caches what it returns.
function Get-MeowCached {
    param([string]$Key, [int]$Ttl, [scriptblock]$Compute)

    $hit = Get-MeowCache -Key $Key -MaxAge $Ttl
    if ($null -ne $hit) { return $hit }
    $value = [string](& $Compute)
    # An empty answer means the probe failed. Leaving it uncached means the
    # caller falls back for this one run and we retry next shell, rather than
    # pinning "Unknown CPU" in place for a week.
    if ($value) { Set-MeowCache -Key $Key -Value $value }
    return $value
}

# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

function Get-Color {
    param([int]$Percent = 0)

    if ($Percent -ge 80) { return $RED }
    if ($Percent -ge 60) { return $ORANGE }
    if ($Percent -ge 30) { return $YELLOW }
    return $GREEN
}

function Draw-Bar {
    param([int]$Percent = 0)

    $width = 18
    if ($Percent -gt 100) { $Percent = 100 }
    if ($Percent -lt 0) { $Percent = 0 }
    $fill = [math]::Floor($Percent * $width / 100)
    return ('█' * $fill) + ('░' * ($width - $fill))
}

function Format-BytesToMB {
    param([double]$Bytes = 0)
    return [math]::Round($Bytes / 1MB)
}

function Format-CpuCoreCount {
    param([int]$Cores = 1)

    if ($Cores -lt 1) { $Cores = 1 }
    if ($Cores -eq 1) { return '1 core' }
    return "$Cores cores"
}

function Format-Uptime {
    param([datetime]$BootTime)

    if (-not $BootTime) { return 'N/A' }
    $span = (Get-Date) - $BootTime
    $parts = @()
    if ($span.Days -gt 0) { $parts += "$($span.Days)d" }
    if ($span.Hours -gt 0) { $parts += "$($span.Hours)h" }
    if ($span.Minutes -gt 0) { $parts += "$($span.Minutes)m" }
    if ($parts.Count -eq 0) { $parts += 'less than a minute' }
    return ($parts -join ' ')
}

function Color-Line {
    param([string]$Line, [int]$Index)

    $rainbowColors = @(31, 33, 32, 36, 34, 35)
    $color = $rainbowColors[$Index % $rainbowColors.Count]
    return "$([char]27)[$color" + "m$Line$([char]27)[0m"
}

# The gauge rows keep their bars in one column. Each label is padded to the
# longest one shown and the percentage is right-aligned to three places, so
# neither bars nor % signs step right with every longer label ("Swap Usage:"
# is one wider than "CPU Usage:"). Labels are plain ASCII, so a character count
# is a column count.
$gaugeRows = [System.Collections.Generic.List[object]]::new()

function Add-MeowRow {
    param([string]$Label, [string]$Value)
    $script:gaugeRows.Add([pscustomobject]@{ Label = $Label; Value = $Value })
}

function Add-MeowGauge {
    param([string]$Label, [int]$Percent, [string]$Detail = '')

    $value = "$(Get-Color $Percent)$(Draw-Bar $Percent) $(([string]$Percent).PadLeft(3))%"
    if ($Detail) { $value += " $Detail" }
    Add-MeowRow -Label $Label -Value $value
}

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# The address traffic actually leaves from. "Connecting" a UDP socket to a
# public address makes the OS pick a route without sending anything, and the
# socket's local end is that route's source address: the same rule the route
# lookups in the macOS and Linux banners follow. The old Get-NetIPAddress path
# sorted every address by interface metric and chose the Hyper-V switch on the
# CI runner (172.23.x.1) while fastfetch reported Ethernet 3 (10.1.0.x), and it
# loaded the NetTCPIP module plus a CIM query to do it.
#
# As on macOS, a tunnel that owns the default route (a VPN, or a TUN-mode proxy
# such as Clash) is looked past to the physical adapter underneath, if any.
function Get-PrimaryIPv4 {
    $ip = $null
    try {
        $socket = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        try {
            $socket.Connect('1.1.1.1', 53)
            $ip = $socket.LocalEndPoint.Address.ToString()
        } finally {
            $socket.Dispose()
        }
    } catch {
    }

    # Ppp, proprietary virtual (Wintun: WireGuard, Clash, ...), Tunnel
    $tunnelTypes = @(23, 53, 131)
    try {
        $nics = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' })
        $owner = $nics | Where-Object {
            @($_.GetIPProperties().UnicastAddresses | ForEach-Object { $_.Address.ToString() }) -contains $ip
        } | Select-Object -First 1

        if (-not $ip -or ($owner -and [int]$owner.NetworkInterfaceType -in $tunnelTypes)) {
            foreach ($nic in $nics) {
                if ([int]$nic.NetworkInterfaceType -in ($tunnelTypes + 24)) { continue }   # 24: loopback
                $props = $nic.GetIPProperties()
                $hasGateway = $props.GatewayAddresses | Where-Object {
                    $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.Address.ToString() -ne '0.0.0.0'
                }
                if (-not $hasGateway) { continue }
                $lan = $props.UnicastAddresses | Where-Object {
                    $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.Address.ToString() -notmatch '^(127\.|169\.254\.)'
                } | Select-Object -First 1
                if ($lan) { $ip = $lan.Address.ToString(); break }
            }
        }
    } catch {
    }

    if (-not $ip) { $ip = 'N/A' }
    return $ip
}

# Whether the machine has a battery at all cannot change, so a desktop stops
# paying for the Win32_Battery query after its first shell.
function Get-BatteryPercentage {
    $has = Get-MeowCached -Key 'has_battery' -Ttl $script:MeowStaticTtl -Compute {
        try {
            $b = @(Get-CimInstance Win32_Battery -Property EstimatedChargeRemaining -ErrorAction Stop)
            if ($b.Count -gt 0) { '1' } else { '0' }
        } catch {
            # Query failed rather than answered: return nothing so this is not
            # cached, and a laptop does not lose its battery line for a week.
            ''
        }
    }
    if ($has -eq '0') { return '' }

    try {
        $battery = Get-CimInstance Win32_Battery -Property EstimatedChargeRemaining | Select-Object -First 1
        if ($battery -and $null -ne $battery.EstimatedChargeRemaining) {
            return "$($battery.EstimatedChargeRemaining)%"
        }
    } catch {
    }
    return ''
}

# CPU and GPU utilisation are rates, so each needs two readings. Get-Counter
# takes both in one call, waiting about a second between its readings, and the
# answer is kept for MEOW_SAMPLE_TTL seconds. The WMI "formatted" CPU class used
# in between returned at once but reported 0% until WMI had a baseline of its
# own: on three CI runs, on a runner busy running this very script, it read 0,
# 26 and 0.
#
# Returned as "cpu|index:percent|...", the GPU part keyed by the physical
# adapter index (phys_N) that Task Manager groups engines by. Memoised for the
# run, so CPU and GPU share one sample even when it cannot be cached.
function Get-UsageSample {
    if ($null -ne $script:MeowUsage) { return $script:MeowUsage }
    $hit = Get-MeowCache -Key 'usage' -MaxAge $script:MeowSampleTtl
    if ($null -ne $hit) { $script:MeowUsage = $hit; return $hit }

    $cpuPath = '\Processor(_Total)\% Processor Time'
    $gpuPath = '\GPU Engine(*)\Utilization Percentage'
    $samples = $null
    if ((Get-MeowCache -Key 'has_gpu_counters' -MaxAge $script:MeowStaticTtl) -ne '0') {
        try {
            $samples = (Get-Counter -Counter $cpuPath, $gpuPath -ErrorAction Stop).CounterSamples
            Set-MeowCache -Key 'has_gpu_counters' -Value '1'
        } catch {
            # No GPU engine counters here (older Windows, some VMs). Remember
            # that, so later shells ask for the CPU alone straight away.
            Set-MeowCache -Key 'has_gpu_counters' -Value '0'
        }
    }
    if (-not $samples) {
        try { $samples = (Get-Counter -Counter $cpuPath -ErrorAction Stop).CounterSamples } catch { }
    }

    $cpu = ''
    $usageByGpu = @{}
    foreach ($sample in @($samples)) {
        if (-not $sample) { continue }
        if ($sample.Path -like '*\processor(_total)\*') {
            $cpu = [string][math]::Min(100, [math]::Max(0, [int][math]::Round($sample.CookedValue)))
            continue
        }
        if ($sample.CookedValue -lt 0 -or $sample.InstanceName -notmatch 'engtype_') { continue }
        # Match phys_ last: $matches holds the most recent successful -match.
        if ($sample.InstanceName -match 'phys_([0-9]+)') {
            $gpuIndex = [int]$matches[1]
            if (-not $usageByGpu.ContainsKey($gpuIndex)) { $usageByGpu[$gpuIndex] = 0.0 }
            $usageByGpu[$gpuIndex] += [double]$sample.CookedValue
        }
    }

    $parts = @($cpu)
    foreach ($gpuIndex in ($usageByGpu.Keys | Sort-Object)) {
        $parts += '{0}:{1}' -f $gpuIndex, [int][math]::Round([math]::Min([double]100, $usageByGpu[$gpuIndex]))
    }
    $script:MeowUsage = $parts -join '|'
    if ($cpu) { Set-MeowCache -Key 'usage' -Value $script:MeowUsage }
    return $script:MeowUsage
}

function Get-CpuUsage {
    $cpu = (Get-UsageSample).Split('|')[0]
    if ($cpu -match '^\d+$') { return [int]$cpu }
    return 0
}

# Takes the Win32_OperatingSystem instance the caller already fetched, instead
# of querying it a second time.
function Get-MemoryStats {
    param($OperatingSystem)

    try {
        $totalMB = [int][math]::Round([double]$OperatingSystem.TotalVisibleMemorySize / 1024)
        $freeMB = [int][math]::Round([double]$OperatingSystem.FreePhysicalMemory / 1024)
        $usedMB = [math]::Max(0, $totalMB - $freeMB)
        $percent = if ($totalMB -gt 0) { [int][math]::Round(($usedMB * 100) / $totalMB) } else { 0 }
        return [pscustomobject]@{ UsedMB = $usedMB; TotalMB = $totalMB; Percent = $percent }
    } catch {
        return [pscustomobject]@{ UsedMB = 0; TotalMB = 0; Percent = 0 }
    }
}

# The paging-file figures come with the Win32_OperatingSystem query this script
# already makes, so Win32_PageFileUsage, a CIM query of its own, is no longer
# needed. Both are reported in KB.
function Get-SwapStats {
    param($OperatingSystem)

    try {
        $totalMB = [int][math]::Round([double]$OperatingSystem.SizeStoredInPagingFiles / 1024)
        $freeMB = [int][math]::Round([double]$OperatingSystem.FreeSpaceInPagingFiles / 1024)
        if ($totalMB -le 0) {
            return [pscustomobject]@{ UsedMB = 0; TotalMB = 0; Percent = 0 }
        }
        $usedMB = [math]::Max(0, $totalMB - $freeMB)
        $percent = [int][math]::Round(($usedMB * 100) / $totalMB)
        return [pscustomobject]@{ UsedMB = $usedMB; TotalMB = $totalMB; Percent = $percent }
    } catch {
        return [pscustomobject]@{ UsedMB = 0; TotalMB = 0; Percent = 0 }
    }
}

# DriveInfo makes the same Win32 calls Win32_LogicalDisk wraps (GetDriveType,
# GetDiskFreeSpaceEx) without a WMI round-trip, so it is the cheaper way to ask.
# Fixed + ready matches the old DriveType = 3 filter: local disks only, no
# removable, optical or network drives.
function Get-DiskStats {
    $results = @()
    try {
        $drives = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } |
            Sort-Object Name
        foreach ($drive in $drives) {
            $sizeBytes = [double]$drive.TotalSize
            $freeBytes = [double]$drive.TotalFreeSpace
            # [double]0, not 0: with an Int32 first argument PowerShell binds
            # Max(Int32, Int32) for any runtime value, so a disk with more than
            # 2 GiB used threw here, the catch below swallowed it, and every disk
            # line silently disappeared. That has been the case since this line
            # was first written.
            $usedBytes = [math]::Max([double]0, $sizeBytes - $freeBytes)
            $totalMB = Format-BytesToMB $sizeBytes
            $usedMB = Format-BytesToMB $usedBytes
            $percent = if ($totalMB -gt 0) { [int][math]::Round(($usedMB * 100) / $totalMB) } else { 0 }
            # "C:\" -> "C:". A root such as "/" would trim to nothing, so keep it whole.
            $name = $drive.Name.TrimEnd('\', '/')
            if (-not $name) { $name = $drive.Name }
            $results += [pscustomobject]@{
                Name = $name; UsedMB = $usedMB; TotalMB = $totalMB; Percent = $percent
            }
        }
    } catch {
    }
    return $results
}

# Adapter names are fixed hardware, so they are cached. The utilisation counter
# is another ~1 s Get-Counter call, so it is refreshed only every
# MEOW_SAMPLE_TTL seconds rather than on every single shell.
function Get-GpuStats {
    $gpuStats = @()
    $nameMap = @{}

    $namesRaw = Get-MeowCached -Key 'gpu_names' -Ttl $script:MeowStaticTtl -Compute {
        $names = @()
        try {
            $controllers = Get-CimInstance Win32_VideoController -Property Name, AdapterRAM |
                Where-Object { $_.Name -and $_.AdapterRAM -gt 0 }
            foreach ($c in $controllers) { $names += $c.Name }
        } catch {
        }
        ($names -join '|')
    }

    $index = 0
    if ($namesRaw) {
        foreach ($name in $namesRaw.Split('|')) {
            if (-not $name) { continue }
            $nameMap[$index] = $name
            $gpuStats += [pscustomobject]@{ Index = $index; Name = $name; Usage = $null; Source = 'adapter' }
            $index++
        }
    }

    $usageRaw = (@((Get-UsageSample).Split('|')) | Select-Object -Skip 1) -join '|'

    if ($usageRaw) {
        foreach ($pair in $usageRaw.Split('|')) {
            if (-not $pair) { continue }
            $bits = $pair.Split(':')
            if ($bits.Count -ne 2) { continue }
            $gpuIndex = [int]$bits[0]
            $usage = [int]$bits[1]
            $existing = $gpuStats | Where-Object { $_.Index -eq $gpuIndex } | Select-Object -First 1
            if ($existing) {
                $existing.Usage = $usage
                $existing.Source = 'counter'
            } else {
                $name = if ($nameMap.ContainsKey($gpuIndex)) { $nameMap[$gpuIndex] } else { "GPU $gpuIndex" }
                $gpuStats += [pscustomobject]@{ Index = $gpuIndex; Name = $name; Usage = $usage; Source = 'counter' }
            }
        }
    }

    return $gpuStats | Sort-Object Index
}

# ---------------------------------------------------------------------------
# Gather
# ---------------------------------------------------------------------------

Read-MeowCache

# Windows' counterpart to root is an elevated process ("Run as administrator"),
# not an account that happens to be named Administrator. That built-in account
# is disabled by default on Windows 10 and 11, so the old name check almost
# never fired, and the elevated runneradmin on CI got the ordinary cat. Under
# UAC, an administrator's normal unelevated shell does not count, just as a
# sudoer is not root until they sudo.
$isAdmin = $false
try {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $isAdmin = ($env:USERNAME -eq 'Administrator')
}

$hostName = $env:COMPUTERNAME
if (-not $hostName) { $hostName = [System.Net.Dns]::GetHostName() }
$arch = $env:PROCESSOR_ARCHITECTURE
if (-not $arch) { $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }

# Model and CPU name are fixed hardware: two CIM queries that only ever ran to
# print the same two strings. Cached, they cost nothing after the first shell.
$modelName = Get-MeowCached -Key 'model' -Ttl $MeowStaticTtl -Compute {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -Property Model -ErrorAction Stop
        if ($cs.Model) { $cs.Model } else { '' }
    } catch { '' }
}
if (-not $modelName) { $modelName = 'Windows Machine' }

$chip = Get-MeowCached -Key 'chip' -Ttl $MeowStaticTtl -Compute {
    try {
        $p = Get-CimInstance Win32_Processor -Property Name -ErrorAction Stop |
                 Select-Object -ExpandProperty Name -First 1
        if ($p) { $p.Trim() } else { '' }
    } catch { '' }
}
# Win32_Processor pads the name with trailing blanks ("AMD EPYC 7763 64-Core
# Processor" plus sixteen spaces), which shoved "(AMD64)" far off to the right.
$chip = ([string]$chip).Trim()
if (-not $chip) { $chip = 'Unknown CPU' }

# .NET already knows this; Win32_ComputerSystem and Win32_Processor were being
# queried purely to count logical processors.
$cpuCores = [Environment]::ProcessorCount
if ($cpuCores -lt 1) { $cpuCores = 1 }
$cpuCoreText = Format-CpuCoreCount $cpuCores

# One query, reused for uptime, memory and the paging file.
$operatingSystem = Get-CimInstance Win32_OperatingSystem `
                       -Property LastBootUpTime, TotalVisibleMemorySize, FreePhysicalMemory,
                                 SizeStoredInPagingFiles, FreeSpaceInPagingFiles

$ipAddr = Get-PrimaryIPv4
$uptime = Format-Uptime $operatingSystem.LastBootUpTime
$battery = Get-BatteryPercentage
$cpuUsage = Get-CpuUsage
$memory = Get-MemoryStats -OperatingSystem $operatingSystem
$swap = Get-SwapStats -OperatingSystem $operatingSystem
$disks = @(Get-DiskStats)
$gpuStats = @(Get-GpuStats)

$welcomes = @(
    'Welcome back!',
    'Hello human!',
    'Kawaii typing detected!',
    'Cat says great!',
    'Have a purrfect day!',
    'Meow meow!',
    'You look comfy!',
    "Let's code!",
    'Paws activated!',
    'Cuteness overload!',
    'Enjoy your terminal!',
    'Feline power!',
    'Stay cozy!',
    'Time to hack!',
    'Cat inspected!',
    'All systems purrfect!',
    'Hello world, meow!',
    'Cat mode on!',
    'Stay pawsitive!',
    'Kitty approves your change!',
    'Make meow changes!',
    'Git commit approved by cat!',
    'Deploying cuteness...',
    'Terminal purrformance optimal!',
    'Cat detected hacker energy!',
    'Linting your code with paws...',
    'Compiling meowdule...',
    'Debugging with whiskers...',
    'Running pawcess...',
    'Cat watching your commits.',
    'Code review by kitty complete!',
    'System check: purrfect!',
    'Whiskers calibrated.',
    'Claws ready for coding!',
    'Keyboard warmed by paws.',
    'Terminal smells like productivity.',
    'Coffee detected. Coding likely.',
    'Cat supervising development.',
    'Boot sequence approved by cat.',
    'Purrmission granted!',
    'Terminal ready. Meow!',
    'Cat scanned the system.',
    'No bugs detected (cat hopes lol).',
    'Whiskers sense good code.',
    'Purrcess initialized.',
    'Shell opened successfully.',
    'Cat guarding the terminal.',
    'Keep coding, human.',
    'Terminal looks cozy today.',
    'Meowgic detected!',
    'Your code smells interesting.',
    'Another day, another commit.',
    'Cat recommends more snacks.',
    'Human detected at keyboard.',
    'Stay focused, stay pawsitive.',
    'Whisker-driven development.',
    'Code like a feline.',
    'System uptime approved.',
    'Cat believes in your code.',
    'Meow is a good time to code.',
    'Paws on keyboard!'
)

$welcome = Get-Random -InputObject $welcomes

Write-MeowLine ''
Write-MeowLine "${BLUE}Welcome to Meow-Meow Terminal!${RESET}"
Write-MeowLine "${CYAN}Cat says:${RESET} ${ORANGE}${welcome}${RESET}"
Write-MeowLine ''

if ($isAdmin) {
    $cat1 = @"
   /\_/\
  ( ⊙ʌ⊙ )
"@
    $cat2 = @"
    /\_/\
   ( ⊙ʌ⊙ )
"@
    $cat1Tail = ' ʔ/ づ づ'
    $cat2Tail = '   づ づ  \ʃ'
    $cat1Text = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
    $cat2Text = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
    # This caption is 23 columns wide, so its tab lands on column 24 while the
    # short face rows land on 16. Two tabs put the faces on 24 as well, keeping
    # the right-hand cat stacked over its own caption.
    $faceGap = "`t`t"
} else {
    $cat1 = @"
   /\_/\
  ( ≧ω≦ )
"@
    $cat2 = @"
    /\_/\
   ( OωO )
"@
    $cat1Tail = ' ʔ/ づ づ'
    $cat2Tail = '   づ づ  \ʃ'
    $cat1Text = "${PINK} Kimochiii!${RESET}"
    $cat2Text = "${BLUE}  Kawayiii!${RESET}"
    $faceGap = "`t"
}

$leftBlock = ($cat1.TrimEnd() -split "`r?`n") + $cat1Tail + $cat1Text
$rightBlock = ($cat2.TrimEnd() -split "`r?`n") + $cat2Tail + $cat2Text

# Tabs rather than spaces: a console that draws ambiguous-width characters such
# as ω and ⊙ double wide still lands every row on the same tab stop.
for ($i = 0; $i -lt [math]::Max($leftBlock.Count, $rightBlock.Count); $i++) {
    $left = if ($i -lt $leftBlock.Count) { $leftBlock[$i] } else { '' }
    $right = if ($i -lt $rightBlock.Count) { $rightBlock[$i] } else { '' }
    $gap = if ($i -eq $leftBlock.Count - 1) { "`t" } else { $faceGap }
    Write-Host ("{0}{1}{2}" -f $left, $gap, $right)
}

Write-MeowLine ''

if ($isAdmin) {
    $userName = "${RED}powerful master${RESET}"
    Write-MeowLine "${CYAN}Cat whispers: your username is ${userName}${CYAN}... oh no!${RESET}"
    Write-MeowLine "${RED}Cat is scared!${RESET}"
    Write-MeowLine "${YELLOW}Please do not delete the system, ${RED}powerful master${YELLOW}...${RESET}"
    Write-MeowLine "${YELLOW}Be gentle with the machine. That is more fun!${RESET}"
    Write-MeowLine "${CYAN}Cat hides behind the keyboard... ${RED}please do not delete meow.${RESET}"
} else {
    $userName = "${YELLOW}$($env:USERNAME)${RESET}"
    Write-MeowLine "${CYAN}Cat whispers: your username is ${userName}${CYAN}, noted!${RESET}"
}

$connectionType = $null
$loginIP = $null

if ($env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
    $connectionType = "SSH"
    $sshInfo = if ($env:SSH_CONNECTION) { $env:SSH_CONNECTION } else { $env:SSH_CLIENT }
    $loginIP = ($sshInfo -split '\s+')[0]
} elseif ($env:TERM -match 'screen|tmux' -and (Get-Process -Id $PID).Parent.ProcessName -match 'telnet|rlogin') {
    $connectionType = "telnet"
    try {
        $netstat = netstat -an | Select-String "ESTABLISHED" | Select-String ":23\s"
        if ($netstat) {
            $loginIP = ($netstat -split '\s+')[2] -replace ':.*$', ''
        }
    } catch {
    }
}

if ($connectionType) {
    if ($loginIP) {
        Write-MeowLine "${CYAN}Cat noticed: you connected via ${MAGENTA}${connectionType}${CYAN} from ${YELLOW}${loginIP}${CYAN}, is this you?${RESET}"
    } else {
        Write-MeowLine "${CYAN}Cat noticed: you connected via ${MAGENTA}${connectionType}${CYAN} from ${YELLOW}somewhere mysterious${CYAN}...${RESET}"
    }
} else {
    # A Win32_LogonSession lookup used to sit here, filtered on LogonId = this
    # process's SessionId. Those are different numbering schemes (a logon LUID
    # against a terminal-session index), so it never matched: every shell paid
    # for a CIM query and printed "Console" regardless.
    $ttyInfo = "Console"
    Write-MeowLine "${CYAN}Cat noticed: you're on local terminal ${YELLOW}${ttyInfo}${RESET}"
}

Write-MeowLine "${CYAN}Cat sniffed the machine: hostname ${YELLOW}${hostName}${RESET}"
Write-MeowLine "${CYAN}Cat checked your primary IP: ${YELLOW}${ipAddr}${RESET}"
Write-MeowLine "${CYAN}Cat checked the uptime: ${YELLOW}${uptime}${RESET}"

if ($battery) {
    $batVal = [int]($battery.TrimEnd('%'))

    if ($batVal -lt 20) {
        $batColor = $RED
        $batText = 'Battery is low. Time to plug in soon.'
    } elseif ($batVal -lt 50) {
        $batColor = $ORANGE
        $batText = 'Battery is halfway there. Still okay for now.'
    } else {
        $batColor = $GREEN
        $batText = 'Battery looks healthy. Have a nice meowing day!'
    }

    Write-MeowLine "${CYAN}Battery level: ${batColor}${battery}${CYAN}, ${batText}${RESET}"
}

Write-MeowLine ''

$catArt1 = @(
"       I'm hungry!  ",
"              ノ    ",
"   ／l、 _․         ",
"  /  l._/. フ       ",
" ( ﾟ⩊ ｡  . ).       ",
"  l     ~ヽ         ",
"   l      -.\   /)  ",
"   じしf_  , .)ノ/  ",
"                    ",
"                    "
)

$catArt2 = @(
"       touch me!    ",
"              ノ    ",
"   ／l、 _․         ",
"  /  l._/. フ       ",
" (.˃ ᵕ ˂. ).        ",
"  l     ~ヽ         ",
"   l      -.\   /)  ",
"   じしf_  , .)ノ/  ",
"                    ",
"                    "
)

$allCatArts = @($catArt1, $catArt2)
$rawArt = Get-Random -InputObject $allCatArts

$deviceArt = @()
for ($i = 0; $i -lt $rawArt.Count; $i++) {
    $deviceArt += (Color-Line -Line $rawArt[$i] -Index $i)
}

$infoLines = @()
$infoLines += "${BLUE}${modelName}${RESET}"
$infoLines += "${DIM}CPU:${RESET} ${YELLOW}${chip}${RESET} ${DIM}(${arch})${RESET}"
$infoLines += "${DIM}User:${RESET} ${LIGHT_GREEN}$($env:USERNAME)${RESET}@${LIGHT_GREEN}${hostName}${RESET}"
$infoLines += "${DIM}========================================${RESET}"
Add-MeowGauge -Label 'CPU Usage:' -Percent $cpuUsage -Detail "(${cpuCoreText})"
Add-MeowGauge -Label 'RAM Usage:' -Percent $memory.Percent -Detail "($($memory.UsedMB)/$($memory.TotalMB) MB)"

if ($swap.TotalMB -gt 0) {
    Add-MeowGauge -Label 'Swap Usage:' -Percent $swap.Percent -Detail "($($swap.UsedMB)/$($swap.TotalMB) MB)"
}

if ($gpuStats.Count -eq 1) {
    $gpu = $gpuStats[0]
    if ($null -ne $gpu.Usage) {
        Add-MeowGauge -Label 'GPU Usage:' -Percent $gpu.Usage
    }
} elseif ($gpuStats.Count -gt 1) {
    foreach ($gpu in $gpuStats) {
        if ($null -ne $gpu.Usage) {
            Add-MeowGauge -Label "GPU$($gpu.Index):" -Percent $gpu.Usage
        } else {
            Add-MeowRow -Label "GPU$($gpu.Index):" -Value "${YELLOW}$($gpu.Name)"
        }
    }
}

foreach ($disk in $disks) {
    # DeviceID already carries its colon ("C:"); appending another printed "Disk C::".
    Add-MeowGauge -Label "Disk $($disk.Name.TrimEnd(':')):" -Percent $disk.Percent -Detail "($($disk.UsedMB)/$($disk.TotalMB) MB)"
}

$labelWidth = 0
foreach ($row in $gaugeRows) {
    if ($row.Label.Length -gt $labelWidth) { $labelWidth = $row.Label.Length }
}
foreach ($row in $gaugeRows) {
    $infoLines += "${CYAN}$($row.Label.PadRight($labelWidth)) $($row.Value)${RESET}"
}

# Get-DisplayWidth used to measure every line character by character, then pad
# by "targetWidth - width" with targetWidth fixed at 1. That is never positive,
# so the padding was always clamped to zero and the measurement thrown away.
#
# More info rows than art rows (a couple of disks plus two GPUs) used to vanish,
# because the loop only walked the ten art rows. The art column is now padded
# out with blanks instead, the way fastfetch pads its logo.
$artPad = ' ' * 20
$rowCount = [math]::Max($deviceArt.Count, $infoLines.Count)
for ($i = 0; $i -lt $rowCount; $i++) {
    $left = if ($i -lt $deviceArt.Count) { $deviceArt[$i] } else { $artPad }
    $right = if ($i -lt $infoLines.Count) { $infoLines[$i] } else { '' }
    Write-Host ("{0} {1}" -f $left, $right)
}

Write-MeowLine ''
Write-MeowLine "${DIM}============================================================${RESET}"
Write-MeowLine ''

Save-MeowCache

if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch
} else {
    Write-MeowLine "${MAGENTA}fastfetch not installed${RESET}"
}
