# powershell 5
1. Copy Microsoft.PowerShell_profile.ps1 file to C:\Users\%username%\Documents\WindowsPowerShell
2. Run Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted and restart your machine
3. Add an environment variable with SSH key pathphrase called `PhlowSSHPathPhrase`

# PowerShell 7
1. Create a symlink `mklink c:\Users\user\Documents\PowerShell\Microsoft.PowerShell_profile.ps1 d:\WORK\powershell\Microsoft.PowerShell_profile.ps1`
2. Add an environment variable with SSH key pathphrase called `PhlowSSHPathPhrase`

# Usage
1. up
2. update
3. install
4. tag
5. newTag
6. tagClear
7. flush
8. sshtest
9. sshprod