#!/bin/bash

set -e  # Exit on any error

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"
BOLD="\033[1m"
VERSION="1.4"  # Update versi

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          Protect + Panel Builder                     ║"
echo "║                    Version $VERSION                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}[1]${RESET} Pasang Protect & Build Panel"
echo -e "${YELLOW}[2]${RESET} Restore dari Backup & Build Panel"
echo -e "${YELLOW}[3]${RESET} Pasang Protect Admin"
read -p "$(echo -e "${CYAN}Pilih opsi [1/2/3]: ${RESET}")" OPSI

CONTROLLER_USER="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
SERVICE_SERVER="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"

# Fungsi helper: Cek file exists dan backup
backup_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ File $file tidak ditemukan.${RESET}"
        exit 1
    fi
    cp "$file" "${file}.bak"
    echo -e "${GREEN}✔ Backup $file dibuat.${RESET}"
}

# Fungsi helper: Syntax check PHP
check_php_syntax() {
    local file="$1"
    if ! php -l "$file" >/dev/null 2>&1; then
        echo -e "${RED}❌ Syntax error di $file setelah patch. Restore dari backup.${RESET}"
        cp "${file}.bak" "$file"
        exit 1
    fi
    echo -e "${GREEN}✔ Syntax PHP $file OK.${RESET}"
}

# Fungsi helper: Fix permission untuk web server
fix_permissions() {
    local file="$1"
    sudo chown www-data:www-data "$file"  # Asumsi Apache/Nginx user
    sudo chmod 644 "$file"
}

# Fungsi helper: Patch UserController (delete + update sekaligus, hindari overwrite)
patch_user_controller() {
    local file="$1"
    local admin_id="$2"
    local message="$3"  # Pesan custom untuk exception

    backup_file "$file"

    # Patch keduanya sequential: Delete dulu, lalu update dari file hasil delete
    # Patch delete
    awk -v admin_id="$admin_id" -v msg="$message" '
    /public function delete\$Request \$request, User \$user\$: RedirectResponse/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        if ($request->user()->id !== " admin_id " && $request->user()->id !== $user->id) {";
        print "            throw new \\Pterodactyl\\Exceptions\\DisplayException(\"" msg "\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "${file}.bak" > "$file.tmp1"

    # Patch update dari hasil patch delete
    awk -v admin_id="$admin_id" -v msg="$message" '
    /public function update\$User FormRequest \$request, User \$user\$: RedirectResponse/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        if ($request->user()->id !== " admin_id " && $request->user()->id !== $user->id) {";
        print "            throw new \\Pterodactyl\\Exceptions\\DisplayException(\"" msg "\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "$file.tmp1" > "$file"
    rm "$file.tmp1"

    check_php_syntax "$file"
    fix_permissions "$file"
    echo -e "${GREEN}✔ Patch UserController (delete + anti-edit) selesai.${RESET}"
}

if [ "$OPSI" = "1" ]; then
    read -p "$(echo -e "${CYAN}Masukkan User ID Admin Utama (numeric, contoh: 1): ${RESET}")" ADMIN_ID
    if ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ ADMIN_ID harus numeric.${RESET}"
        exit 1
    fi

    read -p "$(echo -e "${YELLOW}Konfirmasi pasang Protect (y/N)? ${RESET}")" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Dibatalkan.${RESET}"
        exit 0
    fi

    local_message="Akses Ditolak. Anda tidak bisa mengedit/menghapus user ini. Hanya Admin ID $ADMIN_ID atau pemilik yang boleh."  # Pesan netral, bisa ganti ke lucu

    echo -e "${YELLOW}➤ Menambahkan Protect Delete User & Anti Edit...${RESET}"
    patch_user_controller "$CONTROLLER_USER" "$ADMIN_ID" "$local_message"

    echo -e "${YELLOW}➤ Menambahkan Protect Delete Server...${RESET}"
    backup_file "$SERVICE_SERVER"

    # Patch use statements
    awk '
    BEGIN { added = 0 }
    {
        print
        if (!added && $0 ~ /^namespace Pterodactyl\\Services\\Servers;/) {
            print "use Illuminate\\Support\\Facades\\Auth;"
            print "use Pterodactyl\\Exceptions\\DisplayException;"
            added = 1
        }
    }
    END { if (!added) print "Warning: Namespace not found, manual import needed." }
    ' "$SERVICE_SERVER" > "$SERVICE_SERVER.tmp" && mv "$SERVICE_SERVER.tmp" "$SERVICE_SERVER"

    check_php_syntax "$SERVICE_SERVER"

    # Patch handle function
    local_server_msg="Akses Ditolak. Anda tidak bisa menghapus server ini. Hanya Admin ID $ADMIN_ID yang boleh."
    awk -v admin_id="$ADMIN_ID" -v msg="$local_server_msg" '
    /public function handle\$Server \$server\$: void/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        $user = Auth::user();";
        print "        if ($user && $user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"" msg "\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "$SERVICE_SERVER" > "${SERVICE_SERVER}.patched" && mv "${SERVICE_SERVER}.patched" "$SERVICE_SERVER"

    check_php_syntax "$SERVICE_SERVER"
    fix_permissions "$SERVICE_SERVER"
    echo -e "${GREEN}✔ Protect ServerDeletionService selesai.${RESET}"

    echo -e "${YELLOW}➤ Install Node.js 18 dan build frontend panel...${RESET}"
    sudo apt-get update -y
    sudo apt-get remove nodejs -y
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install nodejs -y

    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal ke direktori panel.${RESET}"; exit 1; }

    sudo npm i -g yarn  # Sudo untuk global install
    yarn add cross-env
    yarn build:production --progress

    echo -e "${GREEN}🎉 Protect V$VERSION & Build Panel berhasil dipasang.${RESET}"

elif [ "$OPSI" = "2" ]; then
    echo -e "${YELLOW}♻ Memulihkan dari backup...${RESET}"
    if [ -f "${CONTROLLER_USER}.bak" ]; then
        cp "${CONTROLLER_USER}.bak" "$CONTROLLER_USER"
        fix_permissions "$CONTROLLER_USER"
        echo -e "${GREEN}✔ UserController dipulihkan.${RESET}"
    else
        echo -e "${RED}⚠ Backup UserController tidak ditemukan.${RESET}"
    fi

    if [ -f "${SERVICE_SERVER}.bak" ]; then
        cp "${SERVICE_SERVER}.bak" "$SERVICE_SERVER"
        fix_permissions "$SERVICE_SERVER"
        echo -e "${GREEN}✔ ServerDeletionService dipulihkan.${RESET}"
    else
        echo -e "${RED}⚠ Backup ServerDeletionService tidak ditemukan.${RESET}"
    fi

    echo -e "${YELLOW}➤ Build ulang panel...${RESET}"
    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal ke direktori panel.${RESET}"; exit 1; }
    yarn build:production --progress

    echo -e "${GREEN}✅ Restore & build selesai.${RESET}"

elif [ "$OPSI" = "3" ]; then
    echo -e "${YELLOW}➤ Download dan jalankan Protect Admin...${RESET}"
    # Tambah verifikasi sederhana (opsional)
    if curl -s --head "https://raw.githubusercontent.com/syahrill11/protect.js/main/ireng.sh" | head -n 1 | grep -q "200 OK"; then
        bash <(curl -s https://raw.githubusercontent.com/syahrill11/protect.js/main/ireng.sh)
    else
        echo -e "${RED}❌ Gagal download Protect Admin.${RESET}"
        exit 1
    fi

else
    echo -e "${RED}❌ Opsi tidak valid.${RESET}"
    exit 1
fi

echo -e "${GREEN}Selesai! Restart panel: php artisan queue:restart && supervisorctl restart all.${RESET}"
