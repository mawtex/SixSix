$excludeFiles = @(".deployment", ".*")            # ("like,"this") - environment files like web.prod.config will be cleaned up automatically
$excludeDirectories = @(".deploy", ".*")

$leaveOnDeploymentDirectories = @(                # Directories that are not in git, but should also NOT be deleted on the deployment - like temp state and logs
    "ApplicationState",
    "Cache",
    "LogFiles",
    "Search",
    "forms",
    "Xslt",
    "InlineCSharpFunctions")                    # the forms, xslt and InlineCSharpFunctions are here because C1 runtime will create these (empty). And then /MIR will delete - and IIS restart

#
# defaults
#
$deploymentSource = if ($Env:DEPLOYMENT_SOURCE) { $Env:DEPLOYMENT_SOURCE } else { ".." };
$deploymentTarget = if ($Env:DEPLOYMENT_TARGET) { $Env:DEPLOYMENT_TARGET } else { "..\..\website_deployed" };
$deploymentEnvironment = if ($Env:DEPLOYMENT_ENVIRONMENT) { $Env:DEPLOYMENT_ENVIRONMENT } else { "prd-cd" };
# $deploymentTemp = if ($Env:DEPLOYMENT_TEMP) { $Env:DEPLOYMENT_TEMP } else { "..\..\website_deploy_temp" };
# avoiding aws temp dir ($Env:DEPLOYMENT_TEMP) since it require full copy of repo each time, easily adding 50+ seconds to deploy + tons of useless disk io
$deploymentTemp = "..\..\website_deploy_temp" ; 

#
# functions
#
function Get-EnvFilenamePatterns {
    Param ([string]$env)

    $validEnvNames = ("dev","qa","int","stg","prd","prd-cm","prd-cd")

    if ($env -eq "all")
    {
        $all = @()
        foreach ($subEnv in $validEnvNames)
        {
            $subEnvPatterns = Get-EnvFilenamePatterns($subEnv)
            $all = $all + $subEnvPatterns
        }

        $all
    }
    else
    {
        if (($validEnvNames | where { $_ -eq $env}) -eq $null)
        {
            Write-Warning "Unknown deploymentEnvironment $env (expecting $validEnvNames)"
        }
        switch ( $env.ToLower() )
        {
            # Prioritized - ex: for qa, *.Test.* is taken instead of *.Debug.* if both match
            # only *.something.* patterns are supported, resulting in a *.* file
            "dev" { ("*.Debug.*") }
            "qa" { ("*.Test.*", "*.Debug.*") }
            "int" { ("*.Test.*", "*.Debug.*") }
            "stg" { ("*.Release.*", "*.Prod.*") }
            "prd" { ("*.Prod.*") }
            "prd-cm" { ("*.Prod.*") }
            "prd-cd" { ("*.Prod.*") }
        }
    }
}

#
# start status
#
if ($Env:DEPLOYMENT_SOURCE -eq $null -or $Env:DEPLOYMENT_TARGET -eq $null -or $Env:DEPLOYMENT_ENVIRONMENT -eq $null )
{
    [console]::WriteLine("Environment variables DEPLOYMENT_SOURCE DEPLOYMENT_TARGET DEPLOYMENT_ENVIRONMENT not set, asuming some default values.`n")
}

[console]::WriteLine("
$($MyInvocation.MyCommand.Name) running using these settings:
    deploymentSource:               $deploymentSource
    deploymentTarget:               $deploymentTarget
    deploymentEnvironment:          $deploymentEnvironment
    deploymentTemp:                 $deploymentTemp
    excludeDirectories:             $excludeDirectories
    excludeFiles:                   $excludeFiles
    leaveOnDeploymentDirectories:   $leaveOnDeploymentDirectories
    `n")

#
# start
#
[console]::WriteLine("Robocopy to temp:")
robocopy /mir $deploymentSource $deploymentTemp /r:3 /w:1 /XF @excludeFiles  /XD @excludeDirectories /njh /ndl /nc /ns /np

#
# fix *.prod.* deployment etc.
#
[console]::WriteLine("Environment specific files task:")
$envFilenamePatterns = Get-EnvFilenamePatterns( $deploymentEnvironment.ToLower() )
[console]::WriteLine("    envFilenamePattern: $envFilenamePatterns")

$envFiles = Get-ChildItem "$deploymentTemp\*" -include $envFilenamePatterns -Recurse -Force

foreach ($envFile in $envFiles)
{
    foreach ($envFilenamePattern in $envFilenamePatterns)
    {
        if ($envFile -like $envFilenamePattern) 
        {
            $toCleanFromFilename =  ($envFilenamePattern -replace "[\.\*]", "")
            $destinationFilename = $envFile -replace "(.*)\.$toCleanFromFilename(.*)", '$1$2'
            Copy-Item $envFile -Destination $destinationFilename
            [console]::WriteLine("    copying $envFilenamePattern version to $destinationFilename")
            break;
        }
    }
}

#
# deleting *.ENV.* files
#
$allEnvFilenamePatterns = Get-EnvFilenamePatterns("all")
Get-ChildItem "$deploymentTemp\*" -include $allEnvFilenamePatterns -Recurse -Force | Remove-Item

[console]::WriteLine("    deleted all environment specific template files")

#
# ensuring Composite.Generated.dll changes are actual an change (otherwise file is skipped to avoid restart)
#
$fileGeneratedFromGit = "$deploymentTemp\bin\Composite.Generated.dll"
$fileGeneratedTarget = "$deploymentTarget\bin\Composite.Generated.dll"

if ((Test-Path $fileGeneratedFromGit) -and (Test-Path $fileGeneratedTarget))
{
	if ((Get-Item $fileGeneratedFromGit).Length -eq (Get-Item $fileGeneratedTarget).Length)
	{
		# Grab Target version (ignore git change) ensuring later mirror or diff copy leaves target as is
		Copy-Item $fileGeneratedTarget -Destination $fileGeneratedFromGit -Force
		[console]::WriteLine("Keeping deployment's Composite.Generated.dll")
	}
}

#
# final copying
#
[console]::WriteLine("Robocopy to target, pure copy only, affected files:")
robocopy /e $deploymentTemp $deploymentTarget /r:1 /w:1 /njh /ndl /nc /ns /np 

#
# MIRRORING DISABLED
#
#[console]::WriteLine("Robocopy to target, mirroring (excluding $leaveOnDeploymentDirectories), affected files / directories:")
#[console]::WriteLine("    (Be aware that directories listed by RoboCopy below are likely being deleted and will cause the IIS AppPool to recycle)")
#robocopy /mir $deploymentTemp $deploymentTarget /r:3 /w:5 /njh /ndl /nc /ns /np /xd @leaveOnDeploymentDirectories

[console]::WriteLine("    Completed custom part of deployment")

