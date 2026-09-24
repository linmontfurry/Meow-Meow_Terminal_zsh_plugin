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
# Int64: an Int32 of epoch seconds runs out in January 2038, and every cache
# entry would then fail to parse and be probed afresh on every shell.
$MeowNow = [datetimeoffset]::UtcNow.ToUnixTimeSeconds()

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
            $stamp = [int64]0
            if (-not [int64]::TryParse($parts[0], [ref]$stamp)) { continue }
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

# Hardware only changes across a power cycle, so everything cached belongs to
# the boot it was measured in. A new boot starts from an empty cache: a swapped
# CPU or GPU shows up in the first shell after the machine comes back, instead
# of up to MEOW_STATIC_TTL later. Boot times under a minute apart are the same
# boot, since Windows moves the boot time when the clock is stepped.
#
# With Fast Startup on, "Shut down" hibernates the running boot instead of
# ending it, and only a restart or a full shutdown moves the boot time. The GPU
# list keeps itself current regardless (see Get-GpuStats), and the CPU name is
# what Windows recorded at boot, so it agrees with Windows either way.
function Set-MeowCacheBoot {
    param($BootTime)

    try { $boot = ([datetimeoffset]$BootTime).ToUnixTimeSeconds() } catch { return }
    $stored = [int64]0
    $hit = Get-MeowCache -Key 'boot' -MaxAge -1
    if ($null -ne $hit -and [int64]::TryParse($hit, [ref]$stored) -and [math]::Abs($stored - $boot) -lt 60) { return }
    $script:MeowCache.Clear()
    Set-MeowCache -Key 'boot' -Value ([string]$boot)
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

# "1 core", "8 cores", "16 threads"
function Format-CpuCoreCount {
    param([int]$Count, [string]$Unit = 'cores')

    if ($Count -eq 1) { $Unit = $Unit.TrimEnd('s') }
    return "$Count $Unit"
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
# The CPU figure is % Processor Utility, the counter Task Manager has shown since
# Windows 8 (KB 3200459). It measures work done against the CPU's nominal
# clock, so a core busy all the time at half speed reads 50% where % Processor
# Time, used before, read 100%. Turbo can take it past 100%; the gauge stops at
# 100. Should the counter be missing, % Processor Time is the fallback.
#
# A GPU's figure is its busiest engine, each engine being the sum over the
# processes using it: how Task Manager computes it. Every engine used to be
# added together, a video decode on top of the 3D work beside it and the copy
# engine on top of both, which overstated the load and could pass 100%.
#
# Engines are grouped by adapter LUID. The phys_N they were grouped by before
# numbers the chips inside one linked adapter, so it is 0 on every ordinary
# GPU: a laptop's integrated and discrete GPUs were added up and shown as the
# first one.
#
# Returned as "cpu|luid:percent|...". Memoised for the run, so CPU and GPU
# share one sample even when it cannot be cached.
function Get-UsageSample {
    if ($null -ne $script:MeowUsage) { return $script:MeowUsage }
    $hit = Get-MeowCache -Key 'usage' -MaxAge $script:MeowSampleTtl
    if ($null -ne $hit) { $script:MeowUsage = $hit; return $hit }

    $cpuPaths = '\Processor Information(_Total)\% Processor Utility', '\Processor(_Total)\% Processor Time'
    $gpuPath = '\GPU Engine(*)\Utilization Percentage'
    $wantGpu = (Get-MeowCache -Key 'has_gpu_counters' -MaxAge $script:MeowStaticTtl) -ne '0'
    $samples = $null
    # A missing counter fails at once, before any waiting, so trying the next
    # one costs nothing. Only the call that succeeds spends the second.
    foreach ($cpuPath in $cpuPaths) {
        if ($wantGpu) {
            try {
                $samples = (Get-Counter -Counter $cpuPath, $gpuPath -ErrorAction Stop).CounterSamples
                Set-MeowCache -Key 'has_gpu_counters' -Value '1'
                break
            } catch {
            }
        }
        try {
            $samples = (Get-Counter -Counter $cpuPath -ErrorAction Stop).CounterSamples
        } catch {
            continue
        }
        # The CPU counter works on its own, so the GPU engine counters are what
        # is missing (older Windows, some VMs). Remember that, so later shells
        # ask for the CPU alone straight away.
        if ($wantGpu) { Set-MeowCache -Key 'has_gpu_counters' -Value '0' }
        break
    }

    $cpu = ''
    $engineLoad = @{}
    foreach ($sample in @($samples)) {
        if (-not $sample) { continue }
        if ($sample.Path -like '*\processor*(_total)\*') {
            $cpu = [string][math]::Min(100, [math]::Max(0, [int][math]::Round($sample.CookedValue)))
            continue
        }
        # pid_1234_luid_0x00000000_0x0000d1b5_phys_0_eng_3_engtype_videodecode
        if ($sample.CookedValue -lt 0 -or
            $sample.InstanceName -notmatch 'luid_0x([0-9a-f]+)_0x([0-9a-f]+)_phys_([0-9]+)_eng_([0-9]+)') { continue }
        $luid = '{0:x8}{1:x8}' -f [Convert]::ToUInt32($matches[1], 16), [Convert]::ToUInt32($matches[2], 16)
        $engineLoad["$luid/$($matches[3])/$($matches[4])"] += [double]$sample.CookedValue
    }

    $gpuLoad = @{}
    foreach ($engine in $engineLoad.Keys) {
        $luid = $engine.Split('/')[0]
        if (-not $gpuLoad.ContainsKey($luid) -or $engineLoad[$engine] -gt $gpuLoad[$luid]) {
            $gpuLoad[$luid] = $engineLoad[$engine]
        }
    }

    $parts = @($cpu)
    foreach ($luid in ($gpuLoad.Keys | Sort-Object)) {
        $parts += '{0}:{1}' -f $luid, [int][math]::Round([math]::Min([double]100, $gpuLoad[$luid]))
    }
    $script:MeowUsage = $parts -join '|'
    if ($cpu) { Set-MeowCache -Key 'usage' -Value $script:MeowUsage }
    return $script:MeowUsage
}

# $null when no counter could be read, so the banner says N/A instead of a
# made-up 0%.
function Get-CpuUsage {
    $cpu = (Get-UsageSample).Split('|')[0]
    if ($cpu -match '^\d+$') { return [int]$cpu }
    return $null
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

# The display adapters in Win32_VideoController order, as "luid=name|...". The
# LUID is the adapter id the GPU Engine counters are keyed by, read from the
# device property {60b193cb-5276-4d0f-96fc-f173abad3ec6} 2 as fastfetch does.
# Windows assigns it when the driver starts, so it holds for one boot at most.
#
# Adapters the AdapterRAM filter hides (remote desktop, virtual displays) stay
# in the list as "luid=", without a name: they get no row, but their LUIDs
# still tell display adapters apart from the Basic Render Driver, which draws
# in software on the CPU and has counters of its own without being a GPU.
#
# An empty list is an answer (a VM may have no GPU worth showing) and is cached
# like any other; $null means the query failed, and is not.
function Get-MeowGpuList {
    $luidOf = @{}
    try {
        $devices = @(Get-CimInstance Win32_PnPEntity -Property DeviceID -ErrorAction Stop `
                         -Filter "ClassGuid = '{4d36e968-e325-11ce-bfc1-08002be10318}'")
        foreach ($device in $devices) {
            try {
                $reply = Invoke-CimMethod -InputObject $device -MethodName GetDeviceProperties -ErrorAction Stop `
                             -Arguments @{ devicePropertyKeys = [string[]]@('{60b193cb-5276-4d0f-96fc-f173abad3ec6} 2') }
                $data = @($reply.deviceProperties)[0].Data
                if ($null -ne $data) { $luidOf[[string]$device.DeviceID] = '{0:x16}' -f [uint64]$data }
            } catch {
            }
        }
    } catch {
    }

    $entries = @()
    try {
        $controllers = Get-CimInstance Win32_VideoController -Property Name, AdapterRAM, PNPDeviceID -ErrorAction Stop
    } catch {
        return $null
    }
    foreach ($c in @($controllers)) {
        if (-not $c) { continue }
        $name = if ($c.Name -and $c.AdapterRAM -gt 0) { ([string]$c.Name).Trim() } else { '' }
        $luid = [string]$luidOf[[string]$c.PNPDeviceID]
        if ($name -or $luid) { $entries += '{0}={1}' -f $luid, $name }
    }
    return ($entries -join '|')
}

# The list is cached with the other hardware facts, and so rebuilt every boot.
# One more check keeps it honest within a boot: a LUID in the counters that it
# has never seen means an adapter started after it was made, such as a GPU
# swapped in under Fast Startup (whose shut down does not end the boot) or a
# reinstalled driver. It is rebuilt then, so a card that is gone does not stay
# on screen.
function Get-GpuStats {
    $load = @{}
    foreach ($pair in @((Get-UsageSample).Split('|') | Select-Object -Skip 1)) {
        $bits = $pair.Split(':')
        if ($bits.Count -eq 2 -and $bits[1] -match '^[0-9]+$') { $load[$bits[0]] = [int]$bits[1] }
    }

    $list = Get-MeowCache -Key 'gpus' -MaxAge $script:MeowStaticTtl
    $seen = @([string](Get-MeowCache -Key 'gpu_luids' -MaxAge -1) -split ',' | Where-Object { $_ })
    $known = $seen + @(([string]$list -split '\|') | ForEach-Object { $_.Split('=')[0] } | Where-Object { $_ })
    $fresh = @($load.Keys | Where-Object { $known -notcontains $_ })
    if ($null -eq $list -or $fresh.Count -gt 0) {
        $list = Get-MeowGpuList
        if ($null -ne $list) { Set-MeowCache -Key 'gpus' -Value $list }
        Set-MeowCache -Key 'gpu_luids' -Value ((@($seen) + $fresh | Select-Object -Unique) -join ',')
    }

    $gpuStats = @()
    $mapped = $false
    foreach ($entry in @(([string]$list -split '\|') | Where-Object { $_ })) {
        $luid, $name = $entry.Split('=', 2)
        if ($luid) { $mapped = $true }
        if (-not $name) { continue }
        $usage = if ($luid -and $load.ContainsKey($luid)) { $load[$luid] } else { $null }
        $gpuStats += [pscustomobject]@{ Index = $gpuStats.Count; Name = $name; Usage = $usage }
    }

    # With no LUID to go by, a reading can only be placed when there is just
    # one GPU it could belong to.
    if (-not $mapped -and $load.Count -gt 0 -and $gpuStats.Count -le 1) {
        $busiest = [int]($load.Values | Measure-Object -Maximum).Maximum
        if ($gpuStats.Count -eq 0) {
            $gpuStats += [pscustomobject]@{ Index = 0; Name = 'GPU 0'; Usage = $busiest }
        } else {
            $gpuStats[0].Usage = $busiest
        }
    }

    return $gpuStats
}

# ---------------------------------------------------------------------------
# Gather
# ---------------------------------------------------------------------------

Read-MeowCache

# One query, reused for uptime, memory and the paging file, and first of all to
# tell whether the cache is from this boot.
$operatingSystem = Get-CimInstance Win32_OperatingSystem `
                       -Property LastBootUpTime, TotalVisibleMemorySize, FreePhysicalMemory,
                                 SizeStoredInPagingFiles, FreeSpaceInPagingFiles
Set-MeowCacheBoot $operatingSystem.LastBootUpTime

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

# The CPU name and its physical core count come from one Win32_Processor query,
# cached with the other hardware facts. NumberOfCores is per socket, so the
# sockets are added up. [Environment]::ProcessorCount, shown before, counts
# hardware threads: twice the cores on a CPU with SMT.
$chip = Get-MeowCache -Key 'chip' -MaxAge $MeowStaticTtl
$physicalCores = Get-MeowCache -Key 'cores' -MaxAge $MeowStaticTtl
if ($null -eq $chip -or $null -eq $physicalCores) {
    try {
        $processors = @(Get-CimInstance Win32_Processor -Property Name, NumberOfCores -ErrorAction Stop)
        # Win32_Processor pads the name with trailing blanks ("AMD EPYC 7763 64-Core
        # Processor" plus sixteen spaces), which shoved "(AMD64)" far off to the right.
        $name = ([string]$processors[0].Name).Trim()
        $cores = [int]($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        if ($name) { $chip = $name; Set-MeowCache -Key 'chip' -Value $name }
        if ($cores -gt 0) { $physicalCores = [string]$cores; Set-MeowCache -Key 'cores' -Value $physicalCores }
    } catch {
    }
}
$chip = ([string]$chip).Trim()
if (-not $chip) { $chip = 'Unknown CPU' }

$cpuCoreText = ''
if ([string]$physicalCores -match '^[0-9]+$' -and [int]$physicalCores -gt 0) {
    $cpuCoreText = '({0})' -f (Format-CpuCoreCount ([int]$physicalCores) 'cores')
} elseif ([Environment]::ProcessorCount -gt 0) {
    $cpuCoreText = '({0})' -f (Format-CpuCoreCount ([Environment]::ProcessorCount) 'threads')
}

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
}
# A telnet check used to follow. It needed pwsh's parent process to be named
# telnet or rlogin, and TERM to name screen or tmux as well, while the Windows
# versions PowerShell 7 runs on ship no Telnet server: it had nothing to find.

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
if ($null -ne $cpuUsage) {
    Add-MeowGauge -Label 'CPU Usage:' -Percent $cpuUsage -Detail $cpuCoreText
} else {
    Add-MeowRow -Label 'CPU Usage:' -Value ("N/A $cpuCoreText").TrimEnd()
}
Add-MeowGauge -Label 'RAM Usage:' -Percent $memory.Percent -Detail "($($memory.UsedMB)/$($memory.TotalMB) MB)"

if ($swap.TotalMB -gt 0) {
    Add-MeowGauge -Label 'Swap Usage:' -Percent $swap.Percent -Detail "($($swap.UsedMB)/$($swap.TotalMB) MB)"
}

# A GPU without a reading still gets its name, as on macOS.
if ($gpuStats.Count -eq 1) {
    $gpu = $gpuStats[0]
    if ($null -ne $gpu.Usage) {
        Add-MeowGauge -Label 'GPU Usage:' -Percent $gpu.Usage
    } else {
        Add-MeowRow -Label 'GPU:' -Value "${YELLOW}$($gpu.Name)"
    }
} elseif ($gpuStats.Count -gt 1) {
    foreach ($gpu in $gpuStats) {
        if ($null -ne $gpu.Usage) {
            # With more than one GPU a bare number does not say which card it is.
            Add-MeowGauge -Label "GPU$($gpu.Index):" -Percent $gpu.Usage -Detail "($($gpu.Name))"
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
