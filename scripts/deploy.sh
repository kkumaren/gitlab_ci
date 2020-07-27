#!/bin/bash

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RESET='\033[0m'

CI_COMMIT=$1
DIRECTORY_TIME=`date "+%Y%m%d%H%M%S"`
DIRECTORY="$DIRECTORY_TIME-$CI_COMMIT"
ROOT_DIRECTORY=$(pwd)
SITE_DIRECTORY=$(pwd)/current
SITE_DIRECTORY_REAL=$(pwd)/releases/$DIRECTORY
declare -a FILE_EXTENSION=(php txt)

declare -a FILE_EXTENSION=("php" "txt" "yml")

#################################################################
# Initializing some variables.
#################################################################

if [ -d "/gitlab-files/src" ]
then
  SITE_DIRECTORY=$(pwd)/current/src
  SITE_DIRECTORY_REAL=$(pwd)/releases/$DIRECTORY/src
fi

#################################################################
# Function to check server installation before running deploy script.
#################################################################
installation_check () {
  echo "Checking server installation"
}

#################################################################
# Function to update shared directory.
#################################################################
update_shared_directory () {
  echo "Updating shared directory."

  RSYNC_EXCLUDE=$SITE_DIRECTORY_REAL/.rsync-exclude
  if [ -f "$RSYNC_EXCLUDE" ]; then
    while IFS= read -r LINE
    do
      cd $ROOT_DIRECTORY/shared
      CURRENT_EXCLUDE_PATH=""
      EXCLUDE_PATHS=$(echo $LINE | tr "/" "\n")
      for EXCLUDE_PATH in $EXCLUDE_PATHS
      do
        EXTENSION=$(echo "${EXCLUDE_PATH##*.}")
        if echo ${FILE_EXTENSION[@]} | grep -qw $EXTENSION; then
          if [ ! -f "$EXCLUDE_PATH" ]; then
            if [ -f "$SITE_DIRECTORY_REAL/$CURRENT_EXCLUDE_PATH/example.$EXCLUDE_PATH" ]; then
              cp $SITE_DIRECTORY_REAL/$CURRENT_EXCLUDE_PATH/example.$EXCLUDE_PATH $EXCLUDE_PATH
            fi
          fi
        else
          mkdir -p $EXCLUDE_PATH
          if [ "$CURRENT_EXCLUDE_PATH" == "" ];then
            CURRENT_EXCLUDE_PATH="$EXCLUDE_PATH"
          else
            CURRENT_EXCLUDE_PATH="$CURRENT_EXCLUDE_PATH/$EXCLUDE_PATH"
          fi
          cd $EXCLUDE_PATH
        fi
      done
      if [ ! -d $SITE_DIRECTORY_REAL/$LINE ] || [ ! -f $SITE_DIRECTORY_REAL/$LINE ]; then
        ln -s $ROOT_DIRECTORY/shared/$LINE $SITE_DIRECTORY_REAL/$LINE
      fi
    done < "$RSYNC_EXCLUDE"
  fi

}

echo "Deploying site to remote server."

#################################################################
# Prepare environment for deployment.
#################################################################

# Create missing directory if they do no exists.
mkdir -p releases shared database current

# Check if release already exists. Use to determine if we are making a new deployment or re-deploying or revert to a previous release.
cd $ROOT_DIRECTORY/releases
EXISTING_DIRECTORY=$(find . -maxdepth 1 -name "*-$CI_COMMIT" -type d)
EXISTING_DIRECTORY=${EXISTING_DIRECTORY#*/}
if [ "$EXISTING_DIRECTORY" == "" ]; then
  EXISTING_DIRECTORY=false
fi

# Get the last release directory name
cd $ROOT_DIRECTORY/releases
if [ ! "$(ls -A .)" ]; then
  PREVIOUS_DIRECTORY=false
else
  #PREVIOUS_DIRECTORY=$(ls -d * | tail -1)
  PREVIOUS_DIRECTORY=$(ls --ignore $EXISTING_DIRECTORY | tail -1)
fi

cd $ROOT_DIRECTORY
if [ EXISTING_DIRECTORY ] && [ -d "releases/$EXISTING_DIRECTORY" ]; then
  echo ""
  echo "[SUCCESS] Release found on remote server."
  echo ""
  cd $ROOT_DIRECTORY/releases
  if [ $(ls -d * | tail -1) == $EXISTING_DIRECTORY ]; then
    echo "================================================================"
    echo "Redeploying to server."
    echo "================================================================"

    if [ -f "$ROOT_DIRECTORY/database/$PREVIOUS_DIRECTORY.sql" ]; then
        echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} Related database backup found $PREVIOUS_DIRECTORY.sql"
    else
      echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} No backup database found $PREVIOUS_DIRECTORY.sql"
    fi

    cd $SITE_DIRECTORY
    if [ $(drush status bootstrap | grep -c "Successful") == '1' ]; then
      drush sset system.maintenance_mode TRUE
    fi

    cd $ROOT_DIRECTORY
    rm -rf releases/$EXISTING_DIRECTORY
    mv gitlab-files releases/$DIRECTORY
    update_shared_directory

    cd $ROOT_DIRECTORY
    rm -rf current
    ln -s releases/$DIRECTORY current

    cd $SITE_DIRECTORY
    if [ $(drush status bootstrap | grep -c "Successful") == '1' ]; then
      if [ -f "$ROOT_DIRECTORY/database/$PREVIOUS_DIRECTORY.sql" ]; then
        drush sql-drop --yes
        drush sql-cli < $ROOT_DIRECTORY/database/$PREVIOUS_DIRECTORY.sql
      fi
      cd $SITE_DIRECTORY
      drush cr
      drush updb
      drush cim -y
      drush cr
      drush sset system.maintenance_mode FALSE
    else
      echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} Fail to execute drush commands."
    fi


  else
    echo "================================================================"
    echo "Reverting to the previous version."
    echo "================================================================"
    cd $ROOT_DIRECTORY
    if [ -f "database/$EXISTING_DIRECTORY.sql" ]; then
        echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} Backup database found."
    else
      echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} Backup database not found."
      exit 1
    fi

    cd $SITE_DIRECTORY
    if [ $(drush status bootstrap | grep -c "Successful") == '1' ]; then
      drush sset system.maintenance_mode TRUE
      drush cr
      # Backup database before update.
      drush sql-dump --result-file=$ROOT_DIRECTORY/database/$PREVIOUS_DIRECTORY.sql
    fi
    cd $ROOT_DIRECTORY
    mv releases/$EXISTING_DIRECTORY releases/$DIRECTORY
    mv database/$EXISTING_DIRECTORY.sql database/$DIRECTORY.sql

    cd $ROOT_DIRECTORY
    rm -rf current
    ln -s releases/$DIRECTORY current

    cd $SITE_DIRECTORY
    drush sql-drop --yes
    drush sql-cli < $ROOT_DIRECTORY/database/$DIRECTORY.sql

    drush cr
    drush sset system.maintenance_mode FALSE
  fi
else
  echo "================================================================"
  echo "Deploying new code to server."
  echo "================================================================"
  cd $ROOT_DIRECTORY
  mv gitlab-files releases/$DIRECTORY

  # Updating shared directory.
  update_shared_directory

  cd $SITE_DIRECTORY
  if [ $(drush status bootstrap | grep -c "Successful") == '1' ]; then
    drush sset system.maintenance_mode TRUE
    drush cr
    if [ $PREVIOUS_DIRECTORY ]; then
     #drush sql-dump --result-file=$ROOT_DIRECTORY/database/$DATABASE_BACKUP_DIR/dump.sql --gzip
     drush sql-dump --result-file=$ROOT_DIRECTORY/database/$PREVIOUS_DIRECTORY.sql
    fi

    #php -r 'function_exists("apc_clear_cache") ? apc_clear_cache() : null;'
    drush cr
    drush updb
    drush cim -y
    drush cr
    drush sset system.maintenance_mode FALSE
  fi

  cd $ROOT_DIRECTORY
  rm -rf current
  ln -s releases/$DIRECTORY current
fi

