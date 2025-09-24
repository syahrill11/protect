#!/bin/bash

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"
BOLD="\033[1m"
VERSION="1.4"

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║         SYAH Protect + Panel Builder                 ║"
echo "║                    Version $VERSION                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}[1]${RESET} Pasang Protect & Build Panel"
echo -e "${YELLOW}[2]${RESET} Restore dari Backup & Build Panel"
echo -e "${YELLOW}[3]${RESET} Pasang Protect Admin"
read -p "$(echo -e "${CYAN}Pilih opsi [1/2/3]: ${RESET}")" OPSI

CONTROLLER_USER="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
SERVICE_SERVER="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
CONTROLLER_FILE="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/FileController.php"

if [ "$OPSI" = "1" ]; then
    read -p "$(echo -e "${CYAN}Masukkan User ID Admin Utama (contoh: 1): ${RESET}")" ADMIN_ID

    # === PROTECT DELETE USER ===
    echo -e "${YELLOW}➤ Menambahkan Protect Delete User...${RESET}"
    [ ! -f "$CONTROLLER_USER" ] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && exit 1
    cp "$CONTROLLER_USER" "${CONTROLLER_USER}.bak"

    awk -v admin_id="$ADMIN_ID" '
    /public function delete\(Request \$request, User \$user\): RedirectResponse/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        if (\$request->user()->id !== " admin_id ") {";
        print "            throw new DisplayException(\"Anda Bukan Lah Admin Utama. Tidak Bisa Delete User (SYAH Protect V'"$VERSION"')\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "${CONTROLLER_USER}.bak" > "$CONTROLLER_USER"
    echo -e "${GREEN}✔ Protect UserController selesai.${RESET}"

    # === PROTECT DELETE SERVER ===
    echo -e "${YELLOW}➤ Menambahkan Protect Delete Server...${RESET}"
    [ ! -f "$SERVICE_SERVER" ] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && exit 1
    cp "$SERVICE_SERVER" "${SERVICE_SERVER}.bak"

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
' "$SERVICE_SERVER" > "$SERVICE_SERVER.tmp" && mv "$SERVICE_SERVER.tmp" "$SERVICE_SERVER"

    awk -v admin_id="$ADMIN_ID" '
    /public function handle\(Server \$server\): void/ { print; in_func = 1; next; }
    in_func == 1 && /^\s*{/ {
        print;
        print "        \$user = Auth::user();";
        print "        if (\$user && \$user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"Anda Bukan Lah Admin Utama. Tidak Bisa Delete Server (SYAH Protect V'"$VERSION"')\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "$SERVICE_SERVER" > "${SERVICE_SERVER}.patched" && mv "${SERVICE_SERVER}.patched" "$SERVICE_SERVER"
    echo -e "${GREEN}✔ Protect ServerDeletionService selesai.${RESET}"

    # === PROTECT FILE UPLOAD/DOWNLOAD ===
    echo -e "${YELLOW}➤ Menambahkan Protect File Upload/Download...${RESET}"
    [ ! -f "$CONTROLLER_FILE" ] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && exit 1
    cp "$CONTROLLER_FILE" "${CONTROLLER_FILE}.bak"

    awk -v admin_id="$ADMIN_ID" '
    BEGIN { inserted_use=0; in_func=0; }
    /^namespace / {
        print;
        if (!inserted_use) {
            print "use Illuminate\\Support\\Facades\\Auth;";
            print "use Pterodactyl\\Exceptions\\DisplayException;";
            inserted_use=1;
        }
        next;
    }
    /public function download\(.*\)/ { print; in_func=1; next; }
    in_func==1 && /^\s*{/ {
        print;
        print "        \$user = Auth::user();";
        print "        if (!\$user || \$user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"Anda Bukan Lah Admin Utama. Tidak Bisa Download File (SYAH Protect V'"$VERSION"')\");";
        print "        }";
        in_func=0; next;
    }
    /public function upload\(.*\)/ { print; in_func=2; next; }
    in_func==2 && /^\s*{/ {
        print;
        print "        \$user = Auth::user();";
        print "        if (!\$user || \$user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"Anda Bukan Lah Admin Utama. Tidak Bisa Upload File (SYAH Protect V'"$VERSION"')\");";
        print "        }";
        in_func=0; next;
    }
    { print; }
    ' "${CONTROLLER_FILE}.bak" > "$CONTROLLER_FILE"
    echo -e "${GREEN}✔ Protect FileController (Upload/Download) selesai.${RESET}"

    # === BUILD PANEL ===
    echo -e "${YELLOW}➤ Install Node.js 16 dan build frontend panel...${RESET}"
    sudo apt-get update -y >/dev/null
    sudo apt-get remove nodejs -y >/dev/null
    curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash - >/dev/null
    sudo apt-get install nodejs -y >/dev/null

    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal cd ke panel.${RESET}"; exit 1; }

    npm i -g yarn >/dev/null
    yarn add cross-env >/dev/null
    yarn build:production --progress

    echo -e "${GREEN}🎉 Protect V$VERSION berhasil dipasang & Panel dibuild.${RESET}"

elif [ "$OPSI" = "2" ]; then
    echo -e "${YELLOW}♻ Memulihkan dari backup...${RESET}"
    [ -f "${CONTROLLER_USER}.bak" ] && cp "${CONTROLLER_USER}.bak" "$CONTROLLER_USER" && \
        echo -e "${GREEN}✔ UserController dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup UserController tidak ditemukan.${RESET}"

    [ -f "${SERVICE_SERVER}.bak" ] && cp "${SERVICE_SERVER}.bak" "$SERVICE_SERVER" && \
        echo -e "${GREEN}✔ ServerDeletionService dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup ServerDeletionService tidak ditemukan.${RESET}"

    [ -f "${CONTROLLER_FILE}.bak" ] && cp "${CONTROLLER_FILE}.bak" "$CONTROLLER_FILE" && \
        echo -e "${GREEN}✔ FileController dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup FileController tidak ditemukan.${RESET}"

    echo -e "${YELLOW}➤ Build ulang panel...${RESET}"
    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal cd ke panel.${RESET}"; exit 1; }
    yarn build:production --progress

    echo -e "${GREEN}✅ Restore & build selesai.${RESET}"

elif [ "$OPSI" = "3" ]; then
    bash <(curl -s https://raw.githubusercontent.com/syahrill11/protect.js/main/ireng.sh)

else
    echo -e "${RED}❌ Opsi tidak valid.${RESET}"
fi
