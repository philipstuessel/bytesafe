#!/bin/zsh
alias bs="bytesafe"

bs_MAIN_FOLDER="${JAP_FOLDER}plugins/packages/bytesafe/config/"
bs_CONFIG_FILE="${bs_MAIN_FOLDER}bytesafe.config.json"
bs_STATUS_FILE="${bs_MAIN_FOLDER}bytesafe.status.json"

bytesafe() {
    if [[ "$1" == "v" || "$1" == "-v" ]];then
        echo -e "${LIGHT_RED}ByteSafe ${NC}${BRED} SQL ${NC}"
        echo -e "${BOLD}v0.1.0${NC}"
        echo -e "${YELLOW}JAP plugin${NC}"
    fi

    if [[ "$1" == "e" || "$1" == "edit" ]];then
            edit $bs_CONFIG_FILE
    fi

    if [[ "$1" == "status" || "$1" == "info" ]];then
        bakupFolder=$(jq -r '.bakupFolder' $bs_CONFIG_FILE)
        lastTime=$(jq -r '.lastTime' $bs_STATUS_FILE)
        saveBak=$(jq -r '.saveBak' $bs_CONFIG_FILE)
        BACKUP_BASE_DIR="$HOME/bakup-sql/"
        if [[ ! $bakupFolder == "/bakup-sql" ]];then
            BACKUP_BASE_DIR=$bakupFolder
        fi
        if [[ ! -e $BACKUP_BASE_DIR ]];then
            echo -e "${RED}Error: folder not found${NC} $BACKUP_BASE_DIR" 
            return
        fi
        size=$(du -sh $BACKUP_BASE_DIR | awk '{print $1}')
        folderhm=$(find $BACKUP_BASE_DIR -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        echo ""
        echo -e "${LIGHT_RED}ByteSafe ${NC}"
        echo ""
        echo -e "${BOLD}Last Bakup${NC}:      ${lastTime}"
        echo -e "${BOLD}how many${NC}:        ${folderhm}/${saveBak}"
        echo -e "${BOLD}size${NC}:            ${size}"
        echo -e "${BOLD}Bak folder${NC}:      ${BACKUP_BASE_DIR}"
        echo ""
    fi

    if [[ "$1" == "list" ]];then
        if [[ ! -e $BACKUP_BASE_DIR ]];then
            echo -e "${RED}Error: folder not found${NC} $BACKUP_BASE_DIR" 
            return
        fi
        folderhm=$(find $BACKUP_BASE_DIR -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        if [[ $folderhm == "0" ]];then
            echo -e "${RED}Error: no backups found${NC}"
        else
            ls -d $BACKUP_BASE_DIR/*/ | xargs -n 1 basename
        fi
    fi

    if [[ "$1" == "bak" || "$1" == "bakup" ]];then
        bakupFolder=$(jq -r '.bakupFolder' $bs_CONFIG_FILE)
        saveBak=$(jq -r '.saveBak' $bs_CONFIG_FILE)
        dbuser=$(jq -r '.dbUser.user' $bs_CONFIG_FILE)
        dbpw=$(jq -r '.dbUser.pw' $bs_CONFIG_FILE)

        mysql -u "$dbuser" -p"$dbpw" -e "EXIT" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${LIGHT_RED}Connection failed${NC}: Incorrect username or password."
            return
        fi

        BACKUP_BASE_DIR="$HOME/bakup-sql"
        if [[ $bakupFolder == "/bakup-sql" ]];then
            mkdir -p "$HOME/bakup-sql"
        else
            mkdir -p "$bakupFolder"
            BACKUP_BASE_DIR=$bakupFolder
        fi

        echo "Starting the database backup process..."
        echo ""
        DATE_SUBDIR=$(date +'%Y-%m-%d')
        BACKUP_DIR="${BACKUP_BASE_DIR}/${DATE_SUBDIR}"
        mkdir -p "$BACKUP_DIR"

        databases=$(mysql -u $dbuser -p$dbpw -N -e 'SHOW DATABASES')
        valid_databases=$(echo "$databases" | grep -v -E "^(information_schema|mysql|performance_schema|sys)$")
        total_databases=$(echo "$valid_databases" | wc -l)
        current=0

        echo "$valid_databases" | while read -r dbname; do
            current=$((current + 1))
            printf "\r[%2d/%2d] ${LIGHT_YELLOW}Backing up database${NC}: %-30s" "$current" "$total_databases" "$dbname"
            backup_file="$BACKUP_DIR/${dbname}.sql"
    
            [ -f "$backup_file" ] && rm "$backup_file"
            if mysqldump -u "$dbuser" -p"$dbpw" --complete-insert --routines --triggers --single-transaction "$dbname" > "$backup_file"; then
                printf "\r[%2d/%2d] ${LIGHT_GREEN}Backup completed${NC}: %-30s\n" "$current" "$total_databases" "$dbname"
            else
                printf "\r[%2d/%2d] ${LIGHT_RED}Error backing up database${NC}: %-30s\n" "$current" "$total_databases" "$dbname"
            fi
        done
        echo "";
        new_time=$(date "+%d.%m.%Y %H:%M:%S")
        temp_folder="${tempf}temp.json"
        jq --arg time "$new_time" '.lastTime = $time' $bs_STATUS_FILE > $temp_folder && mv $temp_folder $bs_STATUS_FILE
        echo "All backups completed."
    fi

    if [[ "$1" == "restore" ]];then
        restoreDIR=""
        bakupFolder=$(jq -r '.bakupFolder' $bs_CONFIG_FILE)
        BACKUP_BASE_DIR="$HOME/bakup-sql"
        if [[ ! $bakupFolder == "/bakup-sql" ]];then
            BACKUP_BASE_DIR=$bakupFolder
        fi
        if [[ ! -e $BACKUP_BASE_DIR ]];then
            echo -e "${RED}Error: folder not found${NC} $BACKUP_BASE_DIR" 
            return
        fi
        if [[ "$2" = "last" ]];then
            latest_folder=$(ls -d ${BACKUP_BASE_DIR}/*/ | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}/$' | sort | tail -n 1)
            restoreDIR=$latest_folder
        else
            selectfolder="$2"
            if [[ -e "$BACKUP_BASE_DIR/$selectfolder" ]];then
                    restoreDIR="$BACKUP_BASE_DIR/$selectfolder"
                else
                    echo -e "${RED}Error: bak not found${NC} $BACKUP_BASE_DIR/$selectfolder"
                    return
            fi
        fi    
        echo "select: ${restoreDIR}"
        echo -n "Are you sure you want to overwrite the database? (y/n) : "
        read -r answer
        if [[ ! "$answer" == [Yy] ]]; then
            echo "Operation cancelled."
            return
        fi
        echo ""
        dbuser=$(jq -r '.dbUser.user' $bs_CONFIG_FILE)
        dbpw=$(jq -r '.dbUser.pw' $bs_CONFIG_FILE)
        total_databases=$(ls -1 "$restoreDIR"/*.sql 2>/dev/null | wc -l)
        if [ "$total_databases" -eq 0 ]; then
            echo "No SQL files found in directory $restoreDIR."
            return
        fi
        current=0

        for file in "$restoreDIR"/*.sql; do
            [ -e "$file" ] || continue
            ((current++))
            dbname="${file##*/}"
            dbname="${dbname%.sql}"
            printf "\r[%2d/%2d] ${LIGHT_YELLOW}Import${NC}... : %-30s" "$current" "$total_databases" "$dbname"
            mysql -u "$dbuser" -p"$dbpw" -e "DROP DATABASE IF EXISTS \`$dbname\`;"
            mysql -u "$dbuser" -p"$dbpw" -e "CREATE DATABASE \`$dbname\`;"
            mysql -u "$dbuser" -p"$dbpw" "$dbname" < "$file"
            printf "\r[%2d/%2d] ${LIGHT_GREEN}Import completed${NC}: %-30s\n" "$current" "$total_databases" "$dbname"
        done
        echo ""
        echo "All backups have been successfully imported."
    fi
}