#!/bin/bash

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"
BOLD="\033[1m"
VERSION="1.5"

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║            SYAH PROTECT SYSTEM v$VERSION              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}[1]${RESET} Pasang Protect & Build Panel"
echo -e "${YELLOW}[2]${RESET} Restore dari Backup & Build Panel"
echo -e "${YELLOW}[3]${RESET} Pasang Protect Admin"
read -p "$(echo -e "${CYAN}Pilih opsi [1/2/3]: ${RESET}")" OPSI

CONTROLLER_USER="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
SERVICE_SERVER="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
FILE_CONTROLLER="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/FileController.php"

if [ "$OPSI" = "1" ]; then
    read -p "$(echo -e "${CYAN}Masukkan User ID Admin Utama (contoh: 1): ${RESET}")" ADMIN_ID

    echo -e "${YELLOW}➤ Menambahkan Protect Delete User...${RESET}"
    [ ! -f "$CONTROLLER_USER" ] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && exit 1
    cp "$CONTROLLER_USER" "${CONTROLLER_USER}.bak"

    awk -v admin_id="$ADMIN_ID" '
    /public function delete\(Request \$request, User \$user\): RedirectResponse/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        if ($request->user()->id !== " admin_id ") {";
        print "            throw new DisplayException(\"LU NGAPAIN TOLOL? PROTECT BY SYAH v'"$VERSION"'\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "${CONTROLLER_USER}.bak" > "$CONTROLLER_USER"
    echo -e "${GREEN}✔ Protect UserController selesai.${RESET}"

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
    /public function handle\(Server \$server\): void/ {
        print; in_func = 1; next;
    }
    in_func == 1 && /^\s*{/ {
        print;
        print "        $user = Auth::user();";
        print "        if ($user && $user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"Mau delet server orang lu bego? Protect by Syah v'"$VERSION"'\");";
        print "        }";
        in_func = 0; next;
    }
    { print }
    ' "$SERVICE_SERVER" > "${SERVICE_SERVER}.patched" && mv "${SERVICE_SERVER}.patched" "$SERVICE_SERVER"
    echo -e "${GREEN}✔ Protect ServerDeletionService selesai.${RESET}"

    echo -e "${YELLOW}➤ Menambahkan Protect Download File...${RESET}"
    [ ! -f "$FILE_CONTROLLER" ] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && exit 1
    cp "$FILE_CONTROLLER" "${FILE_CONTROLLER}.bak"

    awk '
BEGIN { added = 0 }
{
    print
    if (!added && $0 ~ /^namespace Pterodactyl\\Http\\Controllers\\Api\\Client\\Servers;/) {
        print "use Illuminate\\Support\\Facades\\Auth;"
        print "use Pterodactyl\\Exceptions\\DisplayException;"
        added = 1
    }
}
' "$FILE_CONTROLLER" > "$FILE_CONTROLLER.tmp" && mv "$FILE_CONTROLLER.tmp" "$FILE_CONTROLLER"

    awk -v admin_id="$ADMIN_ID" '
    /public function download\(Request \$request, string \$uuid\)/ {
        print; in_func = 1; next
    }
    in_func==1 && /^\s*{/ {
        print
        print "        $user = Auth::user();"
        print "        $server = $this->getServer($request, $uuid);"
        print "        if ($user && $user->id !== " admin_id " && $user->id !== $server->owner_id) {"
        print "            throw new DisplayException(\"Download file diblokir! Hanya admin utama & pemilik server yang boleh. Protect by Syah v'"$VERSION"'\");"
        print "        }"
        in_func=0; next
    }
    { print }
    ' "$FILE_CONTROLLER" > "${FILE_CONTROLLER}.patched" && mv "${FILE_CONTROLLER}.patched" "$FILE_CONTROLLER"
    echo -e "${GREEN}✔ Protect Download File selesai.${RESET}"

    echo -e "${YELLOW}➤ Install Node.js 16 dan build frontend panel...${RESET}"
    sudo apt-get update -y >/dev/null
    sudo apt-get remove nodejs -y >/dev/null
    curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash - >/dev/null
    sudo apt-get install nodejs -y >/dev/null

    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal ke direktori panel.${RESET}"; exit 1; }

    npm i -g yarn >/dev/null
    yarn add cross-env >/dev/null
    yarn build:production --progress

    echo -e "${GREEN}🎉 Protect V$VERSION & Build Panel berhasil dipasang.${RESET}"

elif [ "$OPSI" = "2" ]; then
    echo -e "${YELLOW}♻ Memulihkan dari backup...${RESET}"
    [ -f "${CONTROLLER_USER}.bak" ] && cp "${CONTROLLER_USER}.bak" "$CONTROLLER_USER" && \
        echo -e "${GREEN}✔ UserController dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup UserController tidak ditemukan.${RESET}"

    [ -f "${SERVICE_SERVER}.bak" ] && cp "${SERVICE_SERVER}.bak" "$SERVICE_SERVER" && \
        echo -e "${GREEN}✔ ServerDeletionService dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup ServerDeletionService tidak ditemukan.${RESET}"

    [ -f "${FILE_CONTROLLER}.bak" ] && cp "${FILE_CONTROLLER}.bak" "$FILE_CONTROLLER" && \
        echo -e "${GREEN}✔ FileController dipulihkan.${RESET}" || \
        echo -e "${RED}⚠ Backup FileController tidak ditemukan.${RESET}"

    echo -e "${YELLOW}➤ Build ulang panel...${RESET}"
    cd /var/www/pterodactyl || { echo -e "${RED}❌ Gagal ke direktori panel.${RESET}"; exit 1; }
    yarn build:production --progress

    echo -e "${GREEN}✅ Restore & build selesai.${RESET}"

elif [ "$OPSI" = "3" ]; then
    bash <(curl -s https://raw.githubusercontent.com/syahrill11/protect.js/main/ireng.sh)

else
    echo -e "${RED}❌ Opsi tidak valid.${RESET}"
fi
