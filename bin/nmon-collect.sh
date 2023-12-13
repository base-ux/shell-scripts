#!/usr/bin/ksh
#
# Run nmon statistics collection
#

# Source common library file
BASE_DIR=/usr/scripts
SYS_LIB=${BASE_DIR}/lib/_sys.lib
if [[ ! -f ${SYS_LIB} ]]; then
    # If we can't source _sys.lib we can't do anything
    echo "$0: ${SYS_LIB} not found" >&2 && exit 1
fi
. ${SYS_LIB}

# Source reqired library files
eval $(sys_source_lib fs)

################
# Functions
################

# Show usage help
function prog_usage
{
    echo "Usage: ${PROG_NAME} [-c conffile] [-d dir] [-n count] [-o opts] [-s seconds]"
    exit 1
}

# Get command line arguments
function prog_getopts
{
    typeset _opt

    while getopts :c:d:n:o:s: _opt
    do
	case ${_opt} in
	    c)
		CONF_FILE="${OPTARG}"
		fs_is_abspath ${CONF_FILE} || CONF_FILE=${SYS_PWD}/${CONF_FILE}
		;;
	    d)
		sys_setoptvar NMON_DIR="${OPTARG}"
		;;
	    n)
		sys_setoptvar NMON_COUNT="${OPTARG}"
		;;
	    o)
		sys_setoptvar NMON_OPTS="${OPTARG}"
		;;
	    s)
		sys_setoptvar NMON_SECONDS="${OPTARG}"
		;;
	    :)
		sys_err_msg "argument missing for option '${OPTARG}'"
		prog_usage
		;;
	    ?)
		sys_err_msg "wrong option '${OPTARG}'"
		prog_usage
		;;
	esac
    done
    shift $((${OPTIND} - 1))
    if [[ $# -ne 0 ]]; then
	sys_err_msg "wrong options '$@'"
	prog_usage
    fi
}

################
# Main
################

# Uncomment the next line for functions debug
#for i in $(typeset +f); do typeset -ft $i; done

# Default configuration file in ${CONF_DIR} directory
CONF_FILE=${CONF_DIR}/nmon.conf

# Default values for configuration variables
sys_setdefvar NMON_DIR="/var/nmon"
sys_setdefvar NMON_OPTS="-ftdALM"
sys_setdefvar NMON_SECONDS="60"
sys_setdefvar NMON_COUNT="1440"

# Get command line arguments
prog_getopts "$@"

# Read configuration file
sys_read_conf ${CONF_FILE}

# Set variables (from default, config, environment and options)
sys_setvars

#
# Well, we've got all for the work. :)
#

# Create directory if does not exist
if [[ ! -d ${NMON_DIR} ]]; then
    mkdir -m 0775 ${NMON_DIR}
fi

# Run nmon
eval /usr/bin/nmon ${NMON_OPTS} -s ${NMON_SECONDS} -c ${NMON_COUNT} -m ${NMON_DIR}
