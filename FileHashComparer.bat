<# :batBegin
@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
set CMDARGS=%*
set "CURDIR=%CD%"
set "BATFILE=%~f0"
powershell -NoProfile -Command "& ([scriptblock]::Create([System.IO.File]::ReadAllText($env:BATFILE, [System.Text.Encoding]::UTF8)))"
exit /b %ERRORLEVEL%
:batEnd #>

if (-not ([System.Management.Automation.PSTypeName]"NTDLL.Win32Crc32").Type) {
	Add-Type -TypeDefinition 'namespace NTDLL {
		public class Win32Crc32 {
			[System.Runtime.InteropServices.DllImport("ntdll.dll", CallingConvention = System.Runtime.InteropServices.CallingConvention.StdCall)]
			public static extern uint RtlComputeCrc32(uint dwInitial, byte[] pData, int iLen);
		}
	}'
}

enum CompKey {
	Name
	Extension
	DirectoryName
	Size
	LastWriteTime
}

enum LogMode {
	All
	Matches
	Mismatches
}

enum MaskMode {
	SourceInclude
	SourceExclude
	TargetInclude
	TargetExclude
}

enum TimeMode {
	SourceTime
	TargetTime
}

enum TimeUnit {
	Minutes
	Hours
	Days
	Months
	Years
}

$script:opt = [PSCustomObject]@{
	ShowMenu = $true
	Name = $false
	Extension = $false
	DirectoryName = $false
	Size = $true
	LastWriteTime = $false
	SourceInclude = @()
	SourceExclude = @()
	SourceTimeUnit = $null
	SourceTime = 0
	TargetInclude = @()
	TargetExclude = @()
	TargetTimeUnit = $null
	TargetTime = 0
	LogMode = [LogMode]::All
	Verbose = $true
	Algorithm = 'CRC32'
	Save = $false
	SaveMsg = $true
	Log = $false
	LogMsg = $true
	Quiet = $false
	Batch = $false
}

function Show-Menu {
	$restart = $true
	while ($restart) {
		Invoke-ClearHost
		Write-Host '╔════════════════════╗'
		Write-Host '║ File Hash Comparer ║'
		Write-Host '╚════════════════════╝'
		Write-Host ''
		if ($script:hasTargetSet) {
			if ($script:source.Count -eq 1) {
				Write-Host ('Source path: ' + (Remove-LongPrefix $script:source[0]))
			} else {
				Write-Host ('Source paths: ' + $script:source.Count)
			}
			if ($script:target.Count -eq 1) {
				Write-Host ('Target path: ' + (Remove-LongPrefix $script:target[0]))
			} else {
				Write-Host ('Target paths: ' + $script:target.Count)
			}
		} else {
			if ($script:source.Count -eq 1) {
				Write-Host ('Path: ' + (Remove-LongPrefix $script:source[0]))
			} else {
				Write-Host ('Paths: ' + $script:source.Count)
			}
		}
		Write-Host ''
		Write-Host '1.  [Start comparison]' -ForegroundColor Green
		Write-Host ''
		if ($script:opt.Name) {
			Write-Host '2.  File name match: Yes'
		} else {
			Write-Host '2.  File name match: No' -ForegroundColor DarkGray
		}
		if ($script:opt.Extension) {
			Write-Host '3.  File extension match: Yes'
		} else {
			Write-Host '3.  File extension match: No' -ForegroundColor DarkGray
		}
		if ($script:opt.DirectoryName) {
			Write-Host '4.  Directory name match: Yes'
		} else {
			Write-Host '4.  Directory name match: No' -ForegroundColor DarkGray
		}
		if ($script:opt.Size) {
			Write-Host '5.  File size match: Yes'
		} else {
			Write-Host '5.  File size match: No' -ForegroundColor DarkGray
		}
		if ($script:opt.LastWriteTime) {
			Write-Host '6.  Last write time match: Yes'
		} else {
			Write-Host '6.  Last write time match: No' -ForegroundColor DarkGray
		}
		Write-Host ''
		Write-Host '7.  Filter modes'
		Write-Host ''
		Write-Host ('8.  Algorithm: ' + $script:opt.Algorithm)
		Write-Host '9.  Log mode: ' -NoNewline
		if ($script:opt.LogMode -eq [LogMode]::Mismatches) {
			Write-Host 'Mismatches' -ForegroundColor Red
		} elseif ($script:opt.LogMode -eq [LogMode]::Matches) {
			Write-Host 'Matches' -ForegroundColor Green
		} else {
			Write-Host 'All' -ForegroundColor Yellow
		}
		if ($script:opt.Verbose) {
			Write-Host '10. Verbose logging: Yes'
		} else {
			Write-Host '10. Verbose logging: No' -ForegroundColor DarkGray
		}
		Write-Host ''
		Write-Host '11. View paths'
		Write-Host ''
		Write-Host '0.  Exit'
		Write-Host ''
		$read = Read-Host 'Select option (0-11)'
		switch ($read.Trim()) {
			'' {
				$restart = $false
				break
			}
			'1' {
				$restart = $false
				break
			}
			'2' {
				$script:opt.Name = -not $script:opt.Name
				break
			}
			'3' {
				$script:opt.Extension = -not $script:opt.Extension
				break
			}
			'4' {
				$script:opt.DirectoryName = -not $script:opt.DirectoryName
				break
			}
			'5' {
				$script:opt.Size = -not $script:opt.Size
				break
			}
			'6' {
				$script:opt.LastWriteTime = -not $script:opt.LastWriteTime
				break
			}
			'7' {
				Show-Filters
				break
			}
			'8' {
				Show-SetAlgorithm
				break
			}
			'9' {
				if ($script:opt.LogMode -eq [LogMode]::All) {
					$script:opt.LogMode = [LogMode]::Mismatches
				} elseif ($script:opt.LogMode -eq [LogMode]::Mismatches) {
					$script:opt.LogMode = [LogMode]::Matches
				} else {
					$script:opt.LogMode = [LogMode]::All
				}
				break
			}
			'10' {
				$script:opt.Verbose = -not $script:opt.Verbose
				break
			}
			'11' {
				Show-Paths
				break
			}
			'0' {
				exit 0
			}
		}
	}
}

function Show-Filters {
	$restart = $true
	while ($restart) {
		Invoke-ClearHost
		Write-Host '╔════════════════════╗'
		Write-Host '║ File Hash Comparer ║'
		Write-Host '╚════════════════════╝'
		Write-Host ''
		if ($script:hasTargetSet) {
			Write-Host 'Source file filters'
			Write-Host ''
		}
		if ($script:opt.SourceInclude) {
			Write-Host ('1. Include file mask: ' + ($script:opt.SourceInclude -join '|'))
		} else {
			Write-Host '1. Include file mask: None' -ForegroundColor DarkGray
		}
		if ($script:opt.SourceExclude) {
			Write-Host ('2. Exclude file mask: ' + ($script:opt.SourceExclude -join '|'))
		} else {
			Write-Host '2. Exclude file mask: None' -ForegroundColor DarkGray
		}
		if ($script:opt.SourceTime -gt 0) {
			Write-Host ('3. File modification time (' + (Get-TimeUnit $script:opt.SourceTimeUnit) + '): ' + $script:opt.SourceTime)
		} else {
			Write-Host '3. File modification time: None' -ForegroundColor DarkGray
		}
		if ($script:hasTargetSet) {
			Write-Host ''
			Write-Host 'Target file filters'
			Write-Host ''
			if ($script:opt.TargetInclude) {
				Write-Host ('4. Include file mask: ' + ($script:opt.TargetInclude -join '|'))
			} else {
				Write-Host '4. Include file mask: None' -ForegroundColor DarkGray
			}
			if ($script:opt.TargetExclude) {
				Write-Host ('5. Exclude file mask: ' + ($script:opt.TargetExclude -join '|'))
			} else {
				Write-Host '5. Exclude file mask: None' -ForegroundColor DarkGray
			}
			if ($script:opt.TargetTime -gt 0) {
				Write-Host ('6. File modification time (' + (Get-TimeUnit $script:opt.TargetTimeUnit) + '): ' + $script:opt.TargetTime)
			} else {
				Write-Host '6. File modification time: None' -ForegroundColor DarkGray
			}
		}
		Write-Host ''
		Write-Host '0. [Back to menu]' -ForegroundColor Green
		Write-Host ''
		if ($script:hasTargetSet) {
			$read = Read-Host 'Select option (0-6)'
		} else {
			$read = Read-Host 'Select option (0-3)'
		}
		switch ($read.Trim()) {
			'' {
				$restart = $false
				break
			}
			'1' {
				Show-NewMask ([MaskMode]::SourceInclude)
				break
			}
			'2' {
				Show-NewMask ([MaskMode]::SourceExclude)
				break
			}
			'3' {
				Show-NewTime ([TimeMode]::SourceTime)
				break
			}
			'4' {
				if ($script:hasTargetSet) { Show-NewMask ([MaskMode]::TargetInclude) }
				break
			}
			'5' {
				if ($script:hasTargetSet) { Show-NewMask ([MaskMode]::TargetExclude) }
				break
			}
			'6' {
				if ($script:hasTargetSet) { Show-NewTime ([TimeMode]::TargetTime) }
				break
			}
			'0' {
				$restart = $false
				break
			}
		}
	}
}

function Show-NewMask {
	param(
		[MaskMode]$Mode
	)
	try {
		Write-Host ''
		$masks = @(Get-FileMask (Read-Host 'File mask') -ErrSkip)
	} catch {
		$masks = @()
	}
	switch ($Mode) {
		([MaskMode]::SourceInclude) {
			$script:opt.SourceInclude = $masks
			break
		}
		([MaskMode]::SourceExclude) {
			$script:opt.SourceExclude = $masks
			break
		}
		([MaskMode]::TargetInclude) {
			$script:opt.TargetInclude = $masks
			break
		}
		([MaskMode]::TargetExclude) {
			$script:opt.TargetExclude = $masks
			break
		}
	}
}

function Show-NewTime {
	param(
		[TimeMode]$Mode
	)
	$unit = $null
	$time = 0
	try {
		Invoke-ClearHost
		Write-Host '╔════════════════════╗'
		Write-Host '║ File Hash Comparer ║'
		Write-Host '╚════════════════════╝'
		Write-Host ''
		Write-Host '1. Minutes'
		Write-Host '2. Hours'
		Write-Host '3. Days'
		Write-Host '4. Months'
		Write-Host '5. Years'
		Write-Host ''
		$read = Read-Host 'Select time unit (1-5)'
		switch ($read.Trim()) {
			'1' {
				$unit = [TimeUnit]::Minutes
				break
			}
			'2' {
				$unit = [TimeUnit]::Hours
				break
			}
			'3' {
				$unit = [TimeUnit]::Days
				break
			}
			'4' {
				$unit = [TimeUnit]::Months
				break
			}
			'5' {
				$unit = [TimeUnit]::Years
				break
			}
			default { throw }
		}
		Write-Host ''
		$read = Read-Host ('Time since last file modification (' + (Get-TimeUnit $unit) + ')')
		$time = [int]$read
		Test-TimeValue $unit $time
	} catch {
		$unit = $null
		$time = 0
	}
	switch ($Mode) {
		([TimeMode]::SourceTime) {
			$script:opt.SourceTimeUnit = $unit
			$script:opt.SourceTime = $time
			break
		}
		([TimeMode]::TargetTime) {
			$script:opt.TargetTimeUnit = $unit
			$script:opt.TargetTime = $time
			break
		}
	}
}

function Show-SetAlgorithm {
	Invoke-ClearHost
	Write-Host '╔════════════════════╗'
	Write-Host '║ File Hash Comparer ║'
	Write-Host '╚════════════════════╝'
	Write-Host ''
	Write-Host '1. CRC32'
	Write-Host '2. MD5'
	Write-Host '3. SHA1'
	Write-Host '4. SHA256'
	Write-Host '5. SHA384'
	Write-Host '6. SHA512'
	Write-Host ''
	$read = Read-Host 'Select algorithm (1-6)'
	switch ($read.Trim()) {
		'1' {
			$script:opt.Algorithm = 'CRC32'
			break
		}
		'2' {
			$script:opt.Algorithm = 'MD5'
			break
		}
		'3' {
			$script:opt.Algorithm = 'SHA1'
			break
		}
		'4' {
			$script:opt.Algorithm = 'SHA256'
			break
		}
		'5' {
			$script:opt.Algorithm = 'SHA384'
			break
		}
		'6' {
			$script:opt.Algorithm = 'SHA512'
			break
		}
		default { return }
	}
}

function Show-Paths {
	$restart = $true
	while ($restart) {
		$restart = $false
		Invoke-ClearHost
		Write-Host '╔════════════════════╗'
		Write-Host '║ File Hash Comparer ║'
		Write-Host '╚════════════════════╝'
		Write-Host ''
		if ($script:hasTargetSet) {
			if ($script:source.Count -eq 1) {
				Write-Host ('Source path: ' + (Remove-LongPrefix $script:source[0]))
			} else {
				Write-Host 'Source paths:'
				foreach ($path in $script:source) { Write-Host (Remove-LongPrefix $path) }
			}
			Write-Host ''
			if ($script:target.Count -eq 1) {
				Write-Host ('Target path: ' + (Remove-LongPrefix $script:target[0]))
			} else {
				Write-Host 'Target paths:'
				foreach ($path in $script:target) { Write-Host (Remove-LongPrefix $path) }
			}
		} else {
			if ($script:source.Count -eq 1) {
				Write-Host ('Path: ' + (Remove-LongPrefix $script:source[0]))
			} else {
				Write-Host 'Paths:'
				foreach ($path in $script:source) { Write-Host (Remove-LongPrefix $path) }
			}
		}
		Write-Host ''
		$ret = $true
		while ($ret) {
			Write-Host 'Set new paths? (Yes / ' -NoNewline
			Write-Host '[No]' -ForegroundColor Green -NoNewline
			$read = Read-Host ')'
			switch -Regex ($read.Trim()) {
				'^$' {
					$ret = $false
					break
				}
				'^(y|yes)$' {
					Write-Host ''
					Show-NewPaths
					$restart = $true
					$ret = $false
					break
				}
				'^(n|no)$' {
					$ret = $false
					break
				}
			}
		}
	}
}

function Show-NewPaths {
	Invoke-ClearHost
	Write-Host '╔════════════════════╗'
	Write-Host '║ File Hash Comparer ║'
	Write-Host '╚════════════════════╝'
	Write-Host ''
	Write-Host '1. Common file set'
	Write-Host '2. Source and target file sets'
	Write-Host ''
	$read = Read-Host 'Select file set (1-2)'
	Write-Host ''
	switch ($read.Trim()) {
		'1' {
			$read = Read-Host 'Paths'
			if ($read) { Parse-Args $read -Source -ErrPause }
			$script:target = @()
			break
		}
		'2' {
			$read = Read-Host 'Source paths'
			if ($read) { Parse-Args $read -Source }
			Write-Host ''
			$read = Read-Host 'Target paths'
			if ($read) { Parse-Args $read -Target -ErrPause}
			break
		}
		default { return }
	}
	$script:hasTargetSet = $script:target.Count -gt 0
}

function Parse-Args {
	param(
		[string]$Arguments,
		[switch]$Source,
		[switch]$Target,
		[switch]$ErrPause
	)
	$argList = @([regex]::Matches($Arguments, '(?:[^\s"]|"[^"]*")+') | ForEach-Object { $_.Value })
	if ($argList.Count -eq 0) { return }
	$argErr = $false
	$sourceArgs = [ordered]@{}
	$targetArgs = [ordered]@{}
	$sep = $Target
	foreach ($argRaw in $argList) {
		$arg = $argRaw.Replace('"', '')
		if (-not ($Source -or $sep)) {
			$argOpt = @()
			$argVal = $null
			if ($arg -eq '--') {
				$sep = $true
				continue
			} elseif ($arg -match '^(--[^=]+=)(.*)$') {
				$argOpt = @($Matches[1])
				$argVal = $Matches[2]
			} elseif ($arg -match '^--.+$') {
				$argOpt = @($arg)
			} elseif ($arg -match '^-(.+)$') {
				$argOpt = @($Matches[1].ToCharArray() | ForEach-Object { '-' + $_ })
			}
			if ($argOpt.Count -gt 0) {
				try {
					foreach ($opt in $argOpt) {
						switch -Regex ($opt) {
							'^(-r|--run)$' {
								$script:opt.ShowMenu = $false
								$script:opt.SaveMsg = $false
								$script:opt.LogMsg = $false
								break
							}
							'^(-s|--skip-size-match)$' {
								$script:opt.Size = $false
								break
							}
							'^(-n|--name-match)$' {
								$script:opt.Name = $true
								break
							}
							'^(-e|--extension-match)$' {
								$script:opt.Extension = $true
								break
							}
							'^(-d|--directory-name-match)$' {
								$script:opt.DirectoryName = $true
								break
							}
							'^(-t|--last-write-time-match)$' {
								$script:opt.LastWriteTime = $true
								break
							}
							'^(-i|--log-mismatches)$' {
								$script:opt.LogMode = [LogMode]::Mismatches
								break
							}
							'^(-m|--log-matches)$' {
								$script:opt.LogMode = [LogMode]::Matches
								break
							}
							'^(-v|--no-verbose)$' {
								$script:opt.Verbose = $false
								break
							}
							'^(-c|--save-checksums)$' {
								$script:opt.SaveMsg = $false
								$script:opt.Save = $true
								break
							}
							'^(-l|--save-log)$' {
								$script:opt.LogMsg = $false
								$script:opt.Log = $true
								break
							}
							'^(-q|--quiet)$' {
								$script:opt.Quiet = $true
								break
							}
							'^(-b|--batch)$' {
								$script:opt.Batch = $true
								break
							}
							'^--md5$' {
								$script:opt.Algorithm = 'MD5'
								break
							}
							'^--sha1$' {
								$script:opt.Algorithm = 'SHA1'
								break
							}
							'^--sha256$' {
								$script:opt.Algorithm = 'SHA256'
								break
							}
							'^--sha384$' {
								$script:opt.Algorithm = 'SHA384'
								break
							}
							'^--sha512$' {
								$script:opt.Algorithm = 'SHA512'
								break
							}
							'^--include=$' {
								$script:opt.SourceInclude = @(Get-FileMask $argVal)
								break
							}
							'^--exclude=$' {
								$script:opt.SourceExclude = @(Get-FileMask $argVal)
								break
							}
							'^--minutes=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Minutes) $intVal
								$script:opt.SourceTime = $intVal
								$script:opt.SourceTimeUnit = [TimeUnit]::Minutes
								break
							}
							'^--hours=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Hours) $intVal
								$script:opt.SourceTime = $intVal
								$script:opt.SourceTimeUnit = [TimeUnit]::Hours
								break
							}
							'^--days=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Days) $intVal
								$script:opt.SourceTime = $intVal
								$script:opt.SourceTimeUnit = [TimeUnit]::Days
								break
							}
							'^--months=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Months) $intVal
								$script:opt.SourceTime = $intVal
								$script:opt.SourceTimeUnit = [TimeUnit]::Months
								break
							}
							'^--years=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Years) $intVal
								$script:opt.SourceTime = $intVal
								$script:opt.SourceTimeUnit = [TimeUnit]::Years
								break
							}
							'^--target-include=$' {
								$script:opt.TargetInclude = @(Get-FileMask $argVal)
								break
							}
							'^--target-exclude=$' {
								$script:opt.TargetExclude = @(Get-FileMask $argVal)
								break
							}
							'^--target-minutes=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Minutes) $intVal
								$script:opt.TargetTime = $intVal
								$script:opt.TargetTimeUnit = [TimeUnit]::Minutes
								break
							}
							'^--target-hours=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Hours) $intVal
								$script:opt.TargetTime = $intVal
								$script:opt.TargetTimeUnit = [TimeUnit]::Hours
								break
							}
							'^--target-days=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Days) $intVal
								$script:opt.TargetTime = $intVal
								$script:opt.TargetTimeUnit = [TimeUnit]::Days
								break
							}
							'^--target-months=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Months) $intVal
								$script:opt.TargetTime = $intVal
								$script:opt.TargetTimeUnit = [TimeUnit]::Months
								break
							}
							'^--target-years=$' {
								$intVal = [int]$argVal
								Test-TimeValue ([TimeUnit]::Years) $intVal
								$script:opt.TargetTime = $intVal
								$script:opt.TargetTimeUnit = [TimeUnit]::Years
								break
							}
							default { throw }
						}
					}
				} catch {
					Write-Host ('Invalid option: ' + $argRaw) -ForegroundColor Red
					$argErr = $true
				}
				continue
			}
		}
		try {
			$argObjects = @()
			if ((Remove-LongPrefix $arg) -match '[*?]') {
				$argName = [System.IO.Path]::GetFileName($arg)
				$argDir = [System.IO.Path]::GetDirectoryName($arg)
				if (-not $argDir) { $argDir = $script:curDir }
				$argDir = Get-LongPath $argDir
				$argObjects = @(Get-ChildItem -LiteralPath $argDir -Filter $argName -Force -ErrorAction SilentlyContinue)
			} else {
				$argName = Get-LongPath $arg
				$argObjects = @(Get-Item -LiteralPath $argName -Force -ErrorAction SilentlyContinue)
			}
			if ($argObjects.Count -eq 0) { throw }
			foreach ($argName in $argObjects.FullName) {
				if (-not $sep) {
					$sourceArgs[$argName] = $null
				} elseif (-not $Source) {
					$targetArgs[$argName] = $null
				}
			}
		} catch {
			Write-Host ('Path not found: ' + $argRaw) -ForegroundColor Red
			$argErr = $true
		}
	}
	if ($argErr) {
		if ($ErrPause) { Invoke-Pause }
		if (-not ($Source -or $Target)) { exit 2 }
	}
	if ($sourceArgs.Count -gt 0) { $script:source = @($sourceArgs.Keys) }
	if ($targetArgs.Count -gt 0) { $script:target = @($targetArgs.Keys) }
}

function Add-LongPrefix {
	param(
		[string]$Path
	)
	if ($Path.StartsWith('\\.\', [System.StringComparison]::Ordinal)) {
		return $Path
	} elseif ($Path.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
		return $Path
	} elseif ($Path.StartsWith('\\', [System.StringComparison]::Ordinal)) {
		return '\\?\UNC\' + $Path.Substring(2)
	} else {
		return '\\?\' + $Path
	}
}

function Remove-LongPrefix {
	param(
		[string]$Path
	)
	if ($Path.StartsWith('\\.\', [System.StringComparison]::Ordinal)) {
		return $Path
	} elseif ($Path.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
		return '\\' + $Path.Substring(8)
	} elseif ($Path.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
		return $Path.Substring(4)
	} else {
		return $Path
	}
}

function Get-LongPath {
	param(
		[string]$Path
	)
	return Add-LongPrefix ([System.IO.Path]::GetFullPath($Path))
}

function Get-HashValue {
	param(
		[string]$Path,
		[string]$Algorithm
	)
	$stream = $null
	try {
		try {
			$stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
		} catch {
			try {
				$stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
			} catch {
				Write-Err $_
				return $null
			}
		}
		if ($Algorithm -eq 'CRC32') {
			$result = [System.UInt32]0
			$buffer = [byte[]]::new(65536)
			while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
				$result = [NTDLL.Win32Crc32]::RtlComputeCrc32($result, $buffer, $bytesRead)
			}
			return $result.ToString('X8')
		} else {
			return (Get-FileHash -InputStream $stream -Algorithm $Algorithm -ErrorAction Stop).Hash.ToLowerInvariant()
		}
	} catch {
		Write-Err $_
		return $null
	} finally {
		if ($stream) { $stream.Dispose() }
	}
}

function Get-EntLine {
	param(
		[string]$Path,
		[string]$Hash,
		[string]$Algorithm
	)
	if ($Algorithm -eq 'CRC32') {
		return $Path + ' ' + $Hash
	} else {
		return $Hash + ' *' + $Path
	}
}

function Get-CommentLine {
	param(
		[string]$Value,
		[string]$Algorithm
	)
	if ($Algorithm -eq 'CRC32') {
		return '; ' + $Value
	} else {
		return '# ' + $Value
	}
}

function Get-CompFiles {
	param(
		[string[]]$Paths
	)
	$compFiles = [ordered]@{}
	$searchErr = @()
	Get-ChildItem -LiteralPath $Paths -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +searchErr |
		ForEach-Object {
			$compFiles[(Add-LongPrefix $_.FullName)] = $_ | Add-Member -NotePropertyMembers @{
				Processed = $false
				Matched = $false
				Mismatched = $false
				HashError = $false
			} -PassThru
		}
	foreach ($err in $searchErr) { Write-Err $err }
	$compFiles.Remove($script:batFile)
	return $compFiles.Values
}

function Get-CompKeys {
	$compKeys = [System.Collections.Generic.List[string]]::new()
	if ($script:opt.Name) { $compKeys.Add([CompKey]::Name) }
	if ($script:opt.Extension) { $compKeys.Add([CompKey]::Extension) }
	if ($script:opt.DirectoryName) { $compKeys.Add([CompKey]::DirectoryName) }
	if ($script:opt.Size) { $compKeys.Add([CompKey]::Size) }
	if ($script:opt.LastWriteTime) { $compKeys.Add([CompKey]::LastWriteTime) }
	return $compKeys
}

function Get-CompKeyValue {
	param(
		[System.IO.FileSystemInfo]$File,
		[CompKey]$Key
	)
	switch ($Key) {
		([CompKey]::Name) { return $File.BaseName }
		([CompKey]::Extension) { return $File.Extension }
		([CompKey]::DirectoryName) { return $File.Directory.Name }
		([CompKey]::Size) { return $File.Length }
		([CompKey]::LastWriteTime) { return $File.LastWriteTime.Ticks }
	}
}

function Get-CompFileName {
	param(
		[System.IO.FileSystemInfo]$File
	)
	if ($script:opt.Name -or $script:opt.Extension -or $script:opt.DirectoryName) {
		$name = if ($script:opt.Name) { $File.BaseName } else { '*' }
		$extension = if ($script:opt.Extension) { $File.Extension } else { '.*' }
		$directoryName = if ($script:opt.DirectoryName) { $File.Directory.Name.TrimEnd('\') + '\' } else { '' }
		return 'File name: ' + $directoryName + $name + $extension
	}
	return $null
}

function Get-CompStat {
	param(
		[object[]]$Objects
	)
	$stat = [PSCustomObject]@{
		Processed = 0
		Partially = 0
		Matched = 0
		Mismatched = 0
		NotCompared = 0
		HashError = 0
	}
	foreach ($obj in $Objects) {
		if ($obj.Processed) { $stat.Processed++ }
		if ($obj.Matched) {
			if ($obj.Mismatched) {
				$stat.Partially++
			} else {
				$stat.Matched++
			}
		} elseif ($obj.Mismatched) {
			$stat.Mismatched++
		}
		if ($obj.HashError) { $stat.HashError++ }
	}
	$stat.NotCompared = $stat.Processed - $stat.Partially - $stat.Matched - $stat.Mismatched
	return $stat
}

function Get-TimeUnit {
	param(
		[TimeUnit]$Unit
	)
	switch ($Unit) {
		([TimeUnit]::Minutes) { return 'minutes' }
		([TimeUnit]::Hours) { return 'hours' }
		([TimeUnit]::Days) { return 'days' }
		([TimeUnit]::Months) { return 'months' }
		([TimeUnit]::Years) { return 'years' }
	}
}

function Get-FileTime {
	param(
		[TimeUnit]$Unit,
		[int]$Time
	)
	try {
		switch ($Unit) {
			([TimeUnit]::Minutes) { return $script:start.AddMinutes(-$Time) }
			([TimeUnit]::Hours) { return $script:start.AddHours(-$Time) }
			([TimeUnit]::Days) { return $script:start.AddDays(-$Time) }
			([TimeUnit]::Months) { return $script:start.AddMonths(-$Time) }
			([TimeUnit]::Years) { return $script:start.AddYears(-$Time) }
		}
	} catch {
		return $null
	}
}

function Get-FileMask {
	param(
		[string]$Value,
		[switch]$ErrSkip
	)
	$masks = [ordered]@{}
	foreach ($mask in @($Value -split '\|' | Where-Object { $_ -ne '' })) {
		try {
			[void]('' -like $mask)
			$masks[$mask.Replace('/', '\')] = $null
		} catch {
			if (-not $ErrSkip) { throw }
		}
	}
	if ($masks.Count -eq 0) { throw }
	return $masks.Keys
}

function Test-FileTime {
	param(
		[System.IO.FileSystemInfo]$File,
		[DateTime]$Time
	)
	return ($File.LastWriteTime -ge $Time) -or ($File.CreationTime -ge $Time)
}

function Test-FileMask {
	param(
		[string]$Path,
		[string[]]$Masks
	)
	$match = $false
	foreach ($mask in $Masks) {
		if ($mask.Contains('\')) {
			$match = (Remove-LongPrefix $Path) -like $mask
		} else {
			$match = [System.IO.Path]::GetFileName($Path) -like $mask
		}
		if ($match) { break }
	}
	return $match
}

function Test-TimeValue {
	param(
		[TimeUnit]$Unit,
		[int]$Time
	)
	if ($Time -le 0) { throw }
	if ($null -eq (Get-FileTime $Unit $Time)) { throw }
}

function Write-Log {
	param(
		[string]$Value,
		[ConsoleColor]$ForegroundColor,
		[DateTime]$Time,
		[switch]$NoHost
	)
	if (-not ($script:opt.Quiet -or $NoHost)) {
		if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
			Write-Host $Value -ForegroundColor $ForegroundColor
		} else {
			Write-Host $Value
		}
	}
	if ($Value) {
		if (-not $PSBoundParameters.ContainsKey('Time')) { $Time = Get-Date }
		$script:log.Add('[' + $Time.ToString('yyyy-MM-dd HH:mm:ss.fff') + '] ' + $Value)
	} else {
		$script:log.Add('')
	}
}

function Write-Err {
	param(
		[object]$Err
	)
	$errMsg = $null
	if ($Err.Exception -and $Err.Exception.InnerException) { $errMsg = $Err.Exception.InnerException.Message }
	if (-not $errMsg) { $errMsg = $Err.ToString() }
	Write-Log ('Execution error: ' + $errMsg) -ForegroundColor Red
	$script:err++
}

function Save-Lines {
	param(
		[string]$Name,
		[string]$Extension,
		[string[]]$Lines
	)
	$tempFile = [System.IO.Path]::Combine($script:curDir, $Name + '_' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
	$idx = 0
	$fileName = [System.IO.Path]::Combine($script:curDir, $Name + $Extension)
	try {
		[System.IO.File]::WriteAllLines($tempFile, $Lines, [System.Text.UTF8Encoding]::new($false))
		while ($true) {
			try {
				[System.IO.File]::Move($tempFile, $fileName)
				break
			} catch [System.IO.IOException] {
				if (($_.Exception.HResult -band 0xFFFF) -in 0x50, 0xB7) {
					$idx++
					$fileName = [System.IO.Path]::Combine($script:curDir, $Name + ' (' + $idx + ')' + $Extension)
				} else {
					throw
				}
			}
		}
		return Remove-LongPrefix $fileName
	} catch {
		Write-Err $_
		return $null
	} finally {
		if ([System.IO.File]::Exists($tempFile)) {
			try { [System.IO.File]::Delete($tempFile) } catch {}
		}
	}
}

function Invoke-ClearHost {
	if ($script:opt.Batch) {
		Write-Host ''
	} else {
		Clear-Host
	}
}

function Invoke-Pause {
	if (-not $script:opt.Batch) {
		Write-Host ''
		pause
	}
}

$script:start = Get-Date
$script:curDir = Add-LongPrefix $env:CURDIR
$script:batFile = Add-LongPrefix $env:BATFILE
$script:err = 0
$script:source = @()
$script:target = @()
Parse-Args $env:CMDARGS -ErrPause
if (($script:source.Count -eq 0) -and ($script:target.Count -gt 0)) {
	$script:source = $script:target
	$script:target = @()
}
$script:hasTargetSet = $script:target.Count -gt 0
if ($script:source.Count -eq 0) { $script:source = @($script:curDir) }
if ($script:opt.ShowMenu) {
	Show-Menu
	$script:start = Get-Date
}
Invoke-ClearHost
$script:log = [System.Collections.Generic.List[string]]::new()
Write-Log 'Comparison started' -Time $script:start -NoHost
Write-Log '' -NoHost
if (-not $script:hasTargetSet) {
	$script:opt.TargetInclude = $script:opt.SourceInclude
	$script:opt.TargetExclude = $script:opt.SourceExclude
	$script:opt.TargetTimeUnit = $script:opt.SourceTimeUnit
	$script:opt.TargetTime = $script:opt.SourceTime
}
$sourceFileTime = $null
if ($script:opt.SourceTime -gt 0) {
	$sourceFileTime = Get-FileTime $script:opt.SourceTimeUnit $script:opt.SourceTime
}
$targetFileTime = $null
if ($script:opt.TargetTime -gt 0) {
	$targetFileTime = Get-FileTime $script:opt.TargetTimeUnit $script:opt.TargetTime
}
if ($script:hasTargetSet) {
	if ($script:source.Count -eq 1) {
		Write-Log ('Source path: ' + (Remove-LongPrefix $script:source[0]))
	} else {
		Write-Log 'Source paths:'
		foreach ($path in $script:source) { Write-Log (Remove-LongPrefix $path) }
	}
} else {
	if ($script:source.Count -eq 1) {
		Write-Log ('Path: ' + (Remove-LongPrefix $script:source[0]))
	} else {
		Write-Log 'Paths:'
		foreach ($path in $script:source) { Write-Log (Remove-LongPrefix $path) }
	}
}
$sourceObjects = @(Get-CompFiles $script:source)
if ($sourceObjects.Count -eq 0) {
	if ($script:hasTargetSet) {
		Write-Host 'Source files not found!' -ForegroundColor Red
	} else {
		Write-Host 'Files not found!' -ForegroundColor Red
	}
	Invoke-Pause
	exit 1
} elseif ($script:hasTargetSet) {
	Write-Log ('Source files found: ' + $sourceObjects.Count)
	Write-Log ''
	if ($script:target.Count -eq 1) {
		Write-Log ('Target path: ' + (Remove-LongPrefix $script:target[0]))
	} else {
		Write-Log 'Target paths:'
		foreach ($path in $script:target) { Write-Log (Remove-LongPrefix $path) }
	}
	$targetObjects = @(Get-CompFiles $script:target)
	if ($targetObjects.Count -eq 0) {
		Write-Host 'Target files not found!' -ForegroundColor Red
		Invoke-Pause
		exit 1
	} else {
		Write-Log ('Target files found: ' + $targetObjects.Count)
	}
} else {
	Write-Log ('Files found: ' + $sourceObjects.Count)
	$targetObjects = $sourceObjects
}
Write-Log ''
$targetGroups = @{}
$compKeys = @(Get-CompKeys)
$compKeysCount = $compKeys.Count
$hasTargetGroups = $compKeysCount -gt 0
if ($hasTargetGroups) {
	foreach ($obj in $targetObjects) {
		$group = $targetGroups
		for ($idx = 0; $idx -lt $compKeysCount; $idx++) {
			$key = Get-CompKeyValue $obj $compKeys[$idx]
			if ($idx -eq ($compKeysCount - 1)) {
				if (-not $group.ContainsKey($key)) { $group[$key] = [System.Collections.Generic.List[Object]]::new() }
				$group[$key].Add($obj)
			} else {
				if (-not $group.ContainsKey($key)) { $group[$key] = @{} }
				$group = $group[$key]
			}
		}
	}
} else {
	$targetGroups = $targetObjects
}
$hashes = @{}
foreach ($srcObj in $sourceObjects) {
	if ($srcObj.Processed) { continue }
	$group = $targetGroups
	if ($hasTargetGroups) {
		for ($idx = 0; $idx -lt $compKeysCount; $idx++) {
			$key = Get-CompKeyValue $srcObj $compKeys[$idx]
			if (-not $group.ContainsKey($key)) {
				$group = $null
				break
			}
			$group = $group[$key]
		}
	}
	if ($null -eq $group) { continue }
	$srcName = Add-LongPrefix $srcObj.FullName
	if (($null -ne $sourceFileTime) -and (-not (Test-FileTime $srcObj $sourceFileTime))) { continue }
	if (($script:opt.SourceInclude.Count -gt 0) -and (-not (Test-FileMask $srcName $script:opt.SourceInclude))) { continue }
	if (($script:opt.SourceExclude.Count -gt 0) -and (Test-FileMask $srcName $script:opt.SourceExclude)) { continue }
	$objGroup = [System.Collections.Generic.List[Object]]::new()
	$objGroup.Add($srcObj)
	foreach ($obj in $group) {
		$objName = Add-LongPrefix $obj.FullName
		if ($srcName -eq $objName) { continue }
		if (($null -ne $targetFileTime) -and (-not (Test-FileTime $obj $targetFileTime))) { continue }
		if (($script:opt.TargetInclude.Count -gt 0) -and (-not (Test-FileMask $objName $script:opt.TargetInclude))) { continue }
		if (($script:opt.TargetExclude.Count -gt 0) -and (Test-FileMask $objName $script:opt.TargetExclude)) { continue }
		$obj.Processed = $true
		$objGroup.Add($obj)
	}
	$objCount = $objGroup.Count
	if ($objCount -le 1) { continue }
	$srcObj.Processed = $true
	$lengthMap = @{}
	foreach ($obj in $objGroup) {
		$key = $obj.Length
		$lengthMap[$key] = $lengthMap.ContainsKey($key)
	}
	$lengthGroups = [ordered]@{}
	$compGroups = [System.Collections.Generic.List[Object]]::new()
	$missingGroup = [System.Collections.Generic.List[Object]]::new()
	for ($idx = 0; $idx -lt $objCount; $idx++) {
		$obj = $objGroup[$idx]
		$objName = Add-LongPrefix $obj.FullName
		$key = $obj.Length.ToString()
		if (-not $lengthGroups.Contains($key)) { $lengthGroups[$key] = [ordered]@{} }
		$hashGroups = $lengthGroups[$key]
		if ($lengthMap[$obj.Length]) {
			$hashObj = $hashes[$objName]
			if ($null -eq $hashObj) {
				$hash = Get-HashValue $objName $script:opt.Algorithm
				$hashes[$objName] = [PSCustomObject]@{
					Hash = $hash
					Length = $obj.Length
				}
			} else {
				$hash = $hashObj.Hash
			}
			if ($null -eq $hash) {
				if (-not $obj.HashError) {
					$obj.HashError = $true
					Write-Log ('Failed to calculate hash: ' + (Remove-LongPrefix $objName)) -ForegroundColor Red
				}
				if ($script:hasTargetSet -and ($idx -eq 0)) { break }
				$missingGroup.Add($obj)
			} else {
				if (-not $hashGroups.Contains($hash)) {
					$group = [System.Collections.Generic.List[Object]]::new()
					$compGroups.Add($group)
					$hashGroups[$hash] = $group
				}
				$hashGroups[$hash].Add($obj)
			}
		} else {
			$group = [System.Collections.Generic.List[Object]]::new()
			$group.Add($obj)
			$compGroups.Add($group)
		}
	}
	$compCount = $compGroups.Count
	if (($compCount -eq 0) -or (($compCount -eq 1) -and ($compGroups[0].Count -le 1))) {
		if ($script:hasTargetSet) {
			Write-Log ('Source file not compared: ' + (Remove-LongPrefix $srcName)) -ForegroundColor Magenta
			if ($script:opt.Verbose) {
				Write-Log ('File size: ' + $srcObj.Length.ToString('N0')) -ForegroundColor DarkMagenta
				Write-Log ('Last write time: ' + $srcObj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor DarkMagenta
			}
			$missingGroup = $objGroup[1..($objCount - 1)]
		} else {
			$fileName = Get-CompFileName $srcObj
			if ($null -ne $fileName) { Write-Log $fileName -ForegroundColor Magenta }
			if ($script:opt.Size) { Write-Log ('File size: ' + $srcObj.Length.ToString('N0')) -ForegroundColor Magenta }
			if ($script:opt.LastWriteTime) { Write-Log ('Last write time: ' + $srcObj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Magenta }
			$missingGroup = $objGroup
		}
		$missingCount = $missingGroup.Count
	} else {
		$missingCount = $missingGroup.Count
		$groupsMismatched = $compCount -gt 1
		if ($script:hasTargetSet) {
			$group = $compGroups[0]
			$groupCount = $group.Count
			$groupMatched = $groupCount -gt 1
			$srcObj.Matched = $groupMatched
			$srcObj.Mismatched = $groupsMismatched
			for ($idx = 1; $idx -lt $groupCount; $idx++) {
				$group[$idx].Matched = $true
			}
			for ($idx = 1; $idx -lt $compCount; $idx++) {
				foreach ($obj in $compGroups[$idx]) {
					$obj.Mismatched = $true
				}
			}
			$showComp = $true
			if ($groupMatched -and $groupsMismatched) {
				$color = [ConsoleColor]::Yellow
				$darkColor = [ConsoleColor]::DarkYellow
			} elseif ($groupMatched -and ($script:opt.LogMode -ne [LogMode]::Mismatches)) {
				$color = [ConsoleColor]::Green
				$darkColor = [ConsoleColor]::DarkGreen
			} elseif ($groupsMismatched -and ($script:opt.LogMode -ne [LogMode]::Matches)) {
				$color = [ConsoleColor]::Red
				$darkColor = [ConsoleColor]::DarkRed
			} elseif ($missingCount -gt 0) {
				$color = [ConsoleColor]::Magenta
				$darkColor = [ConsoleColor]::DarkMagenta
				$showComp = $false
			} else {
				continue
			}
			Write-Log ('Source file: ' + (Remove-LongPrefix $srcName)) -ForegroundColor $color
			if ($script:opt.Verbose) {
				Write-Log ('File size: ' + $srcObj.Length.ToString('N0')) -ForegroundColor $darkColor
				Write-Log ('Last write time: ' + $srcObj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor $darkColor
			}
			if ($showComp) {
				if ($groupMatched -and ($script:opt.LogMode -ne [LogMode]::Mismatches)) {
					$filesCount = $groupCount - 1
					Write-Log ('Files matched: ' + $filesCount) -ForegroundColor Green
					for ($idx = 1; $idx -lt $groupCount; $idx++) {
						$obj = $group[$idx]
						Write-Log ('  File {0}/{1}: {2}' -f $idx, $filesCount, (Remove-LongPrefix $obj.FullName)) -ForegroundColor Green
						if ($script:opt.Verbose -and (-not $script:opt.LastWriteTime) -and ($srcObj.LastWriteTime -ne $obj.LastWriteTime)) { Write-Log ('  Last write time: ' + $obj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Cyan }
					}
				}
				if ($groupsMismatched -and ($script:opt.LogMode -ne [LogMode]::Matches)) {
					$filesCount = $objCount - $missingCount - $groupCount
					$fileIdx = 1
					Write-Log ('Files mismatched: ' + $filesCount) -ForegroundColor Red
					for ($idx = 1; $idx -lt $compCount; $idx++) {
						foreach ($obj in $compGroups[$idx]) {
							Write-Log ('  File {0}/{1}: {2}' -f ($fileIdx++), $filesCount, (Remove-LongPrefix $obj.FullName)) -ForegroundColor Red
							if ($script:opt.Verbose) {
								$darkColor = if (($srcObj.Length -eq $obj.Length) -and ($srcObj.LastWriteTime -eq $obj.LastWriteTime)) { [ConsoleColor]::Magenta } else { [ConsoleColor]::DarkRed }
								if (-not $script:opt.Size) { Write-Log ('  File size: ' + $obj.Length.ToString('N0')) -ForegroundColor $darkColor }
								if (-not $script:opt.LastWriteTime) { Write-Log ('  Last write time: ' + $obj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor $darkColor }
							}
						}
					}
				}
			}
		} else {
			$groupsMatched = $false
			foreach ($group in $compGroups) {
				$groupMatched = $group.Count -gt 1
				$groupMismatched = if ($hasTargetGroups) { $groupsMismatched } else { -not $groupMatched }
				if ($groupMatched) { $groupsMatched = $true }
				foreach ($obj in $group) {
					$obj.Matched = $groupMatched
					$obj.Mismatched = $groupMismatched
				}
			}
			$showComp = $true
			if ($groupsMatched -and $groupsMismatched) {
				$color = [ConsoleColor]::Yellow
			} elseif ($groupsMatched -and ($script:opt.LogMode -ne [LogMode]::Mismatches)) {
				$color = [ConsoleColor]::Green
			} elseif ($groupsMismatched -and ($script:opt.LogMode -ne [LogMode]::Matches)) {
				$color = [ConsoleColor]::Red
			} elseif ($missingCount -gt 0) {
				$color = [ConsoleColor]::Magenta
				$showComp = $false
			} else {
				continue
			}
			$fileName = Get-CompFileName $srcObj
			if ($null -ne $fileName) { Write-Log $fileName -ForegroundColor $color }
			if ($script:opt.Size) { Write-Log ('File size: ' + $srcObj.Length.ToString('N0')) -ForegroundColor $color }
			if ($script:opt.LastWriteTime) { Write-Log ('Last write time: ' + $srcObj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor $color }
			if ($showComp) {
				Write-Log ('Files compared: ' + ($objCount - $missingCount)) -ForegroundColor $color
				for ($groupIdx = 0; $groupIdx -lt $compCount; $groupIdx++) {
					$group = $compGroups[$groupIdx]
					$groupCount = $group.Count
					$groupMatched = $group[0].Matched
					$groupMismatched = $group[0].Mismatched
					if ($hasTargetGroups -and $groupMatched -and $groupMismatched) {
						$color = [ConsoleColor]::Yellow
						$darkColor = [ConsoleColor]::DarkYellow
					} elseif ($groupMatched -and ($script:opt.LogMode -ne [LogMode]::Mismatches)) {
						$color = [ConsoleColor]::Green
						$darkColor = [ConsoleColor]::DarkGreen
					} elseif ($groupMismatched -and ($script:opt.LogMode -ne [LogMode]::Matches)) {
						$color = [ConsoleColor]::Red
						$darkColor = [ConsoleColor]::DarkRed
					} else {
						continue
					}
					Write-Log ('Group {0}/{1}' -f ($groupIdx + 1), $compCount) -ForegroundColor $color
					if ($script:opt.Verbose -and (-not $script:opt.Size)) { Write-Log ('File size: ' + $group[0].Length.ToString('N0')) -ForegroundColor $darkColor }
					for ($idx = 0; $idx -lt $groupCount; $idx++) {
						$obj = $group[$idx]
						Write-Log ('  File {0}/{1}: {2}' -f ($idx + 1), $groupCount, (Remove-LongPrefix $obj.FullName)) -ForegroundColor $color
						if ($script:opt.Verbose -and (-not $script:opt.LastWriteTime)) { Write-Log ('  Last write time: ' + $obj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor $darkColor }
					}
				}
			}
		}
	}
	if ($missingCount -gt 0) {
		Write-Log ('Files not compared: ' + $missingCount) -ForegroundColor Magenta
		for ($idx = 0; $idx -lt $missingCount; $idx++) {
			$obj = $missingGroup[$idx]
			Write-Log ('  File {0}/{1}: {2}' -f ($idx + 1), $missingCount, (Remove-LongPrefix $obj.FullName)) -ForegroundColor Magenta
			if ($script:opt.Verbose) {
				if (-not $script:opt.Size) { Write-Log ('  File size: ' + $obj.Length.ToString('N0')) -ForegroundColor DarkMagenta }
				if (-not $script:opt.LastWriteTime) { Write-Log ('  Last write time: ' + $obj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor DarkMagenta }
			}
		}
	}
	Write-Log ''
}
Write-Log 'Comparison completed!'
Write-Log ''
$exit = 0
if ($script:err) {
	Write-Log ('Execution errors: ' + $script:err) -ForegroundColor Red
	Write-Log ''
	$exit = $exit -bor 4
}
$stat = Get-CompStat $sourceObjects
if ($stat.Processed) {
	if ($script:hasTargetSet) {
		Write-Log ('Source files processed: ' + $stat.Processed)
		if ($stat.Matched) {
			Write-Log ('Source files matched: ' + $stat.Matched) -ForegroundColor Green
		}
		if ($stat.Partially) {
			Write-Log ('Source files partially matched: ' + $stat.Partially) -ForegroundColor Yellow
			$exit = $exit -bor 8
		}
		if ($stat.Mismatched) {
			Write-Log ('Source files mismatched: ' + $stat.Mismatched) -ForegroundColor Red
			$exit = $exit -bor 8
		}
		if ($stat.NotCompared) {
			Write-Log ('Source files not compared: ' + $stat.NotCompared) -ForegroundColor Magenta
			$exit = $exit -bor 16
		}
		if ($stat.HashError) { Write-Log ('Source hash calculation errors: ' + $stat.HashError) -ForegroundColor Red }
		Write-Log ''
		$stat = Get-CompStat $targetObjects
		Write-Log ('Target files processed: ' + $stat.Processed)
		if ($stat.Matched) {
			Write-Log ('Target files matched: ' + $stat.Matched) -ForegroundColor Green
		}
		if ($stat.Partially) {
			Write-Log ('Target files partially matched: ' + $stat.Partially) -ForegroundColor Yellow
			$exit = $exit -bor 8
		}
		if ($stat.Mismatched) {
			Write-Log ('Target files mismatched: ' + $stat.Mismatched) -ForegroundColor Red
			$exit = $exit -bor 8
		}
		if ($stat.NotCompared) {
			Write-Log ('Target files not compared: ' + $stat.NotCompared) -ForegroundColor Magenta
			$exit = $exit -bor 16
		}
		if ($stat.HashError) { Write-Log ('Target hash calculation errors: ' + $stat.HashError) -ForegroundColor Red }
	} else {
		Write-Log ('Files processed: ' + $stat.Processed)
		if ($stat.Matched) {
			Write-Log ('Files matched: ' + $stat.Matched) -ForegroundColor Green
		}
		if ($stat.Partially) {
			Write-Log ('Files partially matched: ' + $stat.Partially) -ForegroundColor Yellow
			$exit = $exit -bor 8
		}
		if ($stat.Mismatched) {
			Write-Log ('Files mismatched: ' + $stat.Mismatched) -ForegroundColor Red
			$exit = $exit -bor 8
		}
		if ($stat.NotCompared) {
			Write-Log ('Files not compared: ' + $stat.NotCompared) -ForegroundColor Magenta
			$exit = $exit -bor 16
		}
		if ($stat.HashError) { Write-Log ('Hash calculation errors: ' + $stat.HashError) -ForegroundColor Red }
	}
} else {
	Write-Log 'Files for comparison not found!' -ForegroundColor Yellow
	$exit = $exit -bor 32
}
$finalPause = $true
$hashObjects = @($hashes.GetEnumerator() | Where-Object { $null -ne $_.Value.Hash })
if ($hashObjects.Count -gt 0) {
	if ($script:opt.SaveMsg) {
		Write-Host ''
		$ret = $true
		while ($ret) {
			Write-Host 'Save checksums? (Yes / ' -NoNewline
			Write-Host '[No]' -ForegroundColor Green -NoNewline
			$read = Read-Host ')'
			switch -Regex ($read.Trim()) {
				'^$' {
					$script:opt.Save = $false
					$ret = $false
					break
				}
				'^(y|yes)$' {
					$script:opt.Save = $true
					$ret = $false
					break
				}
				'^(n|no)$' {
					$script:opt.Save = $false
					$ret = $false
					break
				}
			}
		}
		$finalPause = $false
	}
	if ($script:opt.Save) {
		Write-Host ''
		$extensions = @{
			'CRC32' = '.sfv'
			'MD5' = '.md5'
			'SHA1' = '.sha1'
			'SHA256' = '.sha256'
			'SHA384' = '.sha384'
			'SHA512' = '.sha512'
		}
		$entries = [System.Collections.Generic.List[string]]::new()
		$length = $null
		$hash = $null
		$idx = 0
		foreach ($obj in @($hashObjects | Sort-Object { $_.Value.Length }, { $_.Value.Hash }, { [System.IO.Path]::GetDirectoryName($_.Key) }, { [System.IO.Path]::GetFileName($_.Key) })) {
			if ($length -ne $obj.Value.Length) {
				$hash = $null
				$idx = 0
				$length = $obj.Value.Length
				$entries.Add((Get-CommentLine ('File size: ' + $length.ToString('N0')) $script:opt.Algorithm))
			}
			if ($hash -ne $obj.Value.Hash) {
				$hash = $obj.Value.Hash
				$entries.Add((Get-CommentLine ('Group ' + (++$idx) + ':') $script:opt.Algorithm))
			}
			$entries.Add((Get-EntLine (Remove-LongPrefix $obj.Key) $obj.Value.Hash $script:opt.Algorithm))
		}
		$fileName = Save-Lines ('Comparison_Checksums_' + $script:start.ToString('yyyy-MM-dd_HH-mm-ss')) $extensions[$script:opt.Algorithm] $entries
		if ($fileName) {
			Write-Host ('Checksums saved to file: ' + (Remove-LongPrefix $fileName))
		} else {
			Write-Host 'Failed to save checksum file!' -ForegroundColor Red
			$exit = $exit -bor 64
		}
		$finalPause = $true
	}
}
if ($script:opt.LogMsg) {
	Write-Host ''
	$ret = $true
	while ($ret) {
		Write-Host 'Save log? (Yes / ' -NoNewline
		Write-Host '[No]' -ForegroundColor Green -NoNewline
		$read = Read-Host ')'
		switch -Regex ($read.Trim()) {
			'^$' {
				$script:opt.Log = $false
				$ret = $false
				break
			}
			'^(y|yes)$' {
				$script:opt.Log = $true
				$ret = $false
				break
			}
			'^(n|no)$' {
				$script:opt.Log = $false
				$ret = $false
				break
			}
		}
	}
	$finalPause = $false
}
if ($script:opt.Log) {
	Write-Host ''
	$fileName = Save-Lines ('Comparison_Log_' + $script:start.ToString('yyyy-MM-dd_HH-mm-ss')) '.txt' $script:log
	if ($fileName) {
		Write-Host ('Log saved to file: ' + (Remove-LongPrefix $fileName))
	} else {
		Write-Host 'Failed to save log file!' -ForegroundColor Red
		$exit = $exit -bor 128
	}
	$finalPause = $true
}
if ($finalPause) { Invoke-Pause }
exit $exit
