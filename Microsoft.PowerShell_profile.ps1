function global:up {
    $initialDirectory = (Get-Item -Path ".\").Name
    $subfolderUsed = 0
    if ($initialDirectory -ne '.docker' -And (Test-Path ".docker" -PathType Container)) {
        cd .docker
        $subfolderUsed = 1
    } else {
        Write-Verbose -Message "No .docker folder found. Using the current directory" -Verbose
    }

    $path = "shell/distributeConfig.sh"
    $windowsLineEndingChanged = 1
    if (Test-Path $path -PathType leaf) {
        (Get-Content $path -Raw).Replace("`r`n","`n") | Set-Content -NoNewline $path -Force
    } else {
        $windowsLineEndingChanged = 0
        Write-Verbose -Message "Windows line ending are not fixed in '$($path)'. File not found." -Verbose
    }

	docker-compose up -d --build --force-recreate

    if ($windowsLineEndingChanged) {
        (Get-Content $path -Raw).Replace("`n", "`r`n") | Set-Content -NoNewline $path -Force
    }

    if ($subfolderUsed) {
        cd ..
    }
}

function global:install {
    param ([string] $container)
    if (!$container) {
        $container = getContainer
    }
    docker exec -it $container  composer install
}

function global:update {
    param ([string] $container)
    if (!$container) {
        $container = getContainer
    }
    docker exec -it $container composer clearcache
    docker exec -it $container composer update
}

function getContainer() {
    $folderName = (dir (Get-Location)).directory.name[0]
    
    $fullMatch = ' ' + $folderName + '$'
    $container = docker ps -a --filter "name=$($folderName)" | Select-String -Pattern $fullMatch | ForEach-Object { -split $_.Line | Select-Object -Last 1 }
    if ([string]::IsNullOrEmpty($container)) {
        $matchWithVersion = ' (' + $folderName + 'v[0-9\.]+)$'
        $container = docker ps -a --filter "name=$($folderName)" | Select-String -Pattern $matchWithVersion | ForEach-Object { -split $_.Line | Select-Object -Last 1 }
    }
    
    if ([string]::IsNullOrEmpty($container)) {
        Write-Error "Can't find container. Please, run 'up' command."
    }

    if ($container -is [array]) {
        // TODO menu to choose version
        $container = $container[0]
    }

    Write-Verbose -Message "Using '$($container)' container" -Verbose

    return $container
}

function global:tag {
    git fetch --all --tags
    $currentGitTag = git describe --tags --abbrev=0
    $tagName = newTag $currentGitTag

    if (git diff --exit-code composer.json) {
        Write-Warning 'Commit composer.json first'
    } else {
        if ([string]::IsNullOrEmpty($tagName)) {
            Write-Error "Can't define a new tag name"
        } else {
            $title    = 'New tag'
            $question = 'Do you want to upgrade tag from "' + $currentGitTag + '" to "' + $tagName + '" and push to repository?'
            $choices  = '&Yes', '&No'
            $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
    
            if ($decision -eq 0) {
                Write-Verbose -Message "git tag $($tagName)" -Verbose
                git tag $tagName
                Write-Verbose -Message 'git push --tags' -Verbose
                git push --tags
            } else {
                Write-Warning 'cancelled'
            } 
        }
    }

}

function newTag($currentGitTag) {
    $composerJson = Get-Content -Raw -Path composer.json | ConvertFrom-Json
    $tagName = $composerJson.version

    if ($currentGitTag -eq $tagName) {
        $existingBeta = $tagName -split "-beta"
        if ($existingBeta.Count -gt 1) {
            $betaVersion = $existingBeta[1] -as [int]
            $tagName = $existingBeta[0] + '-beta' + (++$betaVersion)
        } else {
            $existingStable = $tagName -split "\."
            $stableMinorVersion = $existingStable[2] -as [int]

            $tagName = $existingStable[0] + '.' + $existingStable[1] + '.' + (++$stableMinorVersion) + '-beta1'
        }

        ((Get-Content -Raw -Path composer.json) -replace $currentGitTag, $tagName) | Set-Content -NoNewline -Path composer.json

        Write-Warning "Tag upgraded to $($tagName) in composer.json"
        return $tagName

        #git commit -F composer.json -m $tagName
    }
    
    return $tagName
}

function global:flush() {
	docker exec -it redis-phlow redis-cli flushall
}

function global:tagClear {
    git fetch --all --tags
    $tagsToDelete = @()
    foreach ($tag in git tag -l) {
        if (($tag -match '-beta..?$') -or ($tag -match '-alpha..?$')) {
            $tagsToDelete = $tagsToDelete + $tag
        }
    }

    if ($tagsToDelete.Count -gt 0) {
        $title    = 'Remove tag(s)'
        $question = "$($tagsToDelete)`nDo you want to completely remove $($tagsToDelete.Count) tags from local and remote repositories?"
        $choices  = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
    
        if ($decision -eq 0) {
            $gitTagCommands = @()
            foreach ($tag in $tagsToDelete) {
                $gitTagDeleteCommands = $gitTagDeleteCommands + "`ngit tag --delete $($tag)"
            }
            Write-Verbose -Message $gitTagDeleteCommands -Verbose

            foreach ($tag in $tagsToDelete) {
                git tag --delete $tag
            }

            foreach ($tag in $tagsToDelete) {
                Write-Verbose -Message "git push --delete origin $($tag)" -Verbose
                git push --delete origin $tag
            }
        } else {
            Write-Warning 'cancelled'
        }
    }
}

function global:sshtest {
	Write-Verbose -Message "p14qdbj8QE8Zo27cjCKP" -Verbose
	colortool --quiet campbell.ini
	ssh developer@localhost -p1701
}

function global:sshprod {
	colortool --quiet OneHalfLight.itermcolors
	ssh developer@localhost -p9701
}