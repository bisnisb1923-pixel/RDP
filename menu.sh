#!/bin/bash

while true; do
    clear
    echo "=============================="
    echo "    AUTO RDP SETUP MENU       "
    echo "=============================="
    echo " [1] Otomatis Buat & Push RDP ke GitHub"
    echo " [2] Keluar"
    echo "=============================="
    read -p "Pilih menu [1-2]: " pilihan

    case $pilihan in
        1)
            echo "=== Konfigurasi Otomatis RDP ==="
            read -p "Masukkan Username GitHub Anda: " gh_user
            read -p "Masukkan Nama Repository (misal: my-rdp): " gh_repo
            read -p "Masukkan Personal Access Token (PAT) GitHub: " gh_token

            echo "Membuat struktur folder workflow..."
            mkdir -p .github/workflows

            echo "Membuat file rdp.yml..."
            cat << 'EOF' > .github/workflows/rdp.yml
name: secure-rdp

on:
  workflow_dispatch:

jobs:
  secure-rdp:
    runs-on: windows-latest
    timeout-minutes: 3600

    steps:
      - name: Configure Core RDP Settings
        run: |
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value 0 -Force
          netsh advfirewall firewall delete rule name="RDP-Tailscale"
          netsh advfirewall firewall add rule name="RDP-Tailscale" dir=in action=allow protocol=TCP localport=3389
          Restart-Service -Name TermService -Force

      - name: Create RDP User with Secure Password
        run: |
          $password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
          $securePass = ConvertTo-SecureString $password -AsPlainText -Force
          New-LocalUser -Name "RDP" -Password $securePass -AccountNeverExpires
          Add-LocalGroupMember -Group "Administrators" -Member "RDP"
          Add-LocalGroupMember -Group "Remote Desktop Users" -Member "RDP"
          echo "RDP_CREDS=User: RDP | Password: $password" >> $env:GITHUB_ENV

      - name: Install Tailscale
        run: |
          $installerPath = "$env:TEMP\tailscale.msi"
          Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-1.82.0-amd64.msi" -OutFile $installerPath
          Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait
          Remove-Item $installerPath -Force

      - name: Establish Tailscale Connection
        run: |
          & "$env:ProgramFiles\Tailscale\tailscale.exe" up --authkey=${{ secrets.TAILSCALE_AUTH_KEY }} --hostname=gh-runner-$env:GITHUB_RUN_ID
          $tsIP = $null
          while (-not $tsIP) {
              $tsIP = & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
              Start-Sleep -Seconds 3
          }
          echo "TAILSCALE_IP=$tsIP" >> $env:GITHUB_ENV

      - name: Maintain Connection
        run: |
          Write-Host "Address: $env:TAILSCALE_IP"
          while ($true) { Start-Sleep -Seconds 300 }
EOF

            echo "Menginisialisasi Git dan melakukan Push ke GitHub..."
            git init
            git branch -M main
            git remote remove origin 2>/dev/null
            git remote add origin https://$gh_token@github.com/$gh_user/$gh_repo.git
            
            git add .
            git commit -m "Auto setup RDP workflow"
            git push -u origin main --force

            echo ""
            echo "Berhasil! Repository dan file workflow telah di-push."
            echo "Silakan buka GitHub Anda, masukkan secret TAILSCALE_AUTH_KEY, lalu jalankan (trigger) workflow secara manual di tab Actions."
            read -p "Tekan Enter untuk kembali ke menu..."
            ;;
        2)
            echo "Keluar..."
            exit 0
            ;;
        *)
            echo "Pilihan tidak valid!"
            sleep 2
            ;;
    esac
done

