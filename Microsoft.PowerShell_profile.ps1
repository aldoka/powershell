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
    & putty
	Write-Verbose -Message "$([System.Environment]::GetEnvironmentVariable('PhlowSSHPathPhrase'))" -Verbose
	colortool --quiet campbell.ini
	ssh developer@localhost -p1701
}

function global:sshprod {
    & putty
	colortool --quiet OneHalfLight.itermcolors
	ssh developer@localhost -p9701
}

function global:putty {
    $pageant = Get-Process pageant -ErrorAction SilentlyContinue
    if (! $pageant) {
        & pageant.exe "c:\Users\user\.ssh\phlow_bastion.ppk" "c:\Users\user\.ssh\id_rsa.ppk" -c "c:\Program Files\PuTTY\putty.exe" -load "Phlow"
    } else {
        $putty = Get-Process putty -ErrorAction SilentlyContinue
        if (! $putty) {
            & "c:\Program Files\PuTTY\putty.exe" -load "Phlow"
        }
    }
}

function global:proxy {
    & rootCertificate
    $subDomain = $args[0]

    $confFolder = ".\certbot\conf\live\$subDomain"
    $rootCertificateConfig = ".\certbot\conf\root\rootCertificateConfig.cnf"
    $crt = "$confFolder\$subDomain.crt"
    $csr = "$confFolder\$subDomain.csr"
    $key = "$confFolder\$subDomain.key"

    New-Item -Path $confFolder -ItemType Directory -Force

    if (-Not (Test-Path -Path $crt -PathType Leaf)) {
        $openSslReq = Start-Process openssl -ArgumentList "req -new -sha256 -nodes -out $csr -newkey rsa:2048 -keyout $key -config $rootCertificateConfig" -NoNewWindow -Wait -PassThru
        $openSslReq.WaitForExit()

        $domainConfig = "$confFolder\domainCertificateConfig.cfg"

        if (-Not (Test-Path -Path $domainConfig -PathType Leaf)) {
            $exampleDomainConfig = ".\certbot\conf\root\domainCertificateConfig.cfg.example"

            Copy-Item $exampleDomainConfig $domainConfig
            ((Get-Content -path $domainConfig -Raw) -replace '{SUBDOMAINNAME}', $subDomain) | Set-Content -Path $domainConfig
        }

        $rootSSLCrt = ".\certbot\conf\root\rootSSL.crt"
        $rootSSLKey = ".\certbot\conf\root\rootSSL.key"

        $openSslX509 = Start-Process openssl -ArgumentList "x509 -req -in $csr -CA $rootSSLCrt -CAkey $rootSSLKey -CAcreateserial -out $crt -sha256 -extfile $domainConfig" -NoNewWindow -Wait -PassThru
        $openSslX509.WaitForExit()
    }

    $newConfig = createHostConfig($subDomain)
    ((Get-Content -path $newConfig -Raw) -replace '#', '') | Set-Content -Path $newConfig

    $notepad = Start-Process notepad++ -ArgumentList $newConfig -Wait -PassThru
    $notepad.WaitForExit()

    docker-compose restart
}

function global:rootCertificate {
    $rootSSLKey = ".\certbot\conf\root\rootSSL.key"
    $sslParams = ".\certbot\conf\ssl-dhparams.pem"

    if (-Not (Test-Path -Path $rootSSLKey -PathType Leaf) -Or -Not (Test-Path -Path $sslParams -PathType Leaf))
    {
        Write-Verbose -Message "No $rootSSLKey or $sslParams file found. Generating a root certificate" -Verbose

        & createHostConfig("auth.dev.phlow.com")

        $dockerCompose = Start-Process docker-compose -ArgumentList "up -d --build" -NoNewWindow -Wait -PassThru
        $dockerCompose.WaitForExit()

        Write-Host -NoNewLine 'Run in the command line .\letsencrypt.sh -d auth.dev.phlow.com -e sergey@phlow.com Then press any key to continue...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

        $rootSSLCrt = ".\certbot\conf\root\rootSSL.crt"
        $rootCertificateConfig = ".\certbot\conf\root\rootCertificateConfig.cnf"

        $openSslGenrsa = Start-Process openssl -ArgumentList "genrsa -des3 -out $rootSSLKey 2048" -NoNewWindow -Wait -PassThru
        $openSslGenrsa.WaitForExit()

        $openSslReq = Start-Process openssl -ArgumentList "req -x509 -sha256 -days 1100 -key $rootSSLKey -out $rootSSLCrt -config $rootCertificateConfig" -NoNewWindow -Wait -PassThru
        $openSslReq.WaitForExit()
    }
}

function createHostConfig([string]$subDomain) {
    $arraySubDomain = $subDomain.Split(".")
    [array]::Reverse($arraySubDomain)
    $ofs = "."
    $conf = ".\proxy\hosts\$arraySubDomain.conf"

    if (-Not (Test-Path -Path $conf -PathType Leaf)) {
        Write-Verbose -Message "No $conf file found. Creating." -Verbose

        $exampleConfig = ".\proxy\hosts\default.443.conf.example"

        Copy-Item $exampleConfig $conf
        ((Get-Content -path $conf -Raw) -replace '{HOSTNAME}', $subDomain) | Set-Content -Path $conf
    }

    return $conf
}