#!/bin/bash
# this file will load all migrations into the database up to a certain point
# The script is expecting the filename to be in the format:
#   XY_databasename_description.sql
# where:
#   - XY is the order to use to load the migration
#   - databasename is the name of the database to create and use [A-Za-z0-9-]
#   - description is a generic short dash-separated description [A-Za-z0-9-]
# the script is also expecting to have at least a 00_databasename_description.sql file
# that it can use to extract the name of the database from.
#
# - author: Matteo Pescarin <matteo.pescarin[AT]steellondon.com>
#
#
# This code is provided 'as-is'
# and released under the GPLv2

# defaults
DEFAULT_PROJECT_ROOT="/vagrant"
DEFAULT_DB_SNAPSHOT_DIR="${DEFAULT_PROJECT_ROOT}/_database/"
MYSQL_ROOT_USER='root'
MYSQL_ROOT_PASS='password'
DEFAULT_DB_USER=$MYSQL_ROOT_USER
DEFAULT_DB_PASS=$MYSQL_ROOT_PASS

# application variables
#DB_NAME=""
#DB_SNAPSHOT=""
#PROJECT_ROOT=""
#DB_USER=""
#DB_PASS=""

# application related variables
VERSION="0.5"
NO_ARGS=0
E_OPTERROR=85
E_GENERROR=25
OLD_IFS="$IFS"
IFS=','

function usage() {
    echo -e "Syntax: `basename $0` [-h|-v] [-d <DB_NAME>] [-s <DB_SNAPSHOT>] [-u <DB_USER>] [-p <DB_PASS>] [-r <PROJECT_ROOT>]
\t-h: shows this help
\t-v: be verbose
\t-d <DB_NAME>: Name of the database to create
\t-u <DB_USER>: Name of the user to give credentials to the db <DB_NAME>
\t-p <DB_PASS>: Password for the <DB_USER>
\t-s <DB_SNAPSHOT>: absolute path to the SQL file to be used to fill the database
\t\tThe file can be compressed using either BZip2 or GZip compression.
\t-r <PROJECT_ROOT>: absolute path of the projcet root in the vagrant VM (no trailing slash)
\n"
}

function version() {
    echo -e "`basename $0` - Mysql Provisionin Script - version $VERSION\n"
}

function error() {
    version
    echo -e "Error: $1\n"
    usage
}

function quit {
    IFS=$OLD_IFS
    exit $1
}

function create_db() {
    [[ -n $BE_VERBOSE ]] && echo ">> Creating the database $DB_NAME"
    mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS} -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci"
    if [[ $DB_USER != $MYSQL_ROOT_USER ]]
    then
        [[ -n $BE_VERBOSE ]] && echo ">> Creating the user $DB_USER with password '${DB_PASS}'"
        mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS} -e "grant all privileges on ${DB_NAME}.* to '${DB_USER}'@'%' identified by '${DB_PASS}'"
    fi
}

function load_sql() {
    [[ -n $BE_VERBOSE ]] && echo ">> Loading $1 in the $DB_NAME db"

    # check if the DB snapshot $1 is compressed
    compression=`file "$1" | grep -oP "[gb]zip"`

    if [ $compression == 'gzip' ]
    then
        [[ -n $BE_VERBOSE ]] && echo "!! Found GZip archive, uncompressing on the fly."
        zcat $1 | mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS} $DB_NAME
    elif [ $compression == 'bzip' ]
    then
        [[ -n $BE_VERBOSE ]] && echo "!! Found BZip2 archive, uncompressing on the fly."
        bzcat $1 | mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS} $DB_NAME
    else
        # no compression or wrong file... let's leave it to mysql
        mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS} $DB_NAME < $1
    fi
}

# no problems if there are no arguments passed, we'll use the default arguments
#if [ $# -eq "$NO_ARGS" ]; then
#    version
#    usage
#    quit $E_OPTERROR
#fi

# The expected flags are
#  h v r
while getopts ":hvd:u:p:s:" Option
do
    case $Option in
        h ) version
            usage
            quit 0
            ;;
        v ) BE_VERBOSE=true
            ;;
        d ) DB_NAME=$OPTARG
			;;
        u ) DB_USER=$OPTARG
			;;
        p ) DB_PASS=$OPTARG
			;;
        s ) [ ! -e $OPTARG ] && error "'$OPTARG' not accessible" && quit $E_OPTERROR
            DB_SNAPSHOT=$OPTARG
            ;;
        r ) [ ! -e $OPTARG ] && error "'$OPTARG' not accessible" && quit $E_OPTERROR
            PROJECT_ROOT=$OPTARG
            ;;
    esac
done

# Decrements the argument pointer so it points to next argument.
# $1 now references the first non-option item supplied on the command-line
# if one exists.
shift $(($OPTIND - 1))

# initialise the missing variables
if [[ ! -n $PROJECT_ROOT ]]
then
    PROJECT_ROOT=${DEFAULT_PROJECT_ROOT}
fi

if [[ ! -n $DB_USER ]]
then
    DB_USER=${DEFAULT_DB_USER}
fi

if [[ ! -n $DB_PASS ]]
then
    DB_PASS=${DEFAULT_DB_PASS}
fi

# DEPRECATED - retro-compatibility stuff
# DB_SNAPSHOT and DB_NAME has not been passed
if [[ ! -n $DB_SNAPSHOT && ! -n $DB_NAME ]]
then
    [[ -n $BE_VERBOSE ]] && echo ">> No snapshot defined, trying to guess."
    # let's look in DEFAULT_DB_SNAPSHOT_DIR
    if [[ -e $DEFAULT_DB_SNAPSHOT_DIR ]]
    then
        # if there's more than one file everything will fail
        for file in ${DEFAULT_DB_SNAPSHOT_DIR}*.sql
        do
            [[ -n $BE_VERBOSE ]] && echo ">> Found snapshot $file"
            DB_SNAPSHOT=$file
            DB_NAME=`basename $file .sql`
        done
    fi
fi

if [[ ! -n $DB_SNAPSHOT && -n $DB_NAME ]]
then
    # no snapshot, but we have a db name, create only
    echo ">> no snapshot defined, db '${DB_NAME}' creation only."
    CREATE_DB_ONLY=true
elif [[ -n $DB_SNAPSHOT && ! -n $DB_NAME ]]
then
    echo ">> snapshot defined, no db defined. Guessing."
    DB_NAME=`basename $DB_SNAPSHOT .sql`
fi

[[ -n $BE_VERBOSE ]] && echo ">> PROJECT_ROOT: ${PROJECT_ROOT}"
[[ -n $BE_VERBOSE ]] && echo ">> DB_NAME     : ${DB_NAME}"
[[ -n $BE_VERBOSE ]] && echo ">> DB_USER     : ${DB_USER}"
[[ -n $BE_VERBOSE ]] && echo ">> DB_PASS     : ${DB_PASS}"
[[ -n $BE_VERBOSE && -n $DB_SNAPSHOT ]] && echo ">> DB_SNAPSHOT : ${DB_SNAPSHOT}"

# no snapshot no party
if [[ ! -n ${DB_NAME} && ! -n ${DB_SNAPSHOT} ]]
then
    [[ -n $BE_VERBOSE ]] && echo ">> No snapshot and no db defined. Exiting."
    exit 0
fi


[[ -n $BE_VERBOSE ]] && echo ">> Creating db ${DB_NAME}"
create_db
if [[ ! -n $CREATE_DB_ONLY ]]
then
    [[ -n $BE_VERBOSE ]] && echo ">> Filling db with ${DB_SNAPSHOT}"
    load_sql $DB_SNAPSHOT
fi

exit 0
