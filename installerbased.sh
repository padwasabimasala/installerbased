#!/bin/bash

#------------------------------------------------------------------------------
# INITIAL SETTINGS
#------------------------------------------------------------------------------
DEF_IFS="$IFS"
INSTALLED_GEMS=`gem list -l`


#------------------------------------------------------------------------------
# HELPER FUNCTIONS
#------------------------------------------------------------------------------

# Bash has very limited support for Array/Hash/Dict types so we create a few
# utilities for setting and getting projects and repositories
# http://linuxshellaccount.blogspot.com/2008/05/how-to-fake-associative-arrays-in-bash.html

declare -a PROJECT_NAMES
declare -a PROJECT_REPOS


function add_project {
  index=$(( ${#PROJECT_REPOS[*]} + 1))
  PROJECT_NAMES[$index]=$1
  PROJECT_REPOS[$index]=$2
}

function get_project {
  for (( i=1 ; i <= ${#PROJECT_NAMES[@]}; i++ )); do
    if [ $1 == "${PROJECT_NAMES[$i]}" ]; then
      echo -n "${PROJECT_REPOS[$i]}" 
    fi
  done
}

function list_projects {
  for proj in ${PROJECT_NAMES[*]}; do
    echo "- $proj"
  done
}

function bigecho {
  echo
  echo -e "\E[34m# $@\E[0m"
  echo
}

function run {
  cmd="$@"
  echo -e "\E[36m$cmd\E[0m"
  eval $cmd
  if [[ $? != 0 ]]; then
    echo -e "\E[31merror\E[0m"
  fi
  echo
}

function get_gem_name {
  # returns gem name portion of line (i.e. first word)
  # expects input like "mygem -v 1.2.3 --source http://..."
  echo $1 | cut -d' ' -f1
}

function get_gem_args {
  # returns gem args portion of line (i.e. all words after first)
  # expects input like "mygem -v 1.2.3 --source http://..."
  echo $1 | cut -d' ' -f2-
}

function get_gem_vers {
  # returns gem version portion of line (i.e. second word) and strips parens
  # expects input like mygem (1.2.3) or mygem --version 1.2.3 
  if [[ $1 =~ ' --version' ]]; then
    # Matches lines like
    # mygem --version 2.3.7 --source
    # mygem --version=2.3.8 --source
    portion_after_version_marker=$(echo ${1#*--version} | sed 's/=//g')
    vers=$(expr match "$portion_after_version_marker" '\([ 0-9.]*\)' | sed 's/ //g') 
    echo "$vers"
  elif [[ $1 =~ ' -v' ]]; then
    # Matches lines like
    # mygem -v2.3.4 --source
    # mygem -v 2.3.5 --source
    # mygem -v=2.3.6 --source
    portion_after_version_marker=$(echo ${1#*-v} | sed 's/=//g')
    vers=$(expr match "$portion_after_version_marker" '\([ 0-9.]*\)' | sed 's/ //g') 
    echo "$vers"
  else
    # Matches lines like
    # mygem (1.2.3)
    # mygem (1.2.4, 1.2.5)
    # mygem (1.2.6, 1.2.7, 1.2.8)
    portion_after_space_paren=$(echo ${1#* \(})
    vers=$(expr match "$portion_after_space_paren" '\([0-9.]*\)' | sed 's/=//g' | sed 's/,//g' | sed 's/)//g')
    echo $vers
  fi
  #echo $1 | cut -d' ' -f2 | sed 's/(//g' | sed 's/)//g'
}

function find_installed_gem {
  # returns matching line of local gem list if gem found
  # input ($1) expected to be line from required_gems in the format "<gemname> <gemargs>"
  #   e.g. supergem -r123 --source http://supergems.com/gems

  IFS=","
  gemname=$(get_gem_name $1)
  gemargs=$(get_gem_args $1)
  # find the gemname at the begining of a line followed by a space
  echo $INSTALLED_GEMS |grep "^$gemname "
}

function find_remote_gem {
  # returns matching line of remote gem list if gem found
  # input ($1) expected to be line from required_gems in the format "<gemname> <gemargs>"
  #   e.g. supergem -r123 --source http://supergems.com/gems

  IFS=$'\n'
  gemname=$(get_gem_name $1)
  gemargs=$(get_gem_args $1)
  # putting the cmd in a string was needed (for an unknown reason) to get the argument parsing right
  cmd="gem list -r '^$gemname\$' $gemargs" 
  # gems occur all on one line. replace space following closing paren with newline
  echo $(eval $cmd) | sed 's/) /)\n/g' | grep $gemname
}

function check_proj_name_for_repo {
  # The svn repo may be forced by appending to the repo name after a colon e.g.
  # PROJ2:http://svn.hostname.com/svn/...

  COLON_INDEX=$(expr match "$PROJ_NAME" '[A-Za-z0-9]*:')
  if [[ $COLON_INDEX != 0 ]]; then
    OVERRIDE_REPO=${PROJ_NAME:$COLON_INDEX:10000} # Hopefully no repo paths are longer than 100,000 chars
    PROJ_NAME=${PROJ_NAME:0:$(($COLON_INDEX - 1))}
  fi
}

function run_install_steps {
  if [[ -n $IB_TEST ]];then
    echo "INSTALL_ROOT: $INSTALL_ROOT"
    echo "PROJ_NAME: $PROJ_NAME"
    echo "PROJ_PATH: $PROJ_PATH"
    echo "PROJ_REPO: $PROJ_REPO"
    echo "INSTALL_STEPS: $1"
  else
    for step in $1; do
      eval ${INSTALL_STEPS[$step]}
    done
  fi
}


#------------------------------------------------------------------------------
# CONFIGURATION
#------------------------------------------------------------------------------

# Configure projects this installer will install. Project name first, svn repo second.
add_project PROJ2 http://svn.hostname.com/svn/mb/trunk/PROJ2
add_project PROJ1 http://svn.hostname.com/svn/mb/trunk/PROJ1

# NFS server-side mount locations
NFS_MNT_PRODUCTION=nfs1.hostname.com:/mediaproduction

DEF_INSTALL_ROOT=/var/www/apps
if [[ -n "$IB_ROOT" ]];then
  INSTALL_ROOT="$IB_ROOT"
else
  INSTALL_ROOT="$DEF_INSTALL_ROOT"
fi

NFS_SOURCES_ROOT=/media/production/sources
NFS_CLIENTS_ROOT=/media/production/clients


#------------------------------------------------------------------------------
# INSTALLER FUNCTIONS
#------------------------------------------------------------------------------

# each function will be assigned an index in INSTALL_STEPS
declare -a INSTALL_STEPS

function install_prerequisites {
  bigecho installing installer prerequisites
  run apt-get install -y subversion build-essential vim
}

function install_ruby_etal { 
  bigecho apt-get installing ruby and related packages
  #   Note that rake is not installed here because it is installed by rails
  #   installing rake via apt can cause versioning issues and other headaches!
  run apt-get install -y ruby ruby1.8-dev libopenssl-ruby rdoc irb 
}

function install_rubygems {
  # check for ruby gems
  which gem > /dev/null
  if [[ $? != 0 ]]; then
    bigecho installing rubygems from source 
    #   use --no-format-executable option to ensure binary is called "gem"
    run mkdir -p /usr/local/src # may already exist
    run cd /usr/local/src 
    run wget http://rubyforge.org/frs/download.php/57643/rubygems-1.3.4.tgz 
    run tar zxf rubygems-1.3.4.tgz
    run cd rubygems-1.3.4; ruby setup.rb install --no-format-executable
  else
    echo -n 'rubygems is already installed at '
    which gem
  fi
}

function install_rails {
  bigecho gem installing rails 2.2.2
  run gem install rails --no-rdoc --no-ri -v=2.2.2
}

function install_and_setup_nfs {
  bigecho creating nfs mounts
  if [[ `aptitude search nfs-common |grep ^i -c` != 0 ]]; then
    run apt-get -y install nfs-common 
  fi

  echo
  if [[ `grep -c $NFS_MNT_PRODUCTION /etc/fstab` != 0 ]]; then
    echo "/etc/fstab contains entry matching '$NFS_MNT_PRODUCTION'"
    echo "Not creating mount for $NFS_MNT_PRODUCTION" else
    run mkdir -p /media/production
    echo "$NFS_MNT_PRODUCTION /media/production nfs defaults 0 0" >> /etc/fstab
    run mount /media/production
  fi
}

function checkout_project {
  bigecho checking out $PROJ_NAME sources from svn
  # Check if project path already exists
  if [[ -e $PROJ_PATH ]]; then
    if [[ $FORCE != true ]]; then
      echo -n "$PROJ_PATH already exists. Do you wish to continue? [y/N] "
      read ANSWER
      echo
      if [[ $ANSWER != 'y' && $ANSWER != 'Y' ]];then
        echo installer quitting
        exit 0
      fi
    fi
    # TODO Allow some kind of option to svn switch?
    echo "Deleting $PROJ_PATH."
    rm -Rf $PROJ_PATH
  fi
  # create install dir
  run mkdir -p $INSTALL_ROOT; cd $INSTALL_ROOT 
  # check out source
  run svn co -q $PROJ_REPO $PROJ_NAME
}

function setup_project {
  bigecho settting up $PROJ_NAME
  run cd $PROJ_PATH
  # setup log files
  run touch log/development.log
  run chmod 0666 log/development.log
  run touch log/production.log
  run chmod 0666 log/production.log
  # chown all project files to developer
  run chown -R developer $PROJ_PATH
 
  script_name=setup.sh
  script_path=$PROJ_PATH/script/install/$script_name
  echo "checking for $script_path"
  if [[ -e $script_path ]]; then
    this_dir=`pwd`
    cd $PROJ_PATH
    run bash script/install/$script_name
    cd $this_dir
  else
    echo "$script_path not found."
  fi
}

function install_required_debs {
  bigecho installing debs from $PROJ_PATH/script/install/required_debs
  DEBS=$(cat $PROJ_PATH/script/install/required_debs)
  IFS=$'\n'
  for deb in $DEBS; do
    if [[ `echo $deb |grep -vc '^[[:space:]]*#'` == 1 ]]; then
      if [[ -n $deb ]]; then
        echo "installing deb $deb"
        run apt-get -y install "$deb"
      fi
    fi
  done
}

function install_required_gems {
  bigecho installing gems from $PROJ_PATH/script/install/required_gems
  GEMS=$(cat $PROJ_PATH/script/install/required_gems)
  IFS=$'\n'
  for ln in $GEMS; do
    if [[ `echo $ln |grep -vc '^[[:space:]]*#'` == 1 ]]; then #ln is not comment
      this_gem=$ln
      echo "installing gem $this_gem"

      installed_gem=$(find_installed_gem $this_gem)
      if [[ $installed_gem == '' ]]; then
        echo "gem not installed"
        run gem install --no-rdoc --no-ri $this_gem

      else # gem is already installed so check versions
        installed_vers=$(get_gem_vers $installed_gem) # may be multiple space seperated vers
        # get version number of this_gem if specified otherwise latest version
        this_ver=$(get_gem_vers $this_gem)
        if [[ $this_ver == '' || $this_ver == " " ]]; then
          this_ver=$(get_gem_vers $(find_remote_gem $this_gem))
        fi

        # check if gem already installed
        installed=false
        for ver in "$installed_vers"; do
          if [[ $ver == $this_ver ]]; then
            installed=true
          fi
        done
        if [[ $installed == true ]]; then
          echo gem $gem already installed
        else
          echo current version $installed_ver older than $this_ver
          run gem install --no-rdoc --no-ri $this_gem
        fi
      fi
      echo
    fi
  done
}

function install_production_symlinks {
  bigecho creating rakerunner.conf and nfs symlinks needed on production installs
  run ln -s $INSTALL_ROOT/$PROJ_NAME/rakerunner/rakerunner.conf /etc/rakerunner.conf
  run ln -s $NFS_CLIENTS_ROOT $INSTALL_ROOT/$PROJ_NAME/clients
  run ln -s $NFS_SOURCES_ROOT $INSTALL_ROOT/$PROJ_NAME/sources
}


# Install steps should be listed in order, each with a unique index
INSTALL_STEPS[1]='install_prerequisites'
INSTALL_STEPS[2]='install_ruby_etal'
INSTALL_STEPS[3]='install_rubygems'
INSTALL_STEPS[4]='install_rails'
INSTALL_STEPS[5]='install_and_setup_nfs'
INSTALL_STEPS[6]='checkout_project'
INSTALL_STEPS[7]='setup_project'
INSTALL_STEPS[8]='install_required_debs'
INSTALL_STEPS[9]='install_required_gems'
INSTALL_STEPS[10]='install_production_symlinks'


#------------------------------------------------------------------------------
# SANITY CHECK AND OPTIONS PARSING
#------------------------------------------------------------------------------

# Option parsing inspired by:
# http://www.spf13.com/sites/default/files/bash_skeleton.sh_0.txt

declare -r PROGNAME=$(basename $0)

function usage {
  echo "Usage: ${PROGNAME} [PROJ_NAME | PROJ_NAME:SVN_URL] [OPTIONS] [-h | --help]"
}

function helptext {
  echo "
  ${PROGNAME}

  Global Based project installer

  Installs to ${DEF_INSTALL_ROOT}/PROJ_NAME by default,
  set IB_ROOT enviromental variable to override.

  $(usage)
  
  Options:
    -h, --help      Print this help and exit.
        --force     Don't confirm install. 
        --nobanner  Hide ASCII art banner.
        --list      List projects that can be installed.
        --test      Print selected install options and exit."

  for step in ${INSTALL_STEPS[*]}; do
    echo "        --$step"
  done
}

# Ensure user is root and /var/www/apps/PROJ1 doen't exist
if [[ $USER != 'root' ]]; then
  bigecho "Script must be run as root"
  exit 1
fi

# Ensure apt-get available
which apt-get  > /dev/null
if [[ $? != 0 ]]; then
  bigecho "apt-get not installed or not in PATH."
  exit 1
fi

# comma separated list of install steps
INSTALL_STEP_OPTS=$(echo ${INSTALL_STEPS[*]} | sed -e 's/ /,/g')

# capture leading opts
declare -a LEADING_OPTS
while (( "$#" )); do
  if [[ `echo $1| grep '^-' -c` != 1 ]];then #$1 does not begin with -
    LEADING_OPTS[((${#LEADING_OPTS[*]} + 1))]=$1
    shift ;
  else
    break
  fi
done

# Note that we use `"$@"' to let each command-line parameter expand to
# a separate word. The quotes around `$@' are essential! We need
# GETOPT_TEMP as the `eval set --' would nuke the return value of
# getopt.
GETOPT_TEMP=$(getopt -o +h --long $INSTALL_STEP_OPTS,help,force,nobanner,list,test -n "$PROGNAME" -- "$@")

if [ $? != 0 ] ; then
    exit 1
fi

# Note the quotes around `$GETOPT_TEMP': they are essential!
eval set -- "$GETOPT_TEMP"

RUN_STEPS=""
# no error checking necessary; sanity of command line and required
# arguments has been checked by getopt program

while true ; do
    case $1 in
        "--${INSTALL_STEPS[1]}")
          RUN_STEPS="$RUN_STEPS 1"
          shift ;
          ;;
        "--${INSTALL_STEPS[2]}")
          RUN_STEPS="$RUN_STEPS 2"
          shift ;
          ;;
        "--${INSTALL_STEPS[3]}")
          RUN_STEPS="$RUN_STEPS 3"
          shift ;
          ;;
        "--${INSTALL_STEPS[4]}")
          RUN_STEPS="$RUN_STEPS 4"
          shift ;
          ;;
        "--${INSTALL_STEPS[5]}")
          RUN_STEPS="$RUN_STEPS 5"
          shift ;
          ;;
        "--${INSTALL_STEPS[6]}")
          RUN_STEPS="$RUN_STEPS 6"
          shift ;
          ;;
        "--${INSTALL_STEPS[7]}")
          RUN_STEPS="$RUN_STEPS 7"
          shift ;
          ;;
        "--${INSTALL_STEPS[8]}")
          RUN_STEPS="$RUN_STEPS 8"
          shift ;
          ;;
        "--${INSTALL_STEPS[9]}")
          RUN_STEPS="$RUN_STEPS 9"
          shift ;
          ;;
        "--${INSTALL_STEPS[10]}")
          RUN_STEPS="$RUN_STEPS 10"
          shift ;
          ;;
        -h|--help)
            helptext ;
            exit 0
            ;;
	      --force)
            FORCE=true
            shift ;
            ;;
	      --nobanner)
            NOBANNER=true
            shift ;
            ;;
        --list)
            echo "Projects"
            list_projects ;
            exit 0
            ;;
	      --test)
            IB_TEST=true
            shift ;
            ;;
        --)
            shift ;
            break
            ;;
        *)
            # should be impossible to reach: getopt should have caught an error
            exit 1
            ;;
    esac
done
unset GETOPT_TEMP
TRAILING_OPTS=$@

# Capture PROJ_NAME if specified and error if there's more than one
if [[ ${#LEADING_OPTS[*]} -gt 1 || ${#TRAILING_OPTS[*]} -gt 1 ]]; then
  echo "Too many arguments: ${LEADING_OPTS[*]} ${TRAILING_OPTS[*]}"
  echo 'You must specify only one PROJ_NAME'
  exit 1
elif [[ ${#LEADING_OPTS[*]} == 1 ]]; then
  PROJ_NAME=${LEADING_OPTS[1]}
elif [[ ${#TRAILING_OPTS[*]} == 1 ]]; then
  PROJ_NAME=${TRAILING_OPTS[1]}
fi

check_proj_name_for_repo

#------------------------------------------------------------------------------
# PROMPT USER FOR ANY NEEDED INPUT
#------------------------------------------------------------------------------

if [[ $NOBANNER != true ]]; then
  #Super secret high security encryption key. DO NOT TOUCH! ;)
  echo -en '\E[32;22m .___                 __    '
  echo '     .__  .__                 '
  echo -en '\E[32;1m |   | ____   _______/  |____'
  echo '__  |  | |  |   ___________  '
  echo -en '\E[32;22m |   |/    \ /  ___/\   __\_'
  echo '_  \ |  | |  | _/ __ \_  __ \ '
  echo -en '\E[32;1m |   |   |  \\\\_   \  |  |  '
  echo '/ __ \|  |_|  |_\  ___/|  | \/ '
  echo -en '\E[32;22m |___|___|  /____  > |__| (_'
  echo '___  /____/____/\___  >__|    '
  echo -en '\E[32;1m          \/     \/          '
  echo '  \/               \/        ' 
  echo -en '\E[31;1m    \=';
  echo -en '\E[31;22m         .  .  . . ...._'
  echo -e  '\E[34;1m            +//'
  echo -en '\E[31;1m    =]]]:>';
  echo -en '\E[31;22m      .  .  . . ...._'
  echo -e  '\E[34;1m        -{[||]}'
  echo -en '\E[31;1m    /=';
  echo -en '\E[31;22m         .  .  . . ...._'
  echo -e  '\E[34;1m            +\\\\ '
  echo -en '\E[33;22m        __________          '
  echo '                .___ '
  echo -en '\E[33;1m        \______   \_____    _'
  echo '_____ ____   __| _/ '
  echo -en '\E[33;22m         |    |  _/\__  \  /'
  echo '  ___// __ \ / __ |  '
  echo -en '\E[33;1m         |    |   \ / __ \_\_'
  echo '__ \\  ___// /_/ |  '
  echo -en '\E[33;22m         |______  /(____  /_'
  echo '___  >\___  >____ |  '
  echo -en '\E[33;1m                \/      \/   '
  echo '  \/     \/     \/ '
  echo -e "\E[0m"
  echo
else
  echo 'InstallerBased'
fi


# Prompt for PROJ_NAME if empty
if [ -z $PROJ_NAME ]; then
  echo "Choose a project to install"
  list_projects
  read PROJ_NAME
  if [[ -z $PROJ_NAME ]]; then
    echo "You must select a project to install."
    exit 1
  else
    echo
  fi
  check_proj_name_for_repo
fi
PROJ_PATH=$INSTALL_ROOT/$PROJ_NAME

# Check that the project exists
PROJ_REPO=$(get_project $PROJ_NAME)
if [[ $PROJ_REPO == '' ]]; then echo "'$PROJ_REPO'"
  echo "'$PROJ_NAME' is not a valid choice. Quitting."
  exit 1
fi

if [[ $OVERRIDE_REPO ]]; then
  echo "Overriding repo $PROJ_REPO with $OVERRIDE_REPO."
  PROJ_REPO=$OVERRIDE_REPO
fi


# Prompt for RUN_STEPS if empty
if [[ -z $RUN_STEPS && $FORCE != true ]];then
  echo 'Enter space separated list of steps to run or press enter to run all'
  cnt=1
  for step in ${INSTALL_STEPS[*]}; do
    echo "$cnt. $step"
    cnt=$(($cnt + 1))
  done
  read RUN_STEPS
fi

if [[ -z $RUN_STEPS ]]; then
  run_install_steps "${!INSTALL_STEPS[*]}"
else
  # Sort RUN_STEPS because latter steps sometimes depend on former
  RUN_STEPS=$(echo $RUN_STEPS | sed -e 's/ /\n/g' | sort)
  #TODO ensure all specified steps exist?
  run_install_steps "$RUN_STEPS"
fi
